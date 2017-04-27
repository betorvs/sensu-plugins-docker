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
#   Copyright 2015 Paul Czarkowski. Github @paulczar
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

class DockerStatsMetrics < Sensu::Plugin::Metric::CLI::Graphite
  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-s SCHEME',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.docker"

  option :docker_host,
         description: 'location of docker api, host:port or /path/to/docker.sock',
         short: '-H DOCKER_HOST',
         long: '--docker-host DOCKER_HOST',
         default: '/var/run/docker.sock',
         proc: proc { |v|  v.gsub('tcp://', '').gsub('unix://', '') }

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
      next if key.start_with? 'blkio_stats' # array values, figure out later
      output "#{config[:scheme]}.#{container}.#{key}", value, @timestamp
    end
  end

  def docker_api(path, full_body = false)
    if config[:docker_protocol] == 'unix'
      request = Net::HTTP::Get.new "/#{path}"
      NetX::HTTPUnix.start("unix://#{config[:docker_host]}") do |http|
        get_response(full_body, http, request)
      end
    else
      uri = URI("#{config[:docker_protocol]}://#{config[:docker_host]}/#{path}")
      request = Net::HTTP::Get.new uri.request_uri
      Net::HTTP.start(uri.host, uri.port) do |http|
        get_response(full_body, http, request)
      end
    end
  end

  def get_response(full_body, http, request)
    if full_body
      get_full_response(http, request)
    else
      get_single_chunk(http, request)
    end
  end

  def get_full_response(http, request)
    http.request request do |response|
      @response = JSON.parse(response.read_body)
    end
    http.finish
    @response
  end

  def get_single_chunk(http, request)
    http.request request do |response|
      response.read_body do |chunk|
        @response = JSON.parse(chunk)
        http.finish
      end
    end
    rescue NoMethodError
      # using http.finish to prematurely kill the stream causes this exception.
      return @response
  end
  def list_services
    list = []
    path = 'services'
    @services = docker_api(path, true)
    @services.each do |service|
      list << service['Spec']['Name']
    end
    list
  end

  def list_containers(service)
    list = []
    path = 'containers/json'
    @containers = docker_api(path, true)

    @containers.each do |container|
      expression = service
      found = container['Names']
      if found.to_s.include? expression
        list << container['Names'][0].gsub('/', '')
      end
    end
    list
  end

  def container_stats(container)
    path = "containers/#{container}/stats"
    @stats = docker_api(path)
  end
end
