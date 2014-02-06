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

        def test_poll_records_thread_count
          fakeshot = NewRelic::Agent::VM::Snapshot.new
          fakeshot.thread_count = 2
          NewRelic::Agent::VM.stubs(:snapshot).returns(fakeshot)

          @sampler.poll
          expected = { 'RubyVM/Threads/all' => { :call_count => 2 } }
          assert_metrics_recorded(expected)
        end
      end
    end
  end
end
