# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

require 'new_relic/agent/threading/thread_profiling_service'
require 'new_relic/agent/threading/threaded_test_case'

module NewRelic::Agent::Threading::ThreadProfilingClientTests
  def test_responds_to_aggregate
    assert target_for_shared_client_tests.respond_to? :aggregate
  end

  def test_responds_to_requested_period
    assert target_for_shared_client_tests.respond_to? :requested_period
    assert target_for_shared_client_tests.requested_period.is_a? Numeric
  end

  def test_responds_to_finished?
    assert target_for_shared_client_tests.respond_to? :finished?
  end

  def test_responds_to_increment_poll_count
    assert target_for_shared_client_tests.respond_to? :increment_poll_count
  end
end
