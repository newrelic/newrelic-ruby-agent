require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/server_source'

module NewRelic::Agent::Configuration
  class ServerSourceTest < Test::Unit::TestCase
    def setup
      config = {
        'agent_config' => {
          'slow_sql.enabled'                         => true,
          'transaction_tracer.transaction_threshold' => 'apdex_f',
          'transaction_tracer.record_sql'            => 'raw',
          'error_collector.enabled'                  => true
        },
        'apdex_t'                                  => 1.0,
        'collect_errors'                           => false,
        'collect_traces'                           => true
      }
      @source = ServerSource.new(config)
    end

    def test_should_set_apdex_t
      assert_equal 1.0, @source[:apdex_t]
    end

    def test_should_set_agent_config_values
      assert_equal 'raw', @source[:'transaction_tracer.record_sql']
    end

    def test_should_not_dot_the_agent_config_sub_hash
      assert_nil @source[:'agent_config.slow_sql.enabled']
    end

    def test_should_enable_tracer_as_configured
      assert @source[:'slow_sql.enabled']
    end

    def test_should_disable_tracer_as_configured
      assert !@source[:'error_collector.enabled']
    end

    def test_should_ignore_apdex_f_setting_for_transaction_threshold
      assert_equal nil, @source[:'transaction_tracer.transaction_threshold']
    end
  end
end
