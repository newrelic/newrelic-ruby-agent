# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/samplers/vm_sampler'
require 'new_relic/agent/vm/snapshot'

module NewRelic
  module Agent
    module Samplers
      class VMSamplerTest < Minitest::Test
        def setup
          @sampler = VMSampler.new
        end

        def test_supported_on_this_platform?
          assert VMSampler.supported_on_this_platform?
        end

        def test_records_transaction_count
          @sampler.setup_events(NewRelic::Agent.instance.events)
          10.times { in_transaction('txn') { } }

          assert_equal(10, @sampler.transaction_count)
        end

        def test_reset_transaction_count
          @sampler.setup_events(NewRelic::Agent.instance.events)
          10.times { in_transaction('txn') { } }

          old_count = @sampler.reset_transaction_count
          assert_equal(10, old_count)
          assert_equal(0, @sampler.transaction_count)
        end

        def test_poll_records_thread_count
          stub_snapshot(:thread_count => 2)

          @sampler.poll
          expected = { 'RubyVM/Threads/all' => { :call_count => 2 } }
          assert_metrics_recorded(expected)
        end

        def stub_snapshot(values)
          fakeshot = NewRelic::Agent::VM::Snapshot.new
          values.each do |key, value|
            fakeshot.send("#{key}=", value)
          end
          NewRelic::Agent::VM.stubs(:snapshot).returns(fakeshot)
          fakeshot
        end
      end
    end
  end
end
