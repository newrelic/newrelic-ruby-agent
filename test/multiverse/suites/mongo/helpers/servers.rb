# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'timeout'
require 'socket'
require 'mongo'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))

module MongoServerHelpers
  def retry_on_exception(options)
    exception = options.fetch(:exception, StandardError)
    message = options[:message]
    maximum_tries = options.fetch(:tries, 3)

    tries = 0

    begin
      result = yield
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

  def debug_print(message)
    print message if debug?
  end

  def debug_puts(message)
    print message if debug?
  end

  def debug?
    ENV['MONGO_DEBUG']
  end
end

class MongoReplicaSet
  include Mongo
  include MongoServerHelpers

  attr_reader :master
  attr_accessor :servers, :client, :state, :connection

  def initialize
    @state = :stopped
    @client = nil

    @servers = Array.new(3) do 
      server = MongoServer.new(type: :replica)
      server.lock_port
      server
    end
  end

  def connect
    start
    debug_print "Waiting for Mongo servers to come online."

    retry_on_exception(exception: Mongo::ConnectionFailure, tries: 100) do
      debug_print "."
      self.connection = ReplSetConnection.new(server_addresses, :read => :secondary)
    end

    debug_puts '.'
    self.connection
  end

  def start
    unless started?
      self.servers.map(&:start)
      self.servers.map(&:wait_for_startup)
      status = initiate_replica_set
      self.state = :started
      status
    end
  end

  def started?
    self.state == :started
  end

  def stop
    unless stopped?
      self.servers.map(&:stop)
      self.client = nil
      self.state = :stopped
    end
  end

  def stopped?
    self.state == :stopped
  end

  def initiate_replica_set
    retry_on_exception(exception: Mongo::ConnectionFailure) do
      self.client = MongoClient.new(self.servers.first.host, self.servers.first.port)
    end

    if client
      retry_on_exception(exception: Mongo::OperationFailure, message: 'need all members up to initiate, not ok', tries: 20) do
        self.client['admin'].command( { "replSetInitiate" => replica_set_config } )
      end
    else
      "Could not create client. Are the servers started? (MongoReplicaSet#start)"
    end
  rescue Mongo::OperationFailure => e
    raise e unless e.message.include? 'already initialized'
    debug_puts "Already initiated replica set."
  end

  def status
    if self.client
      self.client['admin'].command( { replSetGetStatus: 1 } )
    else
      "No client connected. MongoReplicaSet#initiate_replica_set to set client."
    end
  end

  def server_addresses
    self.servers.map(&:address)
  end

  def replica_set_config
    config = { :_id => 'multiverse', :members => [] }

    self.servers.each_with_index do |server, index|
      config[:members] << { :_id => index, :host => "#{server.host}:#{server.port}" }
    end

    config
  end
end

