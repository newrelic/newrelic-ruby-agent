# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))

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
                validate_options(:fluttershy, [])
              end
            end

            def test_validate_options_defaults
              self.expects(:check_for_illegal_keys!)
              self.expects(:check_for_push_scope_and_metric)
              validate_options(:applejack, {})
            end

            def test_validate_options_override
              opts = {:push_scope => false, :metric => false, :force => true}
              self.expects(:check_for_illegal_keys!)
              self.expects(:check_for_push_scope_and_metric)
              val = validate_options(:pinkie_pie, opts)
              assert val.is_a?(Hash)
              assert (val[:push_scope] == false), val.inspect
              assert (val[:metric] == false), val.inspect
              assert (val[:force] == true), val.inspect
            end

            def test_default_metric_name_code
              assert_equal "Custom/#{self.class.name}/test_method", self.class.default_metric_name_code('test_method')
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
                check_for_illegal_keys!(:twilight_sparkle, {:unknown_key => nil})
              end
            end

            def test_check_for_illegal_keys_negative
              test_keys = Hash[*ALLOWED_KEYS.map {|x| [x, nil]}.flatten]
              check_for_illegal_keys!(:rainbow_dash, test_keys)
            end

            def test_check_for_illegal_keys_deprecated
              log = with_array_logger do
                check_for_illegal_keys!(:rarity, :force => true)
              end.array

              assert_equal(1, log.size)

              assert_match(/Deprecated options when adding method tracer to rarity: force/, log[0])
            end

            def test_traced_method_exists_positive
              self.expects(:_traced_method_name)
              self.expects(:method_defined?).returns(true)
              assert traced_method_exists?('test_method', 'Custom/Test/test_method')
            end

            def test_traced_method_exists_negative
              self.expects(:_traced_method_name)
              self.expects(:method_defined?).returns(false)
              assert !traced_method_exists?(nil, nil)
            end

            def test_assemble_code_header_unforced
              self.expects(:_untraced_method_name).returns("method_name_without_tracing")
              opts = {:force => false, :code_header => 'CODE HEADER'}
              assert_equal "return method_name_without_tracing(*args, &block) unless NewRelic::Agent.tl_is_execution_traced?\nCODE HEADER", assemble_code_header('test_method', 'Custom/Test/test_method', opts)
            end

            def test_check_for_push_scope_and_metric_positive
              check_for_push_scope_and_metric({:push_scope => true})
              check_for_push_scope_and_metric({:metric => true})
            end

            def test_check_for_push_scope_and_metric_negative
              assert_raises(RuntimeError) do
                check_for_push_scope_and_metric({:push_scope => false, :metric => false})
              end
            end

            def test_code_to_eval_scoped
              self.expects(:validate_options).returns({:push_scope => true})
              self.expects(:method_with_push_scope).with('test_method', 'Custom/Test/test_method', {:push_scope => true})
              code_to_eval('test_method', 'Custom/Test/test_method', {})
            end

            def test_code_to_eval_unscoped
              self.expects(:validate_options).returns({:push_scope => false})
              self.expects(:method_without_push_scope).with('test', 'Custom/Test/test', {:push_scope => false})
              code_to_eval('test', 'Custom/Test/test', {})
            end
          end
        end
      end
    end
  end
end
