#!/usr/bin/env ruby

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "awesome_print"
  gem "aws-sdk-ssm"
  gem "aws-sdk-ec2"
  gem "aws-sdk-ecs"
  gem "nokogiri"
  gem "terminal-table"
  gem "slop"
  gem "prx-ruby-aws-creds"
end

OPTS = Slop.parse do |o|
  o.string "--profile", "AWS profile", default: "prx-legacy"
  o.string "--region", 'Region (e.g., "us-east-1")', default: "us-east-1"
  o.string "-i", "--instance", "Instance ID (e.g., i-06d0f11e24baaddg7)"
  o.on "-h", "--help" do
    puts o
    exit
  end
end

def colorize_label(label)
  colorized_label = label

  if colorized_label.include?("prod")
    colorized_label.gsub!("prod", "#{"prod".purple}")
  elsif colorized_label.include?("stag")
    colorized_label.gsub!("stag", "#{"stag".yellow}")
  end

  colorized_label.gsub!(/-([A-Za-z]+Stack)-/, "-\033[97;44;1m\\1\033[0m-") if colorized_label.match?(/-[A-Za-z]+Stack-/)

  colorized_label
end

def show_wizard
  puts
  puts "-------------------------------------------------------------"
  puts "  Region: #{OPTS[:region].greenish} | Profile: #{OPTS[:profile].greenish}"
  puts "-------------------------------------------------------------"

  puts
  puts "  1. Connect to an EC2 instance"
  puts "  #{"2".cyan}. Browse ECS clusters"

  print "Choose operation [#{"2".cyan}]: "
  mode_selection = $stdin.gets.chomp
  puts

  mode_selection = "2" if mode_selection.empty?

  if mode_selection == "1"
    # Connect to an EC2 instance selected from a list
    ec2 = Aws::EC2::Client.new(region: OPTS[:region], credentials: PrxRubyAwsCreds.client_credentials(OPTS[:profile]), retry_mode: "adaptive")

    i = 1
    instance_selection_hash = {}
    ec2.describe_instances.each do |resp|
      resp.reservations.each do |reservation|
        reservation.instances.each do |instance|
          instance_selection_hash[i] = instance.instance_id
          instance_name = instance.tags.find{|i| i.key == "Name" }&.value

          puts "  #{i}. #{instance.instance_id}: #{colorize_label(instance_name) || "(No name)"}"
          i += 1
        end
      end
    end

    print "Connect to EC2 instance: "
    instance_selection = $stdin.gets.chomp
    puts
    return if instance_selection.empty?

    instance_id = instance_selection_hash[instance_selection.to_i]
    exec("aws ssm start-session --target #{instance_id} --region #{OPTS[:region]} --profile #{OPTS[:profile]}")
  elsif mode_selection == "2"
    # Connect to something through ECS services and tasks
    ecs = Aws::ECS::Client.new(region: OPTS[:region], credentials: PrxRubyAwsCreds.client_credentials(OPTS[:profile]), retry_mode: "adaptive")

    i = 1
    cluster_selection_hash = {}
    ecs.list_clusters.each do |resp|
      resp.cluster_arns.each do |cluster_arn|
        cluster_selection_hash[i] = cluster_arn

        cluster_slug = cluster_arn.split(":cluster/")[1]

        puts "  #{i}. #{colorize_label(cluster_slug)}"
        i += 1
      end
    end

    print "Select an ECS cluster: "
    cluster_selection = $stdin.gets.chomp
    puts
    return if cluster_selection.empty?

    cluster_arn = cluster_selection_hash[cluster_selection.to_i]

    puts "  1. Connect to any EC2 instance in the cluster"
    puts "  #{"2".cyan}. List ECS services for this cluster"

    print "Make a selection [#{"2".cyan}]: "
    connect_selection = $stdin.gets.chomp
    puts
    connect_selection = "2" if connect_selection.empty?

    if connect_selection == "1"
      # Use SSM Session Manager to connect to an EC2 instance that is part of the
      # chosen cluster

      # A container instance is a record of an EC2 instance within the context
      # of a EC2 cluster
      container_instances = ecs.list_container_instances({cluster: cluster_arn})
      some_container_instance_arn = container_instances.container_instance_arns.first
      some_container_instance_info = ecs.describe_container_instances(cluster: cluster_arn, container_instances: [some_container_instance_arn]).container_instances.first

      some_ec2_instance_id = some_container_instance_info.ec2_instance_id
      puts
      puts "Connecting to EC2 instance #{some_ec2_instance_id.greenish}"
      puts
      exec("aws ssm start-session --target #{some_ec2_instance_id} --region #{OPTS[:region]} --profile #{OPTS[:profile]}")
    elsif connect_selection == "2"
      i = 1
      service_selection_hash = {}
      ecs.list_services(cluster: cluster_arn).each do |resp|
        resp.service_arns.each do |service_arn|
          service_selection_hash[i] = service_arn

          service_slug = service_arn.split("/").last

          puts "  #{i}. #{colorize_label(service_slug)}"
          i += 1
        end
      end

      print "Connect to a task for service (RETURN for host instance): "
      service_selection = $stdin.gets.chomp
      puts

      unless service_selection.empty?
        # Use ECS Exec to connect to a task for the chosen service

        service_arn = service_selection_hash[service_selection.to_i]

        puts
        puts "Connecting to a task for #{service_arn.split("/").last.greenish}"
        puts

        some_task_arn = ecs.list_tasks({cluster: cluster_arn, service_name: service_arn}).task_arns.first
        exec(%Q(aws ecs execute-command --region #{OPTS[:region]} --profile #{OPTS[:profile]} --cluster "#{cluster_arn}" --task "#{some_task_arn}" --interactive --command "/bin/bash"))
      else
        # Find and connect to an EC2 instance for the chosen service
        print "Connect to an EC2 instance running service: "
        service_selection2 = $stdin.gets.chomp
        puts

        service_arn = service_selection_hash[service_selection2.to_i]

        some_task_arn = ecs.list_tasks({cluster: cluster_arn, service_name: service_arn}).task_arns.first

        some_task_info = ecs.describe_tasks({cluster: cluster_arn, tasks: [some_task_arn]}).tasks.first
        some_task_container_instance_arn = some_task_info.container_instance_arn
        some_container_instance_info = ecs.describe_container_instances(cluster: cluster_arn, container_instances: [some_task_container_instance_arn]).container_instances.first
        some_ec2_instance_id = some_container_instance_info.ec2_instance_id
        puts
        puts "Connecting to EC2 instance #{some_ec2_instance_id.greenish}"
        puts
        exec("aws ssm start-session --target #{some_ec2_instance_id} --region #{OPTS[:region]} --profile #{OPTS[:profile]}")
      end
    end
  end
end


if OPTS[:instance]
  # Connect directly to an instance if --instance is provided
  exec("aws ssm start-session --target #{OPTS[:instance]} --region #{OPTS[:region]} --profile #{OPTS[:profile]}")
else
  # Otherwise, show the wizard
  show_wizard
end
