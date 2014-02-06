# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Instrumentation::MetricFrameTest < Minitest::Test

  # These tests are just here to make sure that we're maintaining the required
  # old interface for folks. Real testing of the underlying functionality
  # should go with the Transaction methods we invoke, not these tests.

  def test_recording_web_transaction
    NewRelic::Agent::Transaction.expects(:recording_web_transaction?)
    NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?
  end

  def test_abort_transaction
    NewRelic::Agent::Transaction.expects(:abort_transaction!)
    NewRelic::Agent::Instrumentation::MetricFrame.abort_transaction!
  end
end
