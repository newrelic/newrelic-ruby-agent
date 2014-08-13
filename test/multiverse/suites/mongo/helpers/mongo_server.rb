# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fileutils'
require 'timeout'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))

class MongoServer
  extend NewRelic::TestHelpers::FileSearching

  attr_reader :type
  attr_accessor :port, :client

  def initialize(type = :single)
    @type = type
    lock_port

    make_directories
  end

  def self.count(type = :all)
    count = `ps aux | grep mongo[d]`.split("\n").length
    count -= Dir.glob(File.join(MongoServer.pid_directory, '*.pid')).length if type == :children
    count
  end

  def self.tmp_directory
    ENV["MULTIVERSE_TMP"] || File.join(gem_root, 'tmp')
  end

  def self.port_lock_directory
    File.join(tmp_directory, 'ports')
  end

  def self.pid_directory
    File.join(tmp_directory, 'pids')
  end

  def self.db_directory
    File.join(tmp_directory, 'db')
  end

  def self.log_directory
    File.join(tmp_directory, 'log')
  end

  def ping
    return unless self.client
    self.client['admin'].command( { 'ping' => 1 } )
  end

  def pingable?
    ping == { "ok" => 1.0 }
  end

  def make_directories
    directories = [
      MongoServer.pid_directory,
      MongoServer.db_directory,
      MongoServer.log_directory,
      db_path
    ]

    FileUtils.mkdir_p(directories)
  end

  def make_port_lock_directory
    FileUtils.mkdir_p(MongoServer.port_lock_directory)
  end

  def port_lock_path
    File.join(MongoServer.port_lock_directory, "#{self.port}.lock")
  end

  def pid_path
    File.join(MongoServer.pid_directory, "#{self.port}-#{self.object_id}-#{Process.pid}.pid")
  end

  def db_path
    File.join(MongoServer.db_directory, "data_#{self.port}")
  end

  def log_path
    File.join(MongoServer.log_directory, "#{self.port}.log")
  end

  def start(wait_for_startup = true)
    lock_port

    unless running?
      `#{startup_command}`

      wait_until do
        running?
      end

      if wait_for_startup
        create_client
        wait_until do
          pingable?
        end
      end
    end

    self
  end

  def wait_until(seconds = 10)
    Timeout.timeout(seconds) do
      sleep 0.1 until yield
    end
  end

  def startup_command
    pid_file = "--pidfilepath #{pid_path}"
    log_file = "--logpath #{log_path} "
    fork     = "--fork"

    dbpath = "--dbpath #{db_path}"
    port_flag = "--port #{self.port}"
    small_mongo = "--oplogSize 128 --smallfiles"
    repl_set = "--replSet multiverse"

    base = "#{port_flag} #{fork} #{pid_file} #{log_file} #{small_mongo} #{dbpath}"

    mongod_path = ENV['MONGOD_PATH'] || 'mongod'
    if self.type == :single
      "#{mongod_path} #{base}"
    elsif self.type == :replica
      "#{mongod_path} #{repl_set} #{base}"
    end
  end

  def create_client(client_class = nil)
    require 'mongo'
    if defined? MongoClient
      client_class ||= MongoClient
    else
      client_class ||= Mongo::Connection
    end

    begin
      self.client = client_class.new('localhost', self.port, :connect_timeout => 10)
    rescue Mongo::ConnectionFailure => e
      raise e unless message == "Failed to connect to a master node at localhost:#{port}"
      retry
    end
  end

  def stop
    if pid
      begin
        Process.kill('TERM', pid)
      rescue Errno::ESRCH
        # fine if we're already gone...
      end

      wait_until do
        !running?
      end

      cleanup_files
      self.client = nil
    end

    release_port
    self
  end

  def running?
    return false unless pid
    Process.kill(0, pid) == 1
  rescue Errno::ESRCH
    false
  end

  def pid
    File.read(pid_path).to_i if File.exists? pid_path
  end

  def next_available_port
    used_ports = all_port_lock_files.map do |filename|
      File.basename(filename, '.lock').to_i
    end

    if used_ports.empty?
      27017
    else
      used_ports.sort.last + 1
    end
  end

  def all_port_lock_files
    Dir.glob(File.join(MongoServer.port_lock_directory, '*.lock'))
  end

  def lock_port
    return if self.port

    make_port_lock_directory

    retry_on_exception(:exception => Errno::EEXIST, :tries => 10) do
      self.port = next_available_port
      File.new(port_lock_path, File::CREAT|File::EXCL)
    end
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

  def release_port
    FileUtils.rm port_lock_path, :force => true
    self.port = nil
  end

  # PID file needs to be cleaned up for our process checking logic
  # DB needs to get cleaned up because it's massive
  def cleanup_files
    FileUtils.rm(pid_path)
    FileUtils.rm_rf(db_path)
  end
end
