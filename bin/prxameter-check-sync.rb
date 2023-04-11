#!/usr/bin/env ruby
# Finds all SSM Parameter Store parameters that exist in any of the given
# regions under a given path, and reports whether their values are in sync
# across all those regions.

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-ssm"
  gem "nokogiri"
  gem "terminal-table"
  gem "slop"
  gem "prx-ruby-aws-creds"
end

# All parameters under these paths will be checked by default
default_paths = ["/prx/global/Spire", "/prx/stag/Spire"]
default_regions = ["us-east-1", "us-west-2"]

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--paths", 'Paths (e.g., "/foo,/bar")', default: default_paths.join(",")
  o.string "--regions", 'Regions (e.g., "us-east-1,us-west-1")', default: default_regions.join(",")
  o.bool "--hide-matches", "Hide matching values"
  o.on "-h", "--help" do
    puts o
    exit
  end
end

paths = OPTS[:paths].split(",")
regions = OPTS[:regions].split(",")

# Add an entry for each region where sync should be checked
clients = {}
credentials = PrxRubyAwsCreds.client_credentials
regions.each do |region|
  clients[region] = Aws::SSM::Client.new(region: region, credentials: credentials)
end

lookup = {}

clients.each do |region, client|
  paths.each do |path|
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

headings = ["Parameter Name", "🔄", "🔒", *clients.keys]
rows = []

lookup.each do |parameter_name, region_values|
  row = if parameter_name.include?("/prod/")
    [parameter_name.purple]
  elsif parameter_name.include?("/stag/")
    [parameter_name.yellow]
  elsif parameter_name.include?("/global/")
    [parameter_name.blue]
  else
    [parameter_name]
  end

  if region_values.keys.length == clients.keys.length && region_values.values.map(&:value).uniq.count == 1 && region_values.values.map(&:type).uniq.count == 1
    next if OPTS[:hide_matches]

    # Consider parameters in sync if they exist in each region, and the values
    # and types in each region are identical
    row << "✅"
  elsif region_values.values.map(&:value).uniq.count > 1 || region_values.values.map(&:type).uniq.count > 1
    # If there are non-identical values or types in various regions it means
    # there's a mismatch that needs to be reconciled
    row << "⚠️"
  else
    # Otherwise, it means one or more regions are missing a value, but the
    # values that do exist are identical
    row << "❌"
  end

  row << if region_values.values.first.type == "SecureString"
    "🔒"
  else
    "➖"
  end

  clients.each do |region, client|
    if region_values[region]
      # Show at most 20 characters. If the value doesn't fit, show the first
      # 19 characters and an ellipsis
      parameter_value = region_values[region].value
      text = ((parameter_value.length < 21) ? parameter_value : "#{parameter_value[0..18].strip}…")

      row << if row[1] == "✅"
        text.greenish
      elsif row[1] == "⚠️"
        text.yellowish
      elsif row[1] == "❌"
        text.redish
      else
        text
      end
    else
      row << "➖"
    end
  end

  rows << row
end

puts Terminal::Table.new headings: headings, rows: rows
