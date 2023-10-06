#!/usr/bin/env ruby
# Compares

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-ssm"
  gem "aws-sdk-cloudformation"
  gem "aws-sdk-ecs"
  gem "nokogiri"
  gem "terminal-table"
  gem "slop"
  gem "prx-ruby-aws-creds"
end

# All parameters under these paths will be checked by default
default_paths = ["/prx/global/Spire", "/prx/stag/Spire", "/prx/prod/Spire"]

# Stack parameters and ECS task def secrets for these stacks and all descendants will be checked
default_stack_names = ["infrastructure-cd-root-staging", "infrastructure-cd-root-production"]

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--region", 'Region (e.g., "us-east-1")'
  o.string "--paths", 'Paths (e.g., "/foo,/bar")', default: default_paths.join(",")
  o.string "--stack-names", 'Stack name or ID (e.g., "infrastructure-cd-root-production")', default: default_stack_names.join(",")
  o.on "-h", "--help" do
    puts o
    exit
  end
end

paths = OPTS[:paths].split(",")
stack_names = OPTS[:stack_names].split(",")
region = OPTS[:region]

CLOUDFORMATION = Aws::CloudFormation::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials, retry_mode: "adaptive")
SSM = Aws::SSM::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials, retry_mode: "adaptive")
ECS = Aws::ECS::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials, retry_mode: "adaptive")

def find_params_in_stack_hierarchy(stack_id, stack_param_collecton, secrets_param_collection)
  # Get the full details of this stack, including the stack parameters
  stack_desc = CLOUDFORMATION.describe_stacks({stack_name: stack_id}).stacks[0]

  # Collect all the Parameter Store parameter names used in stack parameters for this stack
  stack_param_collecton.concat(stack_desc[:parameters].filter { |p| !p[:resolved_value].nil? }.map { |p| p.parameter_value })

  # Walk through all the resources that belong to this stack.
  CLOUDFORMATION.list_stack_resources({
    stack_name: stack_id
  }).each do |resp|
    resp.stack_resource_summaries.each do |summary|
      if summary.resource_type == "AWS::CloudFormation::Stack"
        # For child stacks, recursively find all the params in that as well
        find_params_in_stack_hierarchy(summary.physical_resource_id, stack_param_collecton, secrets_param_collection)
      elsif summary.resource_type == "AWS::ECS::TaskDefinition"
        # For ECS task definitions, get the task def details and extract the
        # parameter names used for container secrets
        arn = summary.physical_resource_id
        task_def = ECS.describe_task_definition({task_definition: arn}).task_definition
        secrets = task_def.container_definitions[0].secrets
        secrets_param_collection.concat(secrets.map { |s| s.value_from })
      end
    end
  end
end

# Collect all Parameter Store parameter names that are used in CloudFormation
# stack parameters and ECS task definition container secrets for all supplied
# stack hierarchies.
ecs_secrets_parameter_names = []
cfn_stack_parameter_names = []
stack_names.each do |stack_name|
  find_params_in_stack_hierarchy(stack_name, cfn_stack_parameter_names, ecs_secrets_parameter_names)
end

all_in_use_paramter_names = [].concat(ecs_secrets_parameter_names, cfn_stack_parameter_names).uniq

# Find all Parameter Store parameters that exist under the given paths.
# This is a single list of strings, which are the paramater names,
# e.g., ["/prx/Global/Spire/foo", "/prx/Global/Spire/bar"]
ssm_parameter_names = []
paths.each do |path|
  SSM.get_parameters_by_path({path: path, recursive: true, with_decryption: true}).each do |resp|
    parameters = resp[:parameters]

    parameters.each do |parameter|
      ssm_parameter_names.push(parameter.name)
    end
  end
end

other_regions = {
  "us-east-1" => "us-west-2",
  "us-west-2" => "us-east-1"
}

# For each parameter found by searching Parameter Store, look for a matching
# value from the in-use parameters. If there's no match, print out the
# parameter name
puts
puts
puts "Unused Parameter Store parameters"
puts "  - Any stack parameters set to NoEcho will also appear here"
puts "  - Parameters for other regions that match a parameter for #{region} are excluded, even though they are unused in #{region}"
ssm_parameter_names.each do |name|
  next if all_in_use_paramter_names.include?(name)

  if name.include?("/#{other_regions[region]}/")
    next if all_in_use_paramter_names.include?(name.sub("/#{other_regions[region]}/", "/#{region}/"))
  end

  puts name
end

# For all in-use parameters, print out the ones that have no match to those
# found when searching Parameter Store. These are in-use parameters that are
# not in an expected path, and might need to be moved
puts
puts "Out-of-band parameters (consider moving these to a different path)"
all_in_use_paramter_names.each do |name|
  next if ssm_parameter_names.include?(name)
  next if name.start_with?("/aws/")

  puts name
end
