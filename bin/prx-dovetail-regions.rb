#!/usr/bin/env ruby
# View/update which Dovetail Router regions DNS is pointing at.

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-route53"
  gem "prx-ruby-aws-creds"
  gem "slop"
end

OPTS = Slop.parse do |o|
  o.string "-p", "--profile", "AWS profile", default: "prx-legacy-route53"
  o.string "-e", "--environment", 'E.g. "production" or "staging"', required: true
  o.string "-c", "--change", 'Change dovetail regions (e.g., "us-east-1" or "all")', default: nil
  o.on "-h", "--help" do
    puts o
    exit
  end
end

ZONE_NAME = "prx.tech"
ALL_REGIONS = %w[us-east-1 us-west-2]
if %w[stag staging].include?(OPTS[:environment].to_s.downcase)
  ALIAS = "dovetail-router.staging.u.#{ZONE_NAME}"
  GROUP = "dovetail-router-alb-latency-group.stag.#{ZONE_NAME}"
  REGIONS = ALL_REGIONS.map { |r| [r, "dovetail-router.staging.#{r}.#{ZONE_NAME}"] }.to_h
elsif %w[prod production].include?(OPTS[:environment].to_s.downcase)
  ALIAS = "dovetail-router.u.#{ZONE_NAME}"
  GROUP = "dovetail-router-alb-latency-group.prod.#{ZONE_NAME}"
  REGIONS = ALL_REGIONS.map { |r| [r, "dovetail-router.#{r}.#{ZONE_NAME}"] }.to_h
else
  abort "Invalid environment".red
end

CHANGE =
  if OPTS[:change] == "all"
    GROUP
  elsif REGIONS.key?(OPTS[:change])
    REGIONS[OPTS[:change]]
  elsif OPTS[:change]
    abort "Invalid change region".red
  end

# check if a route53 aws profile exists
creds =
  begin
    PrxRubyAwsCreds.client_credentials
  rescue => e
    puts "Unable to get AWS client credentials!".red
    puts "\nDid you add a #{"[profile prx-legacy-route53]".yellow} to your ~/.aws/config?"
    exit 1
  end

# find hosted zone
client = Aws::Route53::Client.new(credentials: creds, retry_mode: "adaptive")
res = client.list_hosted_zones_by_name(dns_name: "#{ZONE_NAME}.")
zone_id = res.hosted_zones&.first&.id
abort "Hosted zone '#{ZONE_NAME}' not found!".red unless zone_id

# get current aliases
res = client.list_resource_record_sets(hosted_zone_id: zone_id, start_record_name: ALIAS, max_items: 2)
a_rec = res.resource_record_sets.find { |r| r.name == "#{ALIAS}." && r.type == "A" }
aaaa_rec = res.resource_record_sets.find { |r| r.name == "#{ALIAS}." && r.type == "AAAA" }
abort "Missing A record for #{ALIAS}".red unless a_rec
abort "Missing AAAA record for #{ALIAS}".red unless aaaa_rec

puts "Current"
puts "-------"
puts "A    --> #{a_rec.alias_target.dns_name.blue}"
puts "AAAA --> #{aaaa_rec.alias_target.dns_name.blue}"
abort "Mismatching A/AAAA records!".red if a_rec.alias_target.dns_name != aaaa_rec.alias_target.dns_name
exit unless CHANGE

if a_rec.alias_target.dns_name == "#{CHANGE}."
  puts "\nNothing to change"
  exit
end

puts "\nChanges"
puts "-------"
puts "A    --> #{CHANGE.green}."
puts "AAAA --> #{CHANGE.green}."

print "\nProceed with DNS changes? (y/n) "
exit unless STDIN.gets.chomp.strip == "y"

print "Really? You're sure this won't just make things worse? (aye/nay) "
exit unless STDIN.gets.chomp.strip == "aye"

print "You know, Fixed and Failure both start out the same way - proceed anyways? (yep/nope) "
exit unless STDIN.gets.chomp.strip == "yep"

batch = {
  changes: [
    {action: "UPSERT", resource_record_set: a_rec.to_h},
    {action: "UPSERT", resource_record_set: aaaa_rec.to_h}
  ]
}
batch[:changes][0][:resource_record_set][:alias_target][:dns_name] = "#{CHANGE}."
batch[:changes][1][:resource_record_set][:alias_target][:dns_name] = "#{CHANGE}."
client.change_resource_record_sets(hosted_zone_id: zone_id, change_batch: batch)
puts "\nDovetail Router aliases successfully updated".green
