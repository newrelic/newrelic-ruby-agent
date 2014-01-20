# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), 'mongo_server'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))
require 'test/unit'
require 'mocha/setup'

class MongoServerTest < Test::Unit::TestCase
  include NewRelic::TestHelpers::FileSearching

  def setup
    @server = MongoServer.new
  end

  def teardown
    @server.stop
  end

  def test_new_server_has_a_locked_port
    assert File.exists?(@server.port_lock_path)
  end

  def test_creating_a_new_server_after_locking_port_uses_the_next_port
    new_server = MongoServer.new
    new_server_port = new_server.port
    assert_equal @server.port + 1, new_server_port
  ensure
    new_server.stop
  end

  def test_pid_path_is_unique_for_two_servers
    new_server = MongoServer.new
    pid_path1 = @server.start.pid_path
    pid_path2 = new_server.start.pid_path

    refute_equal pid_path1, pid_path2
  ensure
    new_server.stop
  end

  def test_release_port_deletes_the_port_lock_file
    path = @server.port_lock_path
    assert File.exists?(path)
    @server.release_port
    refute File.exists?(path)
  end

  def test_all_port_lock_files_returns_all_file_names
    File.write(@server.port_lock_path, @server.port)
    result = @server.all_port_lock_files
    assert_equal [@server.port_lock_path], result
  end

  def test_start_creates_a_mongod_process
    @server.start
    assert_equal 1, MongoServer.count
  end

  def test_starting_twice_only_creates_one_process
    @server.start
    @server.start
    assert_equal 1, MongoServer.count
  end

  def test_server_is_running_after_start
    @server.start
    assert @server.running?
  end

  def test_stop_kills_a_mongod_process
    @server.start
    @server.stop
    assert_equal 0, MongoServer.count
  end

  def test_stop_releases_port
    @server.start
    assert File.exists?(@server.port_lock_path)
    @server.stop
    refute File.exists?(@server.port_lock_path)
  end

  def test_stop_deletes_pid_file
    @server.start
    assert File.exists?(@server.pid_path)
    @server.stop
    refute File.exists?(@server.pid_path)
  end

  def test_pingable_returns_true_if_ping_is_ok
    ok_status = { "ok" => 1.0 }
    @server.stubs(:ping).returns ok_status
    assert @server.pingable?
  end

  def test_server_start_times_out_if_it_isnt_pingable
    @server.stubs(:pingable?).returns false

    assert_raise Timeout::Error do
      @server.start
    end
  end

  def test_server_count_returns_the_number_of_mongo_processes
    previous_server_count = `ps aux | grep mongo[d]`.split("\n").length
    @server.start
    assert_equal previous_server_count + 1, MongoServer.count
  end

  def test_server_count_children_returns_number_of_mongo_processes_started_by_mongo_server
    test_pid_path = File.join(MongoServer.tmp_directory, 'test.pid')
    `mongod --pidfilepath #{test_pid_path} &`
    pid = File.read(test_pid_path).to_i
    @server.start
    result = MongoServer.count(:children)

    assert_equal 1, result
  ensure
    Process.kill('TERM', pid)
    FileUtils.rm(test_pid_path)
  end

  def test_replica_set_servers_include_fork_flag
    replica = MongoServer.new(:replica)
    assert_includes replica.startup_command, '--fork'
    replica.stop
  end

  def test_replica_set_servers_include_repl_set
    replica = MongoServer.new(:replica)
    assert_includes replica.startup_command, '--replSet'
    replica.stop
  end

  def test_starting_a_server_creates_a_client
    @server.start
    assert @server.client
  end

  def test_ping_returns_ok_for_started_server
    @server.start
    ok_status = { "ok" => 1.0 }
    assert_equal ok_status, @server.ping
  end

  def test_stop_sets_client_to_nil
    @server.start
    @server.stop
    assert_nil @server.client
  end

  def test_ping_returns_nil_for_stopped_server
    @server.start
    @server.stop
    assert_nil @server.ping
  end

  def test_servers_in_different_threads_use_unique_ports
    threads = []

    20.times do
      threads << Thread.new do
        MongoServer.new
      end
    end

    servers = threads.map(&:value)

    assert_equal 20, servers.map(&:port).uniq.length
  ensure
    servers.each(&:stop)
  end
end

