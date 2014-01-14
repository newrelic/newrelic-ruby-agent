require File.expand_path(File.join(File.dirname(__FILE__), 'mongo_server'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))
require 'test/unit'

class MongoServerTest < Test::Unit::TestCase
  include NewRelic::TestHelpers::FileSearching

  def setup
    @server = MongoServer.new
  end

  def teardown
    @server.stop
  end

  def test_creating_a_new_server_without_locking_port_uses_the_same_port
    new_server = MongoServer.new
    assert_equal @server.port, new_server.port
  end

  def test_lock_port_creates_a_lock_file
    @server.lock_port
    assert File.exists?(@server.port_lock_path)
    @server.release_port
  end

  def test_creating_a_new_server_after_locking_port_uses_the_next_port
    @server.lock_port
    new_server_port = MongoServer.new.port
    @server.release_port
    assert_equal @server.port + 1, new_server_port
  end

  def test_release_port_deletes_the_port_lock_file
    @server.lock_port
    @server.release_port
    refute File.exists?(@server.port_lock_path)
  end

  def test_all_port_lock_files_returns_all_file_names
    File.write(@server.port_lock_path, @server.port)
    result = @server.all_port_lock_files
    @server.release_port
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

  def test_server_count_returns_the_number_of_mongo_processes
    previous_server_count = `ps aux | grep mongo[d]`.split("\n").length
    @server.start
    assert_equal previous_server_count + 1, MongoServer.count
  end

  def test_server_count_test_returns_number_of_mongo_processes_started_by_mongo_server
    test_pid_path = File.join(@server.tmp_directory, 'test.pid')
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
  end

  def test_replica_set_servers_include_repl_set
    replica = MongoServer.new(:replica)
    assert_includes replica.startup_command, '--replSet'
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
end

class MongoReplicaSetTest < Test::Unit::TestCase
  def setup
    @replica = MongoReplicaSet.new
  end

  def teardown
    @replica.stop
  end

  def test_replica_is_created_with_three_servers
    assert_equal 3, @replica.servers.length
  end

  def test_start_starts_all_servers
    @replica.start
    assert_equal [true], @replica.servers.map(&:running?).uniq
  end

  def test_stop_stops_all_servers
    @replica.start
    @replica.stop
    assert_equal [false], @replica.servers.map(&:running?).uniq
  end

  def test_running_returns_true_for_started_replica_set
    @replica.start
    assert @replica.running?
  end

  def test_running_returns_false_for_stopped_replica_set
    @replica.start
    @replica.stop
    refute @replica.running?
  end

  def test_status_does_not_raise_an_error_for_uninitiated_replica_set
    @replica.start
    assert_nothing_raised Mongo::OperationFailure do
      @replica.status
    end
  end
end
