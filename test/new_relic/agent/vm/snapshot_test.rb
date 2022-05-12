# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative '../../../test_helper'
require 'new_relic/agent/vm/snapshot'

class NewRelic::Agent::VM::SnapshotTestCase < Minitest::Test
  def test_records_taken_at_on_initialization
    t = nr_freeze_process_time
    snap = NewRelic::Agent::VM::Snapshot.new
    assert_equal(t, snap.taken_at)
  end
end
