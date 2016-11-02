# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(Dalli)
  class DalliTest < Minitest::Test
    include MemcacheTestCases

    MULTI_OPERATIONS = [:get_multi, :get_multi_cas]

    def setup
      @cache = Dalli::Client.new("127.0.0.1:11211", :socket_timeout => 2.0)
    end

    if ::NewRelic::Agent::Instrumentation::Memcache::Dalli.supports_datastore_instances?

      def test_get_multi_in_web_with_capture_memcache_keys
        with_config(:capture_memcache_keys => true) do
          key = set_key_for_testcase
          in_web_transaction("Controller/#{self.class}/action") do
            @cache.get_multi(key)
          end
          trace = last_transaction_trace
          segment = find_node_with_name trace, 'Datastore/operation/Memcached/get_multi_request'
          assert_equal "get_multi_request [\"#{key}\"]", segment[:statement]
        end
      end

      def test_assign_instance_to_with_ip_and_port
        NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
        segment = mock('datastore_segment')
        segment.expects(:set_instance_info).with('jonan.pizza_cube', 11211)
        server = ::Dalli::Server.new '127.0.0.1:11211'
        ::NewRelic::Agent::Instrumentation::Memcache::Dalli.assign_instance_to(segment, server)
      end

      def test_assign_instance_to_with_name_and_port
        NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
        segment = mock('datastore_segment')
        segment.expects(:set_instance_info).with('jonan.gummy_planet', 11211)
        server = ::Dalli::Server.new 'jonan.gummy_planet:11211'
        ::NewRelic::Agent::Instrumentation::Memcache::Dalli.assign_instance_to(segment, server)
      end

      def test_assign_instance_to_with_unix_domain_socket
        NewRelic::Agent::Hostname.stubs(:get).returns("jonan.pizza_cube")
        segment = mock('datastore_segment')
        segment.expects(:set_instance_info).with('jonan.pizza_cube', '/tmp/jonanfs.sock')
        server = ::Dalli::Server.new '/tmp/jonanfs.sock'
        ::NewRelic::Agent::Instrumentation::Memcache::Dalli.assign_instance_to(segment, server)
      end

      def test_assign_instance_to_when_exception_raised
        NewRelic::Agent::Hostname.stubs(:get).raises("oops")
        segment = mock('datastore_segment')
        segment.expects(:set_instance_info).with('unknown', 'unknown')
        server = ::Dalli::Server.new '/tmp/jonanfs.sock'
        ::NewRelic::Agent::Instrumentation::Memcache::Dalli.assign_instance_to(segment, server)
      end

    end

    def instance_metric
      "Datastore/instance/Memcached/#{NewRelic::Agent::Hostname.get}/11211"
    end

    def expected_web_metrics(command)
      if ::NewRelic::Agent::Instrumentation::Memcache::Dalli.supports_datastore_instances?
        datastore_command = MULTI_OPERATIONS.include?(command) ? :get_multi_request : command
        metrics = super(datastore_command)
        metrics.unshift instance_metric
        metrics.unshift "Ruby/Memcached/Dalli/#{command}" if command != datastore_command
        metrics
      else
        super
      end
    end

    def expected_bg_metrics(command)
      if ::NewRelic::Agent::Instrumentation::Memcache::Dalli.supports_datastore_instances?
        datastore_command = MULTI_OPERATIONS.include?(command) ? :get_multi_request : command
        metrics = super(datastore_command)
        metrics.unshift instance_metric
        metrics.unshift "Ruby/Memcached/Dalli/#{command}" if command != datastore_command
        metrics
      else
        super
      end
    end
  end

  if Dalli::VERSION >= '2.7'
    require 'dalli/cas/client'
    DependencyDetection.detect!

    class DalliCasClientTest < DalliTest

      def after_setup
        super
        @cas_key = set_key_for_testcase(1)
      end

      def test_get_cas
        expected_metrics = expected_web_metrics(:get_cas)

        value = nil
        in_web_transaction("Controller/#{self.class}/action") do
          value, _ = @cache.get_cas(@cas_key)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal value, @cache.get(@cas_key)
      end

      def test_get_multi_cas
        expected_metrics = expected_web_metrics(:get_multi_cas)

        value = nil
        in_web_transaction("Controller/#{self.class}/action") do
          # returns { "cas_key" => [value, cas] }
          value, _ = @cache.get_multi_cas(@cas_key)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal 1, value.values.length
        assert_equal value.values.first.first, @cache.get(@cas_key)
      end

      def test_set_cas
        expected_metrics = expected_web_metrics(:set_cas)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.set_cas(@cas_key, 2, 0)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal 2, @cache.get(@cas_key)
      end

      def test_replace_cas
        expected_metrics = expected_web_metrics(:replace_cas)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.replace_cas(@cas_key, 2, 0)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal 2, @cache.get(@cas_key)
      end

      def test_delete_cas
        expected_metrics = expected_web_metrics(:delete_cas)

        in_web_transaction("Controller/#{self.class}/action") do
          @cache.delete_cas(@cas_key)
        end

        assert_memcache_metrics_recorded expected_metrics
        assert_equal nil, @cache.get(@cas_key)
      end

    end
  end
end
