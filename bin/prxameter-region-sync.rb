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
  gem "prx-ruby-aws-creds"
end

# All parameters under these paths will be checked by default
default_paths = ["/prx/global/Spire", "/prx/stag/Spire"]


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

# Create an SSM client for the source region and each destination region from
# the command input
clients = {}
clients[source_region] = Aws::SSM::Client.new(region: source_region, credentials: PrxRubyAwsCreds.client_credentials)
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
