require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/server_source'

module NewRelic::Agent::Configuration
  class ServerSourceTest < Test::Unit::TestCase
    def setup
      config = {
        'slow_sql.enabled'                         => true,
        'transaction_tracer.transaction_threshold' => 'apdex_f',
        'error_collector.enabled'                  => true,
        'collect_errors'                           => false
      }
      @source = ServerSource.new(config)
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
