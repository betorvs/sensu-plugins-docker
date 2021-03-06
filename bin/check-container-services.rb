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
#   check-container-services.rb -c /path/docker-compose.yaml
#   CheckContainerServices OK
#
# NOTES:
#     => State.running == true   -> OK
#     => State.running == false  -> CRITICAL
#     => Not Found               -> CRITICAL
#     => Can't connect to Docker -> WARNING
#     => Other exception         -> WARNING
#
# LICENSE:
#   Copyright 2017 Roberto Scudeller. Github @betorvs
#   Fork from check-container.rb but with some special needs
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
    check_node_manager("#{Socket.gethostname}")
    warning "File #{config[:compose]} not found" unless File.exists?(config[:compose])
    services = JSON.parse(list_services)
    status_check = 0
    result = ""
    services['data'].each do |service|
      service_id = list_tasks(service['id'])
      service_name = service['name']
      stack_name = service['stack']
      target = list_replicas(service_name)
        tasks_up=0
        service_id.each do |tasks|
          path = "tasks/#{tasks}"
          begin
            response = docker_api(path)
            task_state = response['Status']['State']
            task_node = get_node_hostname(response['NodeID'])
            if task_state == "running"
              #result << "OK Stack: #{stack_name} , Service: #{service_name} => #{tasks} is #{task_state} on #{task_node}.\n"
	      tasks_up = tasks_up + 1
            else
	    #  remove because 
             result << "WARNING Stack: #{stack_name} , Service #{service_name} => #{tasks} is #{task_state} on #{task_node}.\n"
            end
          end
	end
	if tasks_up == 0
	  result << "CRITICAL Stack: #{stack_name} , Service: #{service_name} with container #{target} = #{tasks_up} .\n"
	  status = 2
	#elsif tasks_up >= 1
	#  result << "WARNING Stack: #{stack_name}, Service: #{service_name} with containers #{target} = #{tasks_up}"
	else
          #result << "OK: Stack: #{stack_name} , Service #{service_name} with container #{target} = #{tasks_up}"
	  status = 0
	end
      if status > status_check
	status_check = status
      end
      status_check
    end
    if status_check == 2
      puts result
      critical
    else
      #puts result
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
        response.code if response.code != "200"
        return JSON.parse(response.read_body)
      end
    end
  end
  def check_node_manager(hostname)
    path = 'nodes'
    @nodes = docker_api(path)
    @nodes.each do |host|
      if host.to_s.include? "This node is not a swarm manager"
        ok "WORKER node found. Please, verify the Docker Swarm Node Manager if the services is running."
      end
    end
  end
  def get_node_hostname(id)
    path = "nodes/#{id}"
    nodes = docker_api(path)
    node = nodes['Description']['Hostname']
  end
  def list_services
    path = 'services'
    services = docker_api(path)
    list = services.map do |service|
      { :name => service['Spec']['Name'], :id  => service['ID'], :stack => service['Spec']['Labels']['com.docker.stack.namespace'] }
    end
    JSON[{ 'data' => list}]
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
  def list_tasks(service)
    id_name = []
    path = 'tasks'
    expression = service
    tasks = docker_api(path)
    tasks.each do |service_ids|
      found = service_ids['ServiceID']
      if found.to_s.include? expression
        id_name << service_ids['ID']
      end
    ##puts "#{list} #{id_name}"
    end
    id_name
  end
end
