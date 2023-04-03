#!/usr/bin/env ruby
# For all SSM Parameter Store parameters under a given path in some single
# region, copies their values to identically names parameters in a set of other
# regions.

require "bundler/inline"
require "json"
require "io/console"
require "fileutils"
require "digest"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-ssm"
  gem "nokogiri"
  gem "terminal-table"
  gem "inifile"
  gem "slop"
end

# All parameters under these paths will be checked by default
default_paths = ["/prx/global/Spire", "/prx/stag/Spire"]

AWS_CONFIG_FILE = ENV["AWS_CONFIG_FILE"] || "#{Dir.home}/.aws/config"

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--paths", 'Paths (e.g., "/foo,/bar")', default: default_paths.join(",")
  o.string "--source-region", 'Source region (e.g., "us-east-1")', required: true
  o.string "--destination-regions", 'Destination regions (e.g., "us-west-1,us-west-2")', required: true
  o.bool "--list-matches", "List matching values"
  o.bool "--dry-run", "Generate list without offering to sync"
  o.on "-h", "--help" do
    puts o
    exit
  end
end

source_region = OPTS[:source_region]
destination_regions = OPTS[:destination_regions].split(",")

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

# Create an SSM client for the source region and each destination region from
# the command input
clients = {}
clients[source_region] = Aws::SSM::Client.new(region: source_region, credentials: client_credentials)
destination_regions.each do |region|
  clients[region] = Aws::SSM::Client.new(region: region, credentials: client_credentials)
end

# Create a lookup table that includes all Parameter Store parameters from the
# source and destination regions for all parameters under the provided paths.
# e.g., { '/foo/bar': { 'us-east-1': aParam, 'us-west-2': aParam } }
# Values would be accessed via: lookup['/foo/bar']['us-east-1'].value
lookup = {}
clients.each do |region, client|
  OPTS[:paths].split(",").each do |path|
    client.get_parameters_by_path({path: path, recursive: true, with_decryption: true}).each do |resp|
      parameters = resp[:parameters]

      parameters.each do |parameter|
        if !lookup[parameter.name]
          lookup[parameter.name] = {}
        end

        lookup[parameter.name][region] = parameter
      end
    end
  end
end

headings = ["Parameter Name", "Source: #{source_region}", *destination_regions]
rows = []

# Find the parameters that exist in the source region
source_region_parameter_names = lookup.keys.filter { |k| !lookup[k][source_region].nil? }

# Keep track of how many parameters will be changed
pending_updates = 0

# Iterate through all the parameters that exist in the source region, to build
# a list that shows how other regions will be affected by the sync
source_region_parameter_names.each do |source_parameter_name|
  region_params = lookup[source_parameter_name]

  source_param = region_params[source_region]

  # Cell 1: the name of the parameter, color coded by environment
  row = if source_parameter_name.include?("/prod/")
    [source_parameter_name.purple]
  elsif source_parameter_name.include?("/stag/")
    [source_parameter_name.yellow]
  elsif source_parameter_name.include?("/global/")
    [source_parameter_name.blue]
  else
    [source_parameter_name]
  end

  # Cell 2: The value from the source region
  source_value = source_param.value
  text = ((source_value.length < 21) ? source_value : "#{source_value[0..18].strip}…")
  row << text

  # Cell 3-X: The change that will occur in each destination region
  destination_regions.each do |dest_region|
    destination_param = region_params[dest_region]

    if destination_param
      if destination_param.value == source_param.value && destination_param.type == source_param.type
        # Value and type match the source region
        row << "MATCH"
      elsif destination_param.type == source_param.type
        # Type matches, but value doesn't match source region. The value can
        # be updated.
        pending_updates += 1
        row << "UPDATE".yellow
      else
        # Value matches, but type doesn't match the source region. The
        # parameter needs to be recreated with the correct type
        pending_updates += 1
        row << "REPLACE".red
      end
    else
      # Parameter doesn't exist in the destination region and needs to be added
      pending_updates += 1
      row << "ADD".green
    end
  end

  # If the parameter exists in all regions and they're all the same value and
  # type, consider them to be in sync
  all_match = region_params.keys.length == clients.keys.length && region_params.values.map(&:value).uniq.count == 1 && region_params.values.map(&:type).uniq.count == 1

  # Include a row for the parameter if there's any mismatch, or if list-matches
  # option was true on the command
  if !all_match || OPTS[:list_matches]
    rows << row
  end
end

puts Terminal::Table.new headings: headings, rows: rows

if pending_updates == 0
  print "Found nothing to synchronize\n\n"
  return
end

if OPTS[:dry_run]
  return
end

print "Synchronize these #{pending_updates} parameters from #{source_region.blue} to #{destination_regions.join(", ").red} [y/N]: "
confirmation = $stdin.gets.chomp

if confirmation != "y"
  return
end

# Perform updates
source_region_parameter_names.each do |source_parameter_name|
  region_params = lookup[source_parameter_name]

  source_parameter = region_params[source_region]

  destination_regions.each do |dest_region|
    destination_param = region_params[dest_region]
    client = clients[dest_region]

    if destination_param
      if destination_param.value == source_parameter.value && destination_param.type == source_parameter.type
        # Do nothing
      elsif destination_param.type == source_parameter.type
        puts "#{"Updating".yellow} #{source_parameter.type} #{source_parameter_name.gray} in #{dest_region}"
        client.put_parameter({name: source_parameter_name, value: source_parameter.value, type: source_parameter.type, overwrite: true})
      else
        puts "#{"Replacing".red} #{source_parameter.type} #{source_parameter_name.gray} in #{dest_region}"
        client.delete_parameter({name: source_parameter_name})
        client.put_parameter({name: source_parameter_name, value: source_parameter.value, type: source_parameter.type})
      end
    else
      puts "#{"Adding".green} #{source_parameter.type} #{source_parameter_name.gray} to #{dest_region}"
      client.put_parameter({name: source_parameter_name, value: source_parameter.value, type: source_parameter.type})
    end
  end
end

print "\n"