class MongoServer
  include Mongo
  include MongoServerHelpers
  extend NewRelic::TestHelpers::FileSearching

  attr_reader :host, :port, :pidfile_path, :logfile_path, :lockfile_path,
              :db_path, :type, :portlock_path

  attr_accessor :connection

  def initialize(options = {})
    @host = options.fetch(:host, 'localhost')
    @port = options.fetch(:port, 27017).to_i
    @type = options.fetch(:type, :single).to_sym

    while !options[:port] && port_unusable?
      @port += 1
    end

    identifier = "#{self.type}_#{self.host}_#{self.port}"
    @db_path = "#{MongoServer.tmp_path}/data_#{identifier}"
    @pidfile_path = "#{MongoServer.tmp_path}/pids/#{identifier}.pid"
    @logfile_path = "#{MongoServer.tmp_path}/log/#{identifier}.log"
    @portlock_path = "#{MongoServer.tmp_path}/ports/#{self.port}.lock"

    make_tmp_directories
  end

  def self.tmp_path
    gem_root + '/tmp'
  end

  def self.all
    self.pidfiles.map do |filename|
      pidfilename = filename.split('/').last
      type, host, port_dot_pid = pidfilename.split('_')
      port = port_dot_pid.split('.').first

      MongoServer.new(host: host, port: port, type: type)
    end
  end

  def self.single
    server = self.all.select { |server| server.type == :single }.first
    server || MongoServer.new
  end

  def self.pidfiles
    Dir.glob("#{MongoServer.tmp_path}/pids/*")
  end

  def self.reset!
    self.shutdown_all_servers!
    self.delete_all_files!
    nil
  end

  def self.fetch_pids
    self.pidfiles.map { |filename| File.read(filename).strip }
  end

  def self.shutdown_all_servers!
    pids = self.fetch_pids
    if pids.empty?
      debug_puts "No PIDs to shutdown."
    else
      debug_puts "Shutting down PIDs #{pids.join(', ')}."
    end

    pids.each do |pid|
      `kill #{pid}`
    end
  end

  def self.delete_all_files!
    dirs = ['data_*', 'log', 'ports', 'pids']
    dirs.map! { |dir| "#{MongoServer.tmp_path}/#{dir}" }
    `rm -rf #{dirs.join(' ')}`
  end

  def self.locked_ports
    Dir.glob("#{MongoServer.tmp_path}/ports/*.lock").map { |filename| File.read(filename).strip }
  end

  def connect
    start
    debug_print "Waiting for Mongo server to come online."

    retry_on_exception(exception: Mongo::ConnectionFailure, tries: 100) do
      debug_print "."
      self.connection = MongoClient.new(self.host, self.port)
    end

    debug_puts '.'
    self.connection
  end

  def address
    "#{host}:#{port}"
  end

  def lock_port
    File.write(self.portlock_path, self.port)
    self.port
  end

  def unlock_port
    File.delete(self.portlock_path)
    self.port
  end

  def locked_port?(port_number)
    MongoServer.locked_ports.include? port_number.to_s
  end

  def running?
    File.exists?(self.pidfile_path)
  end

  def wait_for_startup
    Timeout::timeout(3) do
      until running? do
        sleep(0.1)
      end
    end
  rescue => e
    debug_puts "Server could not be started."
    debug_puts `cat #{self.logfile_path}`
    raise e
  end

  def port_unusable?
    port_in_use?(self.host, self.port) || locked_port?(self.port)
  end

  def port_in_use?(host, port)
    begin
      Timeout::timeout(1) do
        begin
          s = TCPSocket.new(host, port)
          s.close
          return true
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          return false
        end
      end
    rescue Timeout::Error
      debug_puts "Timed out checking for port #{port} on #{host}."
    end

    return false
  end

  def single_instance_already_started?
    self.type == :single && port_in_use?(self.host, self.port)
  end

  def start
    if single_instance_already_started?
      debug_puts "Single Mongo instance already started #{server_info}"
      debug_puts "Use :type => :replica for a replica set."
      return nil
    end

    if running?
      debug_puts "Tried to start Mongo (#{self.pid}) - #{self.host}:#{self.port}"
      debug_puts "Server is already running."
    else
      make_db_directory
      lock_port

      cmd = `#{startup_command}`

      wait_for_startup
      debug_puts "Started Mongo (#{self.pid}) - #{self.host}:#{self.port}"
      pid
    end
  end

  def make_tmp_directories
    dirs = ['pids', 'log', 'ports']
    dirs.map! { |dir| "#{MongoServer.tmp_path}/#{dir}" }
    `mkdir -p #{dirs.join(' ')}`
  end

  def make_db_directory
    `mkdir -p #{self.db_path}`
  end

  def server_info
    "(#{self.pid}) - #{self.host}:#{self.port}"
  end

  def pid
    File.read(self.pidfile_path).strip.to_i
  rescue Errno::ENOENT => e
    if e.message.match(/No such file or directory/)
      'pidfile not found'
    else
      raise e
    end
  end

  def startup_command
    pid_file = "--pidfilepath #{self.pidfile_path}"
    log_file = "--logpath #{logfile_path} "

    db_path = "--dbpath #{self.db_path}"
    port_flag = "--port #{self.port}"
    small_mongo = "--oplogSize 128 --smallfiles"
    repl_set = "--fork --replSet multiverse"

    base = "#{port_flag} #{pid_file} #{log_file} #{small_mongo} #{db_path}"

    if self.type == :single
      "mongod #{base} &"
    elsif self.type == :replica
      "mongod #{repl_set} #{base} &"
    end
  end

  def stop
    if running?
      `kill #{self.pid}`
      unlock_port
      debug_puts "Stopped Mongo (#{self.pid}) - #{self.host}:#{self.port}"
      `rm #{self.pidfile_path}`
    else
      debug_puts "Tried to stop Mongo (#{self.pid}) - #{self.host}:#{self.port}"
      debug_puts "Server isn't running."
    end

    nil
  end

end
