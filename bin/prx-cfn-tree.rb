#!/usr/bin/env ruby
# Prints an ASCII tree of some CloudFormation stack hierarchy, starting with a
# given stack.

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-cloudformation"
  gem "nokogiri"
  gem "terminal-table"
  gem "slop"
  gem "prx-ruby-aws-creds"
end

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--region", 'Region (e.g., "us-east-1")', required: true
  o.string "--max-depth", 'Max depth (e.g., "us-east-1")', default: "10"
  o.bool "--stacks-only", "List only CloudFormation stacks"
  o.string "--stack-name", 'Stack name or ID (e.g., "infrastructure-cd-root-production")', required: true
  o.on "-h", "--help" do
    puts o
    exit
  end
end

region = OPTS[:region]
MAX_DEPTH = OPTS[:max_depth].to_i
STACKS_ONLY = OPTS[:stacks_only]
ROOT_STACK_NAME = OPTS[:stack_name]

CLOUDFORMATION = Aws::CloudFormation::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials, retry_mode: "adaptive")

# Depth 0 is the root stack itself
# Depth 1 is resources that belong to the root stack
# Depth 2 would be resources that belong to a stack at depth 1
def walk_stack_hierarchy(stack_id, depth = 0)
  count = 0

  if depth == 0
    puts "#{"AWS::CloudFormation::Stack".blue} #{stack_id}"
  end

  depth += 1

  if depth <= MAX_DEPTH
    CLOUDFORMATION.list_stack_resources({
      stack_name: stack_id
    }).each do |resp|
      resp.stack_resource_summaries.each do |summary|
        count += 1
        if summary.resource_type == "AWS::CloudFormation::Stack" || (summary.resource_type != "AWS::CloudFormation::Stack" && !STACKS_ONLY)
          type = (summary.resource_type == "AWS::CloudFormation::Stack") ? summary.resource_type.blue : summary.resource_type.green
          puts "#{"│  " * (depth - 1)}├─ #{type} #{summary.logical_resource_id}"
        end

        if summary.resource_type == "AWS::CloudFormation::Stack"
          nested_count = walk_stack_hierarchy(summary.physical_resource_id, depth)
          count += nested_count
        end
      end
    end
  end

  count
end

resource_count = walk_stack_hierarchy(ROOT_STACK_NAME)

puts
puts "Resource count: #{resource_count}".yellow
puts
