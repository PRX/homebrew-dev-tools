#!/usr/bin/env ruby

require "bundler/inline"
require "json"
require "io/console"
require "fileutils"
require "digest"
require "time"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "inifile"
  gem "aws-sdk-sts"
  gem "aws-sdk-sso"
  gem "nokogiri"
end

AWS_CONFIG_FILE = ENV["AWS_CONFIG_FILE"] || "#{Dir.home}/.aws/config"

# Look through the native SSO cache to find a token that appears to be
# associated with the given start URL. If the token hasn't expired, returns
# that token.
def get_cached_sso_access_token(profile_start_url)
  sso_access_token = nil

  Dir["#{Dir.home}/.aws/sso/cache/*.json"].each do |path|
    data = JSON.parse(File.read(path))
    if data["startUrl"] && data["startUrl"] == profile_start_url
      if Time.parse(data["expiresAt"]) > Time.now
        sso_access_token = data["accessToken"]
        break
      end
    end
  end

  sso_access_token
end

def get_iam_credentials(sso_region, role_name, account_id, sso_access_token)
  sso = Aws::SSO::Client.new(region: sso_region)

  role_creds = sso.get_role_credentials({
    role_name: role_name,
    account_id: account_id.to_s,
    access_token: sso_access_token
  })

  role_creds[:role_credentials]
end

# Load the AWS config INI file
aws_config_file = IniFile.load(AWS_CONFIG_FILE)

# Find the name of each profile that appears to use SSO
sso_profile_names = []
aws_config_file.each_section do |section|
  if section.start_with?("profile") && (aws_config_file[section]["sso_start_url"] || aws_config_file[section]["sso_session"])
    sso_profile_names.push(section.gsub(/^profile /, ""))
  end
end

if sso_profile_names.length == 0
  puts "No profiles were found in ~/.aws/config with SSO configurations!\n".red
  return
end

puts "\nThe following profiles are configured for SSO access:"
sso_profile_names.each_with_index { |name, idx| puts "  #{idx + 1}. #{name.yellow}" }
print "\nShow SSO information for profile [1]: "
sso_profile_selection = $stdin.gets.chomp
puts

# Default selection
sso_profile_selection = "1" if sso_profile_selection.empty?

if /^[0-9]+$/.match?(sso_profile_selection)
  idx_selection = sso_profile_selection.to_i - 1

  if sso_profile_names[idx_selection]
    sso_selected_profile_name = sso_profile_names[idx_selection]

    # Get the config values from the INI file for the selected profile
    aws_config_file_section = aws_config_file["profile #{sso_selected_profile_name}"]
    sso_region = aws_config_file_section["sso_session"] ? aws_config_file["sso-session #{aws_config_file_section["sso_session"]}"]["sso_region"] : aws_config_file_section["sso_region"]
    account_id = aws_config_file_section["sso_account_id"]
    role_name = aws_config_file_section["sso_role_name"]
    profile_start_url = aws_config_file_section["sso_session"] ? aws_config_file["sso-session #{aws_config_file_section["sso_session"]}"]["sso_start_url"] : aws_config_file_section["sso_start_url"]

    # Look for an SSO access token in the cache
    sso_access_token = get_cached_sso_access_token(profile_start_url)

    envar = "export AWS_PROFILE=#{sso_selected_profile_name}".purple
    puts "  1. Copy #{envar} to the clipboard."
    puts "     When AWS_PROFILE is set to #{sso_selected_profile_name} in a shell, the AWS CLI make"
    puts "     requests using the #{role_name.blue} role to the #{sso_selected_profile_name.blue} account."
    puts ""
    puts "  2. Copy temporary IAM credentials to the clipboard."
    puts "     When these credentials are set as environment variables in a shell, all AWS SDK"
    puts "     clients (CLI, Ruby, etc) will implicitly use them to make requests using the"
    puts "     #{role_name.blue} role in the #{sso_selected_profile_name.blue} account."

    login_cmd = "aws sso login --profile #{sso_selected_profile_name}".green
    puts ""
    puts "  3. Run #{login_cmd} immediately."
    puts "     Create or refresh the SSO access token (not IAM credentials)."
    puts ""

    if sso_access_token
      print "There appears to be a valid SSO token [1]: "
    else
      print "Your browser will open to complete SSO login [1]: "
    end

    command_selection = $stdin.gets.chomp
    puts

    command_selection = "1" if command_selection.empty?

    # Just do the login and exit
    if command_selection == "3"
      `aws sso login --profile #{sso_selected_profile_name}`
      puts
      return
    end

    # Other options should ensure that the current SSO token is valid, and
    # perform a login to refresh the token if not. Once there's a valid token,
    # copy the requested value to the clipboard

    # If no cached token was found, perform an SSO login for the selected
    # profile, and then get the token from the cache
    if !sso_access_token
      `aws sso login --profile #{sso_selected_profile_name}`
      sso_access_token = get_cached_sso_access_token(profile_start_url)
    end

    # Ensure that the access token can be used to get actual role credentials.
    # If it can't, force a new SSO login to upsert the cache.
    creds = nil
    begin
      creds = get_iam_credentials(sso_region, role_name, account_id, sso_access_token)
    rescue Aws::SSO::Errors::UnauthorizedException
      puts "The cached SSO token was invalid. A browser will open to login and fetch a fresh token.".red

      `aws sso login --profile #{sso_selected_profile_name}`
      sso_access_token = get_cached_sso_access_token(profile_start_url)

      # Confirm the login worked by getting some credentials with the token
      creds = get_iam_credentials(sso_region, role_name, account_id, sso_access_token)
    end

    if command_selection == "1"
      var_string = "export AWS_PROFILE=#{sso_selected_profile_name}"
      `echo #{var_string} | pbcopy`
    elsif command_selection == "2"
      access_key_id = creds[:access_key_id]
      secret_access_key = creds[:secret_access_key]
      session_token = creds[:session_token]

      var_string = "AWS_ACCESS_KEY_ID=#{access_key_id} AWS_SECRET_ACCESS_KEY=#{secret_access_key} AWS_SESSION_TOKEN=#{session_token}"
      `echo #{var_string} | pbcopy`
    end

    puts "Copied!".green
    puts
  end
end
