# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/delayed_job_instrumentation'

module NewRelic::Agent::Instrumentation
  class DelayedJobInstrumentationTest < Minitest::Test

    class DummyPayload
      include NewRelic::Agent::Instrumentation::DelayedJob::Naming
      attr_accessor :object
    end

    def test_legacy_performable_method
      payload_string = DummyPayload.new.tap { |dp| dp.object = 'LOAD;Foo' }
      payload_fixnum = DummyPayload.new.tap { |dp| dp.object = 123 }
      assert DummyPayload.new.send(:legacy_performable_method?, payload_string)
      refute DummyPayload.new.send(:legacy_performable_method?, payload_fixnum)
    end
  end
end
