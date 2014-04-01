# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/vm/snapshot'

class NewRelic::Agent::VM::SnapshotTestCase < Minitest::Test
  def test_records_taken_at_on_initialization
    t = freeze_time
    snap = NewRelic::Agent::VM::Snapshot.new
    assert_equal(t.to_f, snap.taken_at)
  end
end
