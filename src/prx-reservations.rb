#!/usr/bin/env ruby
# Shows some basic information about AWS resource reservations

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-elasticache"
  gem "aws-sdk-rds"
  gem "aws-sdk-savingsplans"
  gem "nokogiri"
  gem "terminal-table"
  gem "slop"
  gem "prx-ruby-aws-creds"
end

OPTS = Slop.parse do |o|
  o.string "--regions", 'Regions (e.g., "us-east-1,us-west-2")', default: "us-east-1,us-east-2,us-west-2"
  o.string "--data-account-profiles", 'Profiles to look for resources (e.g., "prx-legacay,prx-data-staging")', default: "prx-legacy,prx-data-staging,prx-data-production"
  o.on "-h", "--help" do
    exit
  end
end

REGIONS = OPTS[:regions].split(",")
DATA_PROFILES = OPTS[:data_account_profiles].split(",")

# Savings plans are global
# savings_plans = Aws::SavingsPlans::Client.new(region: "us-east-1", credentials: PrxRubyAwsCreds.client_credentials("prx-main"), retry_mode: "adaptive")
# savings_plans.describe_savings_plans({}).savings_plans.each do |plan|
#   pp plan
# end

# EC and RDS reservations are regional, and all instances are regional.
# All reservations are made in prx-main, but instances can be found in a
# variety of accounts.
ec_reservations = []
ec_instances = []
rds_reservations = []
rds_instances = []
REGIONS.each do |region|
  # Get all active RDS reservations
  rds = Aws::RDS::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials("prx-main"), retry_mode: "adaptive")
  rds_reservations.push(*rds.describe_reserved_db_instances({}).reserved_db_instances)

  # Get all RDS instances
  DATA_PROFILES.each do |profile|
    rds = Aws::RDS::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials(profile), retry_mode: "adaptive")
    rds_instances.push(*rds.describe_db_instances({}).db_instances)
  end

  # Get all active ElastiCache reservations
  elasticache = Aws::ElastiCache::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials("prx-main"), retry_mode: "adaptive")
  ec_reservations.push(*elasticache.describe_reserved_cache_nodes({}).reserved_cache_nodes)

  # Get all ElastiCache instances
  DATA_PROFILES.each do |profile|
    elasticache = Aws::ElastiCache::Client.new(region: region, credentials: PrxRubyAwsCreds.client_credentials(profile), retry_mode: "adaptive")
    ec_instances.push(*elasticache.describe_cache_clusters({}).cache_clusters)
  end
end

# Expand RDS reservations into a list the reflects total instance count
expanded_rds_reservations = []
rds_reservations.filter { |r| r.state == "active" }.each do |res|
  res.db_instance_count.times do |i|
    expanded_rds_reservations << {
      db_instance_class: res.db_instance_class,
      product_description: res.product_description,
      reserved_db_instance_arn: res.reserved_db_instance_arn,
      region: res.reserved_db_instance_arn.split(":")[3],
      multi_az: res.multi_az
    }
  end
end

# Expand EC reservations into a list the reflects total node count
expanded_ec_reservations = []
ec_reservations.filter { |r| r.state == "active" }.each do |res|
  res.cache_node_count.times do |i|
    expanded_ec_reservations << {
      cache_node_type: res.cache_node_type, # e.g., cache.t3.micro
      product_description: res.product_description, # e.g., redis
      reservation_arn: res.reservation_arn,
      region: res.reservation_arn.split(":")[3]
    }
  end
end

headings = ["Service", "Type", "Region", "Class", "ID", "Reserved?"]
rows = []

# For each DB instance that's in use try to find a reservation from the
# expanded list of reservation that matches. If a match is found, remove that
# reservation from the list.
# Reservations are matched on: region, engine, instance class, and multi AZ
rds_instances.each do |instance|
  arn = instance.db_instance_arn
  region = arn.split(":")[3]

  reserved = "No".red
  idx = expanded_rds_reservations.find_index { |r| region == r[:region] && instance.engine == r[:product_description] && instance.db_instance_class == r[:db_instance_class] && instance.multi_az == r[:multi_az] }
  if idx
    reserved = "Yes".green
    expanded_rds_reservations.delete_at(idx)
  end

  instance_class = instance.db_instance_class
  instance_class += " #{instance.multi_az}" if instance.multi_az

  rows << ["RDS", instance.engine, region, instance_class, instance.db_instance_identifier, reserved]
end

# For each node that's in use (an instance or cluster can have multiple nodes),
# try to find a reservation from the expanded list of reservation that matches.
# If a match is found, remove that reservation from the list.
# Reservations are matched on: region, engine, and instance class
ec_instances.each do |instance|
  instance.num_cache_nodes.times do |node|
    arn = instance.arn
    region = arn.split(":")[3]

    reserved = "No".red
    idx = expanded_ec_reservations.find_index { |r| instance.engine == r[:product_description] && region == r[:region] && instance.cache_node_type == r[:cache_node_type] }
    if idx
      reserved = "Yes".green
      expanded_ec_reservations.delete_at(idx)
    end

    rows << ["ElastiCache", instance.engine, region, instance.cache_node_type, instance.cache_cluster_id, reserved]
  end
end

puts Terminal::Table.new headings: headings, rows: rows
