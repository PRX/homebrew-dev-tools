#!/usr/bin/env ruby

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-ecr"
  gem "nokogiri"
  gem "slop"
  gem "prx-ruby-aws-creds"
end

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--prefix", 'Prefix to filter ECR repositories (e.g., "github/prx")'
  o.string "--regions", 'Regions (e.g., "us-east-1,us-west-2")', required: true
  o.bool "--force", "Replace existing policies"
  o.on "-h", "--help" do
    puts o
    exit
  end
end

regions = OPTS[:regions].split(",")
prefix = OPTS[:prefix]
force = OPTS[:force]

policy = {
  rules: [
    # Identifies images that have a `release-` prefix and marks all but the
    # 10 most recent for expiration. The remaining 10 will not be marked
    # for expiration by any lower priority rules.
    {
      rulePriority: 10,
      description: "Expire release images older than the 5 most recent",
      selection: {
        tagStatus: "tagged",
        tagPrefixList: ["release-"],
        countType: "imageCountMoreThan",
        countNumber: 10
      },
      action: {
        type: "expire"
      }
    },
    # Identifies images that have a `prerelease-` prefix and marks any that
    # are older than 30 days for expiration. The remaining images that are
    # less than 30 days old will not be marked for expiration by any lower
    # priority rules. Any images that were matched by a higher priority
    # rule are skipped.
    {
      rulePriority: 20,
      description: "Expire prerelease images older than 30 days",
      selection: {
        tagStatus: "tagged",
        tagPrefixList: ["prerelease-"],
        countType: "sinceImagePushed",
        countUnit: "days",
        countNumber: 30
      },
      action: {
        type: "expire"
      }
    },
    # Identifies all images and marks all but the 15 most recent for
    # expiration. Any images that were matched by a higher priority rule
    # are skipped.
    {
      rulePriority: 30,
      description: "Expire images older than the 15 most recent",
      selection: {
        tagStatus: "any",
        countType: "imageCountMoreThan",
        countNumber: 15
      },
      action: {
        type: "expire"
      }
    }
  ]
}

regions.each do |region|
  ecr = Aws::ECR::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials, retry_mode: "adaptive")

  repositories = []

  ecr.describe_repositories({}).each do |resp|
    repositories.push(*resp.repositories)
  end

  filtered_repositories = repositories.filter { |r| r.repository_name.start_with?(prefix) }

  filtered_repositories.each do |repository|
    repository_name = repository.repository_name

    if force
      puts "Setting policy for: #{repository_name}"
      ecr.put_lifecycle_policy({repository_name: repository_name, lifecycle_policy_text: JSON.dump(policy)})
    else
      begin
        ecr.get_lifecycle_policy({repository_name: repository_name})
      rescue Aws::ECR::Errors::LifecyclePolicyNotFoundException
        puts "Setting policy for: #{repository_name}"
        ecr.put_lifecycle_policy({repository_name: repository_name, lifecycle_policy_text: JSON.dump(policy)})
      end
    end
  end
end
