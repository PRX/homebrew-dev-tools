AWS_CONFIG_FILE = ENV["AWS_CONFIG_FILE"] || "#{Dir.home}/.aws/config"

class RubyAwsCreds
  class << self
    def cache_directory
      "#{Dir.home}/.aws/ruby/cache"
    end

    def cache_key_path(assume_role_options)
      # The cache key is based on the parameters used for the AssumeRole call.
      # The role session name is removed if it's randomly generated (which it
      # always is for us). If the options were ever to include a policy document,
      # that should get sorted before hashing.
      # https://github.com/boto/botocore/blob/88d780dea1684da00689f2eef388fa4c782ced08/botocore/credentials.py#L700
      key_opts = assume_role_options.clone
      key_opts.delete(:role_session_name)
      cache_key = Digest::SHA1.hexdigest(JSON.dump(key_opts))

      "#{cache_directory}/#{cache_key}.json"
    end

    # Returns the options passed to SSO#get_role_credentials. This is used when the
    # profile uses an SSO, rather than a key/secret. If the selected profile is
    # not configured for SSO, returns nil.
    def sso_get_role_options
      aws_config_file = IniFile.load(AWS_CONFIG_FILE)
      aws_config_file_section = aws_config_file["profile #{OPTS[:profile]}"]

      if aws_config_file_section["sso_start_url"]
        profile_start_url = aws_config_file_section["sso_start_url"]

        sso_access_token = nil
        Dir["#{Dir.home}/.aws/sso/cache/*.json"].each do |path|
          data = JSON.parse(File.read(path))
          if data["startUrl"] && data["startUrl"] == profile_start_url
            sso_access_token = data["accessToken"]
            break
          end
        end

        if !sso_access_token
          raise "No SSO access token was found for this profile. Run 'aws sso login --profile #{OPTS[:profile]}' to fetch a valid token."
        end

        {
          role_name: aws_config_file_section["sso_role_name"],
          account_id: aws_config_file_section["sso_account_id"].to_s,
          access_token: sso_access_token
        }
      end
    end

    # Returns the options passed to AssumeRole. This is used when the profile uses
    # a key/secret. If the selected profile is not configured for key/secret,
    # returns nil.
    def assume_role_options
      aws_config_file = IniFile.load(AWS_CONFIG_FILE)
      aws_config_file_section = aws_config_file["profile #{OPTS[:profile]}"]
      role_arn = aws_config_file_section["role_arn"]
      role_name = role_arn.split("role/")[1]
      account_id = role_arn.split(":")[4]

      {
        role_arn: "arn:aws:sts::#{account_id}:role/#{role_name}",
        role_session_name: "ruby-sdk-session-#{Time.now.to_i}",
        duration_seconds: 3600
      }
    end

    def get_and_cache_credentials
      FileUtils.mkdir_p cache_directory

      aws_config_file = IniFile.load(AWS_CONFIG_FILE)
      aws_config_file_section = aws_config_file["profile #{OPTS[:profile]}"]

      if aws_config_file_section["sso_role_name"]
        opts = sso_get_role_options

        sso = Aws::SSO::Client.new(region: aws_config_file_section["region"])
        credentials = sso.get_role_credentials(opts)

        File.write(cache_key_path(opts), JSON.dump({"credentials" => {
          "access_key_id" => credentials.role_credentials.access_key_id,
          "secret_access_key" => credentials.role_credentials.secret_access_key,
          "session_token" => credentials.role_credentials.session_token
        }}))

        Aws::Credentials.new(credentials.role_credentials.access_key_id, credentials.role_credentials.secret_access_key, credentials.role_credentials.session_token)
      elsif aws_config_file_section["mfa_serial"]
        mfa_serial = aws_config_file_section["mfa_serial"]

        mfa_code = $stdin.getpass("Enter MFA code for #{mfa_serial}: ")
        credentials = Aws.shared_config.assume_role_credentials_from_config(profile: OPTS[:profile], token_code: mfa_code.chomp)
        sts = Aws::STS::Client.new(
          region: "us-east-1",
          credentials: credentials
        )
        _id = sts.get_caller_identity

        opts = assume_role_options
        cacheable_role = sts.assume_role(assume_role_options)
        File.write(cache_key_path(opts), JSON.dump(cacheable_role.to_h))

        Aws::Credentials.new(cacheable_role["credentials"]["access_key_id"], cacheable_role["credentials"]["secret_access_key"], cacheable_role["credentials"]["session_token"])
      end
    rescue Aws::SSO::Errors::UnauthorizedException
      raise "The SSO access token for this profile is invalid. Run 'aws sso login --profile #{OPTS[:profile]}' to fetch a valid token."
    end

    def load_and_verify_cached_credentials
      # Look up the cache file based on the options for the seleted profile.
      options = sso_get_role_options || assume_role_options

      cached_role_json = File.read(cache_key_path(options))
      cached_role = JSON.parse(cached_role_json)

      credentials = Aws::Credentials.new(cached_role["credentials"]["access_key_id"], cached_role["credentials"]["secret_access_key"], cached_role["credentials"]["session_token"])

      # Verify that the credentials still work; this will raise an error if they're
      # bad, which we can catch
      sts = Aws::STS::Client.new(region: "us-east-1", credentials: credentials)
      sts.get_caller_identity

      credentials
    rescue Aws::STS::Errors::ExpiredToken
      get_and_cache_credentials
    rescue Aws::STS::Errors::InvalidClientTokenId
      get_and_cache_credentials
    rescue Errno::ENOENT
      get_and_cache_credentials
    end

    # Returns temporary client credentials for the profile selected with --profile
    # when the command was run.
    def client_credentials
      # For the selected profile, get the appropriate set of options.
      options = sso_get_role_options || assume_role_options

      return if !options

      # Check for a cache file with a name derived from those options.
      if !File.file?(cache_key_path(options))
        # When no cache exists for these options, fetch new credentials, cache them
        # and return them.
        get_and_cache_credentials
      else
        # When there is a cache for these options, return them if they are still
        # valid, otherwise refresh them and return the new credentials.
        load_and_verify_cached_credentials
      end
    end
  end
end
