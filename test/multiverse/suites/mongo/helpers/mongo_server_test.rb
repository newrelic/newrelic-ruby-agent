require File.expand_path(File.join(File.dirname(__FILE__), 'mongo_server'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))
require 'test/unit'

class MongoServerTest < Test::Unit::TestCase
  include NewRelic::TestHelpers::FileSearching

  def setup
    @server = MongoServer.new
  end

  def teardown
    @server.release_port
    @server.stop
  end

  def port_lock_path
    File.join(gem_root, 'tmp', 'ports', "#{@server.port}.lock")
  end

  def test_creating_a_new_server_without_locking_port_uses_the_same_port
    new_server = MongoServer.new
    assert_equal @server.port, new_server.port
  end

  def test_lock_port_creates_a_lock_file
    @server.lock_port
    assert File.exists?(port_lock_path)
  end

  def test_creating_a_new_server_after_locking_port_uses_the_next_port
    @server.lock_port
    new_server = MongoServer.new
    assert_equal @server.port + 1, new_server.port
  end

  def test_release_port_deletes_the_port_lock_file
    @server.lock_port
    @server.release_port
    refute File.exists?(port_lock_path)
  end

  def test_all_port_lock_files_returns_all_file_names
    File.write(port_lock_path, @server.port)
    assert_equal [port_lock_path], @server.all_port_lock_files
  end

  def test_start_creates_a_mongod_process
    @server.start
    assert_equal 1, `ps aux | grep mongo[d]`.split("\n").length
  end

  def test_server_is_running_after_start
    @server.start
    assert @server.running?
  end

  def test_stop_kills_a_mongod_process
    @server.start
    @server.stop
    assert_equal 0, `ps aux | grep mongo[d]`.split("\n").length
  end

  def test_stop_releases_port
    @server.start
    assert File.exists?(port_lock_path)
    @server.stop
    refute File.exists?(port_lock_path)
  end
end
