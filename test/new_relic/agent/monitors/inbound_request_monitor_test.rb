# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'

module NewRelic::Agent
  class InboundRequestMonitorTest < Minitest::Test
    ENCODING_KEY_NOOP = "\0"

    def setup
      @events = NewRelic::Agent::EventListener.new
      @monitor = NewRelic::Agent::InboundRequestMonitor.new(@events)

      @config = {:encoding_key => ENCODING_KEY_NOOP}
      NewRelic::Agent.config.add_config_for_testing(@config)

      class << @monitor
        define_method(:on_finished_configuring) do |*_|
        end
      end

      @events.notify(:initial_configuration_complete)
    end

    def teardown
      NewRelic::Agent.config.remove_config(@config)
    end

    def test_deserialize
      payload = @monitor.obfuscator.obfuscate("[1,2,3]")
      assert_equal [1, 2, 3], @monitor.deserialize_header(payload, "the_key")
    end

    def test_deserialize_nonsense
      expects_logging(:debug, includes("the_key"))
      assert_nil @monitor.deserialize_header("asdf", "the_key")
    end

    def test_deserialize_with_invalid_json
      payload = @monitor.obfuscator.obfuscate("[1,2,3")

      expects_logging(:debug, includes("the_key"))
      assert_nil @monitor.deserialize_header(payload, "the_key")
    end
  end
end
