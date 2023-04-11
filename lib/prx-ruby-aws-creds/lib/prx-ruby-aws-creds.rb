require "json"
require "digest"
require "time"
require "fileutils"
require "io/console"
require "inifile"
require "aws-sdk-core"
require "aws-sdk-sts"
require "aws-sdk-sso"

CACHE_DIRECTORY = "#{Dir.home}/.aws/ruby/cache"
AWS_CONFIG_FILE = ENV["AWS_CONFIG_FILE"] || "#{Dir.home}/.aws/config"

class PrxRubyAwsCreds
  class << self
    # The cache key is based on the parameters used to request temporary
    # credentials (using either STS AssumeRole or SSO GetRoleCredentials). The
    # role session name is removed if it's randomly generated (which it always
    # is for us). If the options were ever to include a policy document, that
    # should get sorted before hashing.
    # https://github.com/boto/botocore/blob/88d780dea1684da00689f2eef388fa4c782ced08/botocore/credentials.py#L700
    #
    # For any
    def cache_key_path(role_options)
      key_opts = role_options.clone
      key_opts.delete(:role_session_name)
      key_opts.delete(:access_token)
      cache_key = Digest::SHA1.hexdigest(JSON.dump(key_opts))

      "#{CACHE_DIRECTORY}/#{cache_key}.json"
    end

    # For a given SSO start URL, return a valid access token from the cache. If
    # no valid token is found, returns nil. An access token will only be
    # considered valid if it has not expired.
    def sso_get_cached_access_token(start_url)
      Dir["#{Dir.home}/.aws/sso/cache/*.json"].each do |path|
        data = JSON.parse(File.read(path))
        if data["startUrl"] && data["startUrl"] == start_url
          expiration = Time.parse(data["expiresAt"])

          if expiration > Time.now
            return data["accessToken"]
          end
        end
      end

      nil
    end

    # Returns the options passed to SSO#get_role_credentials. This is used when
    # the profile uses an SSO, rather than a key/secret. If the selected
    # profile is not configured for SSO, returns nil.
    #
    # `role_name` and `account_id` are values found in the config file for the
    # given profile. `access_token` is a SSO token found in the SSO cache for
    # the SSO start URL associated with the given profile.
    def sso_get_role_options(profile_name)
      aws_config_file = IniFile.load(AWS_CONFIG_FILE)
      aws_config_file_section = aws_config_file["profile #{profile_name}"]

      # The selected profile does not use SSO
      return if !aws_config_file_section["sso_start_url"]

      # Get the SSO start URL for the selected profile
      profile_start_url = aws_config_file_section["sso_start_url"]

      sso_access_token = sso_get_cached_access_token(profile_start_url)

      # If a valid token wasn't found in the cache, prompt the user to fetch a
      # new one.
      if !sso_access_token
        puts
        puts "No #{"access token".yellow} was found for this SSO start URL associated with this profile (#{profile_start_url.blue})."
        puts "Press #{"RETURN".green} to request a new token. This will open a web browser."
        puts "You can also do this manually with: 'aws sso login --profile #{profile_name}'".gray
        puts
        inp = $stdin.gets.chomp
        `aws sso login --profile #{profile_name}` if inp.empty?
        sso_access_token = sso_get_cached_access_token(profile_start_url)
        puts "This #{"access token".yellow} is valid for all SSO profiles using #{profile_start_url.blue} as their start URL."
        puts
      end

      {
        role_name: aws_config_file_section["sso_role_name"],
        account_id: aws_config_file_section["sso_account_id"].to_s,
        access_token: sso_access_token
      }
    end

    # Returns the options passed to AssumeRole. This is used when the profile
    # uses a key/secret. If the selected profile is not configured for
    # key/secret, returns nil.
    def assume_role_options(profile_name)
      aws_config_file = IniFile.load(AWS_CONFIG_FILE)
      aws_config_file_section = aws_config_file["profile #{profile_name}"]

      # Get the role ARN for the selected profile
      role_arn = aws_config_file_section["role_arn"]

      # Extract some values from the ARN
      role_name = role_arn.split("role/")[1]
      account_id = role_arn.split(":")[4]

      {
        role_arn: "arn:aws:sts::#{account_id}:role/#{role_name}",
        role_session_name: "ruby-sdk-session-#{Time.now.to_i}",
        duration_seconds: 3600
      }
    end

    # Makes a request to some AWS API endpoint that can generate temporary IAM
    # credentials (e.g., AssumeRole, GetRoleCredentials, etc) based on the
    # configuration of the selected profile.
    #
    # Cache the resulting credentials in the CACHE_DIRECTORY. The file is named
    # using a hash of the options passed to the endpoint.
    def get_and_cache_credentials(profile_name)
      # Make sure the cache directory exists
      FileUtils.mkdir_p CACHE_DIRECTORY

      aws_config_file = IniFile.load(AWS_CONFIG_FILE)
      aws_config_file_section = aws_config_file["profile #{profile_name}"]

      if aws_config_file_section["sso_role_name"]
        # For SSO profiles, call GetRoleCredentials with a role, account, and
        # access token to get back a set of temporary credentials.
        # https://docs.aws.amazon.com/singlesignon/latest/PortalAPIReference/API_GetRoleCredentials.html
        # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SSO/Client.html#get_role_credentials-instance_method
        opts = sso_get_role_options(profile_name)
        sso = Aws::SSO::Client.new(region: aws_config_file_section["sso_region"])
        credentials = sso.get_role_credentials(opts)

        # Cache the credentials. The structure of this file doesn't exactly
        # match what native libraries (boto, etc) use. Instead, it matches the
        # default output of assume_role. It could be anything, it just needs
        # to be consistent across profile types, and match what
        # load_and_verify_cached_credentials expects.
        File.write(cache_key_path(opts), JSON.dump({"credentials" => {
          "access_key_id" => credentials.role_credentials.access_key_id,
          "secret_access_key" => credentials.role_credentials.secret_access_key,
          "session_token" => credentials.role_credentials.session_token
        }}))

        # Return the temporary IAM credentials
        Aws::Credentials.new(credentials.role_credentials.access_key_id, credentials.role_credentials.secret_access_key, credentials.role_credentials.session_token)
      elsif aws_config_file_section["mfa_serial"]
        # For profiles using an API key with an MFA token, get the serial
        # number of the MFA device associated with the profile.
        mfa_serial = aws_config_file_section["mfa_serial"]

        # Prompt the user for the current TOTP code associated with the MFA
        # device.
        mfa_code = $stdin.getpass("Enter MFA code for #{mfa_serial}: ")

        # Get a set of credentials for the role configured in the profile using
        # the TOTP code. I don't remember why, but I don't think these
        # credentials should be used for anything other than making another
        # call to assume_role. Don't cache or return these credentials.
        # Note: This is marked as a private API
        credentials = Aws.shared_config.assume_role_credentials_from_config(profile: profile_name, token_code: mfa_code.chomp)
        sts = Aws::STS::Client.new(region: "us-east-1", credentials: credentials)

        # Make a call to get_caller_identity to ensure that the first set of
        # credentials are valid?
        _id = sts.get_caller_identity

        # Make a regular assume_role call to get standard temporary IAM
        # credentials.
        opts = assume_role_options
        cacheable_role = sts.assume_role(opts)
        File.write(cache_key_path(opts), JSON.dump(cacheable_role.to_h))

        # Return the temporary IAM credentials
        Aws::Credentials.new(cacheable_role["credentials"]["access_key_id"], cacheable_role["credentials"]["secret_access_key"], cacheable_role["credentials"]["session_token"])
      end
    rescue Aws::SSO::Errors::UnauthorizedException
      raise "The SSO access token for this profile is invalid. Run 'aws sso login --profile #{profile_name}' to fetch a valid token."
    end

    # For the selected profile, look for a set of cached temporary IAM
    # credentials. These are vanilla IAM credentials that look the same
    # regardless of what type of profile is selected (SSO, MFA, etc).
    #
    # If no cached credential exist for the profile, or if the credentials are
    # invalid (i.e., can't successfully call get_caller_identity), a new set
    # of credentials will be fetched and cached.
    def load_and_verify_cached_credentials(profile_name)
      # Look up the cache file based on the options for the seleted profile.
      options = sso_get_role_options(profile_name) || assume_role_options(profile_name)

      cached_role_json = File.read(cache_key_path(options))
      cached_role = JSON.parse(cached_role_json)

      credentials = Aws::Credentials.new(cached_role["credentials"]["access_key_id"], cached_role["credentials"]["secret_access_key"], cached_role["credentials"]["session_token"])

      # Verify that the credentials still work; this will raise an error if they're
      # bad, which we can catch
      sts = Aws::STS::Client.new(region: "us-east-1", credentials: credentials)
      sts.get_caller_identity

      credentials
    rescue Aws::STS::Errors::ExpiredToken
      get_and_cache_credentials(profile_name)
    rescue Aws::STS::Errors::InvalidClientTokenId
      get_and_cache_credentials(profile_name)
    rescue Errno::ENOENT
      get_and_cache_credentials(profile_name)
    end

    # Returns temporary IAM client (Aws::Credentials) credentials for a given
    # profile.
    def client_credentials(profile_name = nil)
      profile_name ||= OPTS[:profile]

      # For the selected profile, get the appropriate set of options.
      options = sso_get_role_options(profile_name) || assume_role_options(profile_name)

      return if !options

      # Check for a cache file with a name derived from those options.
      if !File.file?(cache_key_path(options))
        # When no cache exists for these options, fetch new credentials, cache them
        # and return them.
        get_and_cache_credentials(profile_name)
      else
        # When there is a cache for these options, return them if they are still
        # valid, otherwise refresh them and return the new credentials.
        load_and_verify_cached_credentials(profile_name)
      end
    end
  end
end
