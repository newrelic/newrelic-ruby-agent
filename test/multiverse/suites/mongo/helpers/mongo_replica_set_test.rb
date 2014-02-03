# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), 'mongo_replica_set'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))
require 'test/unit'
require 'mocha/setup'

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

  def test_config_returns_nil_unless_servers_are_running
    @replica.start
    @replica.stop
    assert_nil @replica.config
  end

  def test_started_replica_set_servers_have_unique_ports
    @replica.start

    assert_equal 3, @replica.servers.map(&:port).uniq.length
  end

  def test_config_includes_replica_set_member_strings_with_correct_ports
    @replica.start

    result = @replica.config[:members].map { |member| member[:host].split(':').last.to_i }
    expected = @replica.servers.map(&:port)

    assert_equal expected, result
  end

  def test_server_connections_returns_the_hosts_and_ports_for_the_servers
    expected = ['localhost:27017', 'localhost:27018', 'localhost:27019']
    assert_equal expected, @replica.server_connections
  end

  def test_start_creates_a_replica_set_client_connection
    @replica.start
    assert @replica.client
  end
end
