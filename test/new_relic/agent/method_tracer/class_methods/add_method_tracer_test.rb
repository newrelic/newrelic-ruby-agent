# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../../test_helper'

require 'set'
module NewRelic
  module Agent
    class Agent
      module MethodTracer
        module ClassMethods
          class AddMethodTracerTest < Minitest::Test
            #  require 'new_relic/agent/method_tracer'
            include NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer

            def test_validate_options_nonhash
              assert_raises(TypeError) do
                _nr_validate_method_tracer_options(:fluttershy, [])
              end
            end

            def test_newrelic_method_exists_positive
              self.expects(:method_defined?).returns(true)
              assert newrelic_method_exists?('test_method')
            end

            def test_newrelic_method_exists_negative
              self.class.expects(:method_defined?).returns(false)
              self.class.expects(:private_method_defined?).returns(false)

              assert !self.class.newrelic_method_exists?('test_method')
            end

            def test_check_for_illegal_keys_positive
              assert_raises(RuntimeError) do
                _nr_validate_method_tracer_options(:twilight_sparkle, {:unknown_key => nil})
              end
            end

            def test_check_for_illegal_keys_negative
              test_keys = Hash[*ALLOWED_KEYS.map { |x| [x, true] }.flatten]
              _nr_validate_method_tracer_options(:rainbow_dash, test_keys)
            end

            def test_traced_method_exists_positive
              self._nr_traced_method_module.expects(:method_defined?).returns(true)
              assert method_traced?('test_method')
            end

            def test_traced_method_exists_negative
              self._nr_traced_method_module.expects(:method_defined?).returns(false)
              refute method_traced?('test_method')
            end

            def test_check_for_push_scope_and_metric_negative
              assert_raises(RuntimeError) do
                _nr_validate_method_tracer_options(:foo, {:push_scope => false, :metric => false})
              end
            end
          end
        end
      end
    end
  end
end
