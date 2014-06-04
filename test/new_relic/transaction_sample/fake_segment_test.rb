# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'new_relic/transaction_sample/fake_segment'
class NewRelic::TransactionSample::FakeSegmentTest < Minitest::Test
  def test_fake_segment_creation
    NewRelic::TransactionSample::FakeSegment.new(0.1, 'Custom/test/metric')
  end

  def test_parent_segment
    # should be public in this class, but not in the parent class
    s = NewRelic::TransactionSample::FakeSegment.new(0.1, 'Custom/test/metric')
    s.parent_segment = 'foo'
    assert_equal('foo', s.instance_eval { @parent_segment } )
  end
end
