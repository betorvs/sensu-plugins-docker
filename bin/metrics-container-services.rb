#! /usr/bin/env ruby
#
#   metrics-container-services
#
# DESCRIPTION:
#
# Supports the stats feature of the docker remote api ( docker server 1.5 and newer )
# Currently only supports when docker is listening on tcp port.
#
#
# OUTPUT:
#   metric-data
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#   Copyright 2017 Roberto Scudeller. Github @betorvs
#   Fork from metrics-docker-stats.rb but with some special needs
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/metric/cli'
require 'socket'
require 'net_http_unix'
require 'json'

class Hash
  def self.to_dotted_hash(hash, recursive_key = '')
    hash.each_with_object({}) do |(k, v), ret|
      key = recursive_key + k.to_s
      if v.is_a? Hash
        ret.merge! to_dotted_hash(v, key + '.')
      else
        ret[key] = v
      end
    end
  end
end

class MetricsContainerServices < Sensu::Plugin::Metric::CLI::Graphite
  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.docker"

  option :docker_host,
         description: 'location of docker api, host:port or /path/to/docker.sock',
         short: '-H DOCKER_HOST',
         long: '--docker-host DOCKER_HOST',
         default: '/var/run/docker.sock'

  option :docker_protocol,
         description: 'http or unix',
         short: '-p PROTOCOL',
         long: '--protocol PROTOCOL',
         default: 'unix'

  def run
    @timestamp = Time.now.to_i
    services = list_services
    services.each do |service|
      containers = list_containers(service)
      containers.each do |container|
        stats = container_stats(container)
        output_stats(container, stats)
      end
    end
    ok
  end

  def output_stats(container, stats)
    dotted_stats = Hash.to_dotted_hash stats
    dotted_stats.each do |key, value|
      next if key == 'read' # unecessary timestamp
      next if value.is_a?(Array)
      output "#{config[:scheme]}.#{container}.#{key}", value, @timestamp
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
    if list.empty?
      warning
    else
      list
    end
  end

  def container_stats(container)
    path = "containers/#{container}/stats?stream=0"
    @stats = docker_api(path)
  end
end
