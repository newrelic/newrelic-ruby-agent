require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/new_relic_thread'

class NewRelicThreadTest < Test::Unit::TestCase

  def test_sets_label
    t = NewRelicThread.new("labelled") {}
    assert_equal "labelled", t[:newrelic_label]
  end

  def test_is_new_relic_thread
    t = NewRelicThread.new("labelled") {}
    assert NewRelicThread.is_new_relic?(t)
  end

  def test_runs_block
    called = false

    t = NewRelicThread.new("labelled") { called = true }
    t.join

    assert called
  end
end
