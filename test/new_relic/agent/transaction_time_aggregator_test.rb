# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/transaction_time_aggregator'

class NewRelic::Agent::TransctionTimeAggregatorTest < Minitest::Test

  def test_simple
    nr_freeze_time

    3.times do
      advance_time 1
      NewRelic::Agent::TransactionTimeAggregator.transaction_started
      advance_time 10
      NewRelic::Agent::TransactionTimeAggregator.transaction_stopped
    end

    # Advance to 60 seconds (harvest time)
    advance_time 27

    transaction_time = NewRelic::Agent::TransactionTimeAggregator.harvest!
    busy = transaction_time / 60

    assert_equal 0.5, busy
  end

end