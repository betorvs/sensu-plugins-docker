#! /usr/bin/env ruby
#
#   check-container-services
#
# DESCRIPTION:
#   This is a simple check script for Sensu to check that a Docker container is
#   running. You can pass in either a container id or a container name.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   check-container-services.rb c92d402a5d14
#   CheckContainerServices OK
#
#   check-container-services.rb circle_burglar
#   CheckContainerServices CRITICAL: circle_burglar is not running on the host
#
# NOTES:
#     => State.running == true   -> OK
#     => State.running == false  -> CRITICAL
#     => Not Found               -> CRITICAL
#     => Can't connect to Docker -> WARNING
#     => Other exception         -> WARNING
#
# LICENSE:
#   Copyright 2014 Sonian, Inc. and contributors. <support@sensuapp.org>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'sensu-plugins-docker/client_helpers'
require 'json'
require 'yaml'

#
# Check Container Services
#
class CheckContainerServices < Sensu::Plugin::Check::CLI
  option :docker_host,
         short: '-h DOCKER_HOST',
         long: '--host DOCKER_HOST',
         description: 'Docker socket to connect. TCP: "host:port" or Unix: "/path/to/docker.sock" (default: "127.0.0.1:2375")',
         default: '/var/run/docker.sock'
  option :docker_protocol,
         description: 'http or unix',
         short: '-p PROTOCOL',
         long: '--protocol PROTOCOL',
         default: 'unix'
  option :compose,
         short: '-c COMPOSE_YAML_FILE',
         long: '--compose COMPOSE_YAML_FILE',
         required: true

  def run
    client = create_docker_client
    services = list_services
    status_check = 0
    services.each do |service|
      containers = list_containers(service)
      target = list_replicas(service)
        containers_size=0
        containers.each do |container|
          path = "/containers/#{container}/json"
          req = Net::HTTP::Get.new path
          begin
            response = client.request(req)
            if response.body.include? 'no such id'
              puts "#{container} is not running on #{config[:docker_host]}"
            end
      
            container_state = JSON.parse(response.body)['State']['Running']
            if container_state == true
              #puts "#{container} is running on #{config[:docker_host]}."
	      containers_size = containers_size + 1
            else
              puts "#{container} is #{container_state} on #{config[:docker_host]}."
            end
          rescue JSON::ParserError => e
            critical "JSON Error: #{e.inspect}"
          rescue => e
            warning "Error: #{e.inspect}"
          end
	end
	if containers_size == 0
	  puts "CRITICAL: #{service} with containers #{target} = #{containers_size}"
	  status = 2
	#elsif containers_size >= 1
	#  puts "WARNING: #{service} with containers #{target} = #{containers_size}"
	else
          #puts "OK: #{service} with containers #{target} = #{containers_size}"
	  status = 0
	end
      if status > status_check
	status_check = status
      end
      status_check
    end
    if status_check == 2
      critical 
    else
      ok
    end
  end
  def docker_api(path)
    if config[:docker_protocol] == 'unix'
      session = NetX::HTTPUnix.new("unix://#{config[:docker_host]}")
      request = Net::HTTP::Get.new "/#{path}"
    else
      uri = URI("#{config[:docker_protocol]}://#{config[:docker_host]}/#{path}")
      session = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new uri.request_uri
    end

    session.start do |http|
      http.request request do |response|
        response.value
        return JSON.parse(response.read_body)
      end
    end
  end
  def list_services
    list = []
    path = 'services'
    @services = docker_api(path)
    @services.each do |service|
      list << service['Spec']['Name']
    end
    list
  end
  def list_replicas(service)
    list = []
    compose_file = YAML.load_file("#{config[:compose]}")
    project = service.to_s.sub(/_.*$/, '')
    name = service.to_s.sub(/#{project}_/, '')
    deploy_mode = compose_file['services']["#{name}"]['deploy']['mode']
    if deploy_mode == "global"
      list << "1"
    else
      replicas = compose_file['services']["#{name}"]['deploy']['replicas']
      list << "#{replicas}"
    end 
    list
  end
  def list_containers(service)
    list = []
    path = 'containers/json'
    @containers = docker_api(path)
    
    @containers.each do |container|
      expression = service
      found = container['Names']
      if found.to_s.include? expression
        list << container['Names'][0].gsub('/', '')
      end
    end
    list
  end
end
