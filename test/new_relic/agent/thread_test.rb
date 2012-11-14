require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/thread'

class ThreadTest < Test::Unit::TestCase

  def test_sets_label
    t = NewRelic::Agent::Thread.new("labelled") {}
    assert_equal "labelled", t[:newrelic_label]
  end

  def test_is_new_relic_thread
    t = NewRelic::Agent::Thread.new("labelled") {}
    assert NewRelic::Agent::Thread.is_new_relic?(t)
  end

  def test_runs_block
    called = false

    t = NewRelic::Agent::Thread.new("labelled") { called = true }
    t.join

    assert called
  end
end
