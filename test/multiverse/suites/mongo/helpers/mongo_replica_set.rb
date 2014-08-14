# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fileutils'
require 'timeout'
require 'mongo'
require File.expand_path(File.join(File.dirname(__FILE__), 'mongo_server'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))

class MongoReplicaSet
  include Mongo

  attr_accessor :servers, :client

  def initialize
    create_servers
  end

  def create_servers
    self.servers = Array.new(3) { MongoServer.new(:replica) }
  end

  def start
    self.servers.each { |server| server.start }
    initiate

    retry_on_exception(:exception => Mongo::ConnectionFailure, :tries => 100) do
      self.client = MongoReplicaSetClient.new(server_connections, :read => :secondary)
    end

    self
  end

  def retry_on_exception(options)
    exception = options.fetch(:exception, StandardError)
    message = options[:message]
    maximum_tries = options.fetch(:tries, 3)

    tries = 0

    begin
      yield
    rescue exception => e
      if message
        raise e unless e.message.include? message
      end

      sleep 0.1
      tries += 1
      retry unless tries > maximum_tries
      raise e
    end
  end

  def server_connections
    self.servers.map do |server|
      "localhost:#{server.port}"
    end
  end

  def stop
    self.servers.each { |server| server.stop }
    self.client = nil
  end

  def running?
    server_running_statuses = self.servers.map(&:running?).uniq
    server_running_statuses.length == 1 && server_running_statuses.first
  end

  def status
    return nil unless running?
    self.servers.first.client['admin'].command( { 'replSetGetStatus' => 1 } )
  rescue Mongo::OperationFailure => e
    raise e unless e.message.include? 'EMPTYCONFIG'
  end

  def config
    return unless running?

    config = { :_id => 'multiverse', :members => [] }

    self.servers.each_with_index do |server, index|
      config[:members] << { :_id => index, :host => "localhost:#{server.port}" }
    end

    config
  end

  def initiate
    return nil unless running?
    self.servers.first.client['admin'].command( { 'replSetInitiate' => config } )
  rescue Mongo::OperationFailure => e
    raise e unless e.message.match(/already initialized/)
  end
end
