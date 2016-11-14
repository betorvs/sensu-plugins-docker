#! /usr/bin/env ruby
#
#   check-container
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
#   check-docker-container.rb c92d402a5d14
#   CheckDockerContainer OK
#
#   check-docker-container.rb circle_burglar
#   CheckDockerContainer CRITICAL: circle_burglar is not running on the host
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

#
# Check Docker Container
#
class CheckDockerContainer < Sensu::Plugin::Check::CLI
  option :docker_host,
         short: '-h DOCKER_HOST',
         long: '--host DOCKER_HOST',
         description: 'Docker socket to connect. TCP: "host:port" or Unix: "/path/to/docker.sock" (default: "127.0.0.1:2375")',
         default: '127.0.0.1:2375'
  option :container,
         short: '-c CONTAINER',
         long: '--container CONTAINER',
         default: ''
  option :docker_protocol,
         description: 'http or unix',
         short: '-p PROTOCOL',
         long: '--protocol PROTOCOL',
         default: 'http'
  option :friendly_names,
         description: 'use friendly name if available',
         short: '-n',
         long: '--names',
         boolean: true,
         default: false

  def run
    client = create_docker_client
    if config[:container] != ''
      list = [config[:container]]
    else
      list = list_containers
    end
    list.each do |container|
      path = "/containers/#{container}/json"
      req = Net::HTTP::Get.new path
      begin
        response = client.request(req)
        if response.body.include? 'no such id'
          #critical "#{config[:container]} is not running on #{config[:docker_host]}"
          critical "#{container} is not running on #{config[:docker_host]}"
        end
  
        container_state = JSON.parse(response.body)['State']['Running']
        if container_state == true
          #ok "#{config[:container]} is running on #{config[:docker_host]}."
          ok "#{container} is running on #{config[:docker_host]}."
        else
          #critical "#{config[:container]} is #{container_state} on #{config[:docker_host]}."
          critical "#{container} is #{container_state} on #{config[:docker_host]}."
        end
      rescue JSON::ParserError => e
        critical "JSON Error: #{e.inspect}"
      rescue => e
        warning "Error: #{e.inspect}"
      end
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
  def list_containers
    list = []
    path = 'containers/json'
    @containers = docker_api(path)

    @containers.each do |container|
      if config[:friendly_names]
        list << container['Names'][0].gsub('/', '')
      else
        list << container['Id']
      end
    end
    list
  end
end
