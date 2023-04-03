#!/usr/bin/env ruby
# Lists all SSM Parameter Store parameters that exist in any of the given
# regions under one or more paths.

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
  gem "tty-table"
  gem "inifile"
  gem "slop"
end

# All parameters under these paths will be checked by default
default_paths = ["/prx/global/Spire", "/prx/stag/Spire"]

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--paths", 'Paths (e.g., "/foo,/bar")', default: default_paths.join(",")
  o.string "--region", 'Region (e.g., "us-east-1")', required: true
  o.on "-h", "--help" do
    puts o
    exit
  end
end

paths = OPTS[:paths].split(",")
region = OPTS[:region]

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

def assume_role_options
  aws_config_file = IniFile.load("#{Dir.home}/.aws/config")
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

  aws_config_file = IniFile.load("#{Dir.home}/.aws/config")
  aws_config_file_section = aws_config_file["profile #{OPTS[:profile]}"]
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

def load_and_verify_cached_credentials
  cached_role_json = File.read(cache_key_path(assume_role_options))
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

def client_credentials
  if !File.file?(cache_key_path(assume_role_options))
    get_and_cache_credentials
  else
    load_and_verify_cached_credentials
  end
end

client = Aws::SSM::Client.new(region: region, credentials: client_credentials)

headings = ["Parameter Name", "🔒", "Parameter Value"]
rows = []

paths.each do |path|
  client.get_parameters_by_path({path: path, recursive: true, with_decryption: true}).each do |resp|
    parameters = resp[:parameters]

    parameters.each do |parameter|
      row = if parameter.name.include?("/prod/")
        [parameter.name.purple]
      elsif parameter.name.include?("/stag/")
        [parameter.name.yellow]
      elsif parameter.name.include?("/global/")
        [parameter.name.blue]
      else
        [parameter.name]
      end

      row << if parameter.type == "SecureString"
        "🔒"
      else
        "➖"
      end

      row << parameter.value[0, 120]

      rows.push(row)
    end
  end
end

table = TTY::Table.new headings, rows
puts table.render(:unicode, multiline: true)
