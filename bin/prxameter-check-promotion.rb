#!/usr/bin/env ruby
# Checks all SSM Parameter Store parameters in a single region that get
# promoted from staging to production during deploys (e.g., Docker image tags),
# to ensure that they are in sync in the two environments.

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

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--region", 'Region (e.g., "us-east-1")'
  o.bool "--hide-matches", "Hide matching values"
  o.on "-h", "--help" do
    puts o
    exit
  end
end

region = OPTS[:region]
hide_matches = OPTS[:hide_matches]

client = Aws::SSM::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials)

stag_parameters = []
prod_parameters = []

client.get_parameters_by_path({path: "/prx/stag/Spire", recursive: true, with_decryption: true}).each do |resp|
  parameters = resp[:parameters]
  stag_parameters.concat(parameters)
end

client.get_parameters_by_path({path: "/prx/prod/Spire", recursive: true, with_decryption: true}).each do |resp|
  parameters = resp[:parameters]
  prod_parameters.concat(parameters)
end

all_normalized_parameter_names = []
[stag_parameters, prod_parameters].each do |list|
  list.each do |parameter|
    all_normalized_parameter_names.push(parameter.name.gsub("/prx/stag/", "/prx/*/").gsub("/prx/prod/", "/prx/*/"))
  end
end

headings = ["Parameter Name", "🔄", "Staging", "Production"]
rows = []

all_normalized_parameter_names.each do |name|
  stag_parameter = stag_parameters.find { |p| name == p.name.gsub("/prx/stag/", "/prx/*/") }
  prod_parameter = prod_parameters.find { |p| name == p.name.gsub("/prx/prod/", "/prx/*/") }

  stag_value = stag_parameter&.value || "—"
  prod_value = prod_parameter&.value || "—"

  next if stag_value == prod_value && hide_matches

  if name.include? "/pkg/"
    rows << [name, (stag_value == prod_value) ? "✅" : "❌", stag_value[0, 50].split("\n")[0], prod_value[0, 50].split("\n")[0]]
  end
end

puts Terminal::Table.new headings: headings, rows: rows
