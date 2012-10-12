require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'thread'
require 'timeout'
require 'new_relic/agent/thread_profiler'

class ThreadProfilerTest < Test::Unit::TestCase

  def test_profiler_polls_for_given_duration
    p = NewRelic::Agent::ThreadProfiler.new(0.21)
    assert_nothing_raised do
      thread = nil
      Timeout.timeout(0.22) do
        thread = p.run
      end
      thread.join
    end
  end

  def test_profiler_collects_backtrace_from_every_thread
    other_thread = Thread.new { sleep(0.3) }
    other_thread.expects(:backtrace).returns("Chunky bacon").twice

    p = NewRelic::Agent::ThreadProfiler.new(0.21)
    p.run

    sleep(0.22)

    assert_equal 6, p.backtraces.size
    assert_equal 2, p.backtraces.select { |b| b == "Chunky bacon" }.size

    other_thread.join
  end

end
