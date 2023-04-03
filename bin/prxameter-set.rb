#!/usr/bin/env ruby
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "aws-sdk-ssm"
  gem "awesome_print"
  gem "nokogiri"
end

# print usage information
do_commit = ARGV.delete("--commit")
do_delete = ARGV.delete("--delete")
file = ARGV[0]
unless file&.end_with?(".env") && File.exist?(file)
  puts "Usage: #{"prxameter-set".green} [env-file] [--commit] [--delete]"
  exit 1
end

# read file
new_params = File.read(file).split("\n").each_with_object({}) do |line, acc|
  name, value = line.split("=", 2)
  acc[name] = value
end

# parse filename - only the 3rd segment can have dots in it
parts = file.split(".").reject(&:empty?)[0..-3]
path = "/" + parts.join(".").split(".", 3).join("/") + "/"
region = file.split(".")[-2]

# load existing params + pages
client = Aws::SSM::Client.new(region: region)
resp = client.get_parameters_by_path(path: path, recursive: true)
old_params = resp.parameters
while resp.next_token
  resp = client.get_parameters_by_path(path: path, recursive: true, next_token: resp.next_token)
  old_params += resp.parameters
end

# create/update params
new_params.each do |key, value|
  name = path + key
  existing = old_params.find { |p| p[:name] == name }
  if !existing
    puts name
    puts "  > #{value}".green
    client.put_parameter(name: name, value: value, type: "String") if do_commit
  elsif value != existing[:value]
    puts name
    puts "  < #{existing[:value]}".red
    puts "  > #{value}".green
    client.put_parameter(name: name, value: value, overwrite: true) if do_commit
  end
end

# optionally delete missing params
if do_delete
  old_params.each do |param|
    unless new_params.find { |key,| path + key == param[:name] }
      if param[:name].include?("=")
        puts param[:name] + " (SKIP)".blue + " bad name"
      elsif param[:value].include?("\n")
        puts param[:name] + " (SKIP)".blue + " newlines not supported"
      elsif delete_missing
        puts param[:name] + " (DELETE)".red
      end
    end
  end
end

# warn if not committed
unless do_commit
  puts "\nTHIS WAS A DRY RUN ... pass " + "--commit".blue + " to save"
end
