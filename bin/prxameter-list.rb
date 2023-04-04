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
  gem "prx-ruby-aws-creds"
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

client = Aws::SSM::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials)

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
