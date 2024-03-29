#!/usr/bin/env ruby
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "aws-sdk-ssm"
  gem "awesome_print"
  gem "nokogiri"
end

# print usage information
do_print = ARGV.delete("--print")
path = ARGV[0]
region = ARGV[1] || "us-east-1"
unless path && region
  puts "Usage: #{"prxameter-get".green} [path] [region] [--print]"
  exit 1
end

# load params + pages
client = Aws::SSM::Client.new(region: region)
resp = client.get_parameters_by_path(path: path, recursive: true)
params = resp.parameters
while resp.next_token
  resp = client.get_parameters_by_path(path: path, recursive: true, next_token: resp.next_token)
  params += resp.parameters
end

# reformat
params = params.each_with_object({}) do |param, acc|
  name = param[:name].split(path).last.sub(/^\//, "")
  if name.include?("=")
    puts "skipping #{name}".red + " - bad segment name"
  elsif param[:value].include?("\n")
    puts "skipping #{name}".red + " - newlines not supported"
  else
    acc[name] = param[:value]
  end
end

# well formed filename - only support 3 or less segments, and no dots in the first 2
parts = path.split("/").reject(&:empty?)
abort "#{"WOH-".red} we only support 3 or less segments in prefix" if parts.count > 3
abort "#{"WOH-".red} only the 3rd segment of name can include dots" if parts[0...-1].join.include?(".")
filename = ".#{parts.join(".")}.#{region}.env"

# write params or print
if do_print
  params.each { |k, v| puts "#{k}=#{v}" }
else
  File.write(filename, params.map { |k, v| "#{k}=#{v}\n" }.join)
  puts "wrote #{params.count.to_s.green} to #{filename}"
end
