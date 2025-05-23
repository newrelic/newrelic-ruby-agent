# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module Trace
        class TracerProviderTest < Minitest::Test
          include MultiverseHelpers
          setup_and_teardown_agent

          def after_setup
            puts @NAME
            @tracer_provider = NewRelic::Agent::OpenTelemetry::Trace::TracerProvider.new
          end

          def test_tracer_returns_a_tracer
            assert @tracer_provider.tracer.is_a?(NewRelic::Agent::OpenTelemetry::Trace::Tracer)
          end

          def test_tracer_returns_a_tracer_with_name_and_version
            tracer = @tracer_provider.tracer('newrelic_rpm', '1.2.3')

            assert_equal 'newrelic_rpm', tracer.instance_variable_get(:@name)
            assert_equal '1.2.3', tracer.instance_variable_get(:@version)
          end
        end
      end
    end
  end
end
