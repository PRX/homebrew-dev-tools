#!/usr/bin/env ruby
# Finds log groups without an expiration set

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-cloudwatchlogs"
  gem "nokogiri"
  gem "terminal-table"
  gem "slop"
  gem "prx-ruby-aws-creds"
  gem "tty-spinner"
end

regions = [
  "us-east-1",
  "us-east-2",
  "us-west-1",
  "us-west-2",
  "ap-south-1",
  "ap-northeast-1",
  "ap-northeast-2",
  "ap-northeast-3",
  "ap-southeast-1",
  "ap-southeast-2",
  "ca-central-1",
  "eu-central-1",
  "eu-west-1",
  "eu-west-2",
  "eu-west-3",
  "eu-north-1",
  "sa-east-1"
]

profiles = %w[prx-main prx-devops prx-legacy prx-feed-cdn-staging prx-feed-cdn-production prx-dovetail-cdn-staging prx-dovetail-cdn-production prx-data-staging prx-data-production prx-shared-development prx-globalpost prx-gregstout prx-pri prx-theworld]

headings = ["Account", "Region", "Log Group Name", "Size"]
rows = []

count = profiles.length * regions.length
spinner = TTY::Spinner.new("[:spinner] Auditing #{count} accounts/regions. This will take a few minutes…", format: :dots, clear: true)

spinner.run("Done!") do |spinner|
  profiles.each do |profile|
    regions.each do |region|
      logs = Aws::CloudWatchLogs::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials(profile), retry_mode: "adaptive")

      logs.describe_log_groups({}).each do |resp|
        resp.log_groups.each do |log_group|
          bytes = log_group.stored_bytes

          rows << [profile, region, log_group.log_group_name, bytes] if log_group.retention_in_days.nil?
        end
      end
    end
  end
end

rows = rows.sort_by { |row| row[3] }.map do |row|
  bytes = row[3]
  mb = (bytes.to_f / 1_000_000).round(2)
  gb = (bytes.to_f / 1_000_000_000).round(2)

  row[3] = if gb >= 10
    "#{gb} GB".red
  elsif gb >= 1
    "#{gb} GB".yellow
  elsif mb >= 100
    "#{mb} MB".cyan
  else
    "#{mb} MB"
  end

  row
end
puts Terminal::Table.new headings: headings, rows: rows
puts "Found #{rows.length} log groups".green
