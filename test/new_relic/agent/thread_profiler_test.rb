require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'thread'
require 'timeout'
require 'new_relic/agent/thread_profiler'

class ThreadProfilerTest < Test::Unit::TestCase

  def setup
    @single_trace = [
      "irb.rb:69:in `catch'",
      "irb.rb:69:in `start'",
      "irb:12:in `<main>'"
    ]

 end

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

  def test_parse_backtrace
    trace = [
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb:69:in `catch'",
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb:69:in `start'",
      "/Users/jclark/.rbenv/versions/1.9.3/bin/irb:12:in `<main>'"
    ]    

    result = NewRelic::Agent::ThreadProfiler.parse_backtrace(trace)
    assert_equal({ :method => 'catch', 
                   :file => '/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb', 
                   :line_no => 69 }, result[0])
    assert_equal({ :method => 'start', 
                   :file => '/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb', 
                   :line_no => 69 }, result[1])
    assert_equal({ :method => '<main>', 
                   :file => '/Users/jclark/.rbenv/versions/1.9.3/bin/irb', 
                   :line_no => 12 }, result[2])
  end

  def test_aggregate_builds_tree_from_first_trace
    parsed = NewRelic::Agent::ThreadProfiler.parse_backtrace(@single_trace)
    result = NewRelic::Agent::ThreadProfiler.aggregate(parsed)

    expected_tree = {
      { :file => 'irb', :line_no => 12, :method => '<main>'} => {
        :runnable_count => 1,
        :children => {
          { :file => 'irb.rb', :line_no => 69, :method => 'start' } => {
            :runnable_count => 1,
            :children => {
              { :file => 'irb.rb', :line_no => 69, :method => 'catch' } => {
                :runnable_count => 1,
                :children => {}
              }
            }
          }
        }
      }
    }
 
    assert_equal expected_tree, result
  end

  def test_aggregate_builds_tree_from_overlapping_traces
    parsed = NewRelic::Agent::ThreadProfiler.parse_backtrace(@single_trace)
 
    result = NewRelic::Agent::ThreadProfiler.aggregate(parsed)
    result = NewRelic::Agent::ThreadProfiler.aggregate(parsed, result)

    expected_tree = {
      { :file => 'irb', :line_no => 12, :method => '<main>'} => {
        :runnable_count => 2,
        :children => {
          { :file => 'irb.rb', :line_no => 69, :method => 'start' } => {
            :runnable_count => 2,
            :children => {
              { :file => 'irb.rb', :line_no => 69, :method => 'catch' } => {
                :runnable_count => 2,
                :children => {}
              }
            }
          }
        }
      }
    }
 
    assert_equal expected_tree, result
  end

  def test_aggregate_builds_tree_from_diverging_traces
    other_trace = [
      "irb.rb:69:in `catch'",
      "chunky_bacon.rb:42:in `start'",
      "irb:12:in `<main>'"
    ]

    parsed1 = NewRelic::Agent::ThreadProfiler.parse_backtrace(@single_trace)
    parsed2 = NewRelic::Agent::ThreadProfiler.parse_backtrace(other_trace)
    result = NewRelic::Agent::ThreadProfiler.aggregate(parsed1)
    result = NewRelic::Agent::ThreadProfiler.aggregate(parsed2, result)

    expected_tree = {
      { :file => 'irb', :line_no => 12, :method => '<main>'} => {
        :runnable_count => 2,
        :children => {
          { :file => 'irb.rb', :line_no => 69, :method => 'start' } => {
            :runnable_count => 1,
            :children => {
              { :file => 'irb.rb', :line_no => 69, :method => 'catch' } => {
                :runnable_count => 1,
                :children => {}
              }
            }
          },
          { :file => 'chunky_bacon.rb', :line_no => 42, :method => 'start' } => {
            :runnable_count => 1,
            :children => {
              { :file => 'irb.rb', :line_no => 69, :method => 'catch' } => {
                :runnable_count => 1,
                :children => {}
              }
            }
          },
        }
      }
    }

    assert_equal expected_tree, result
  end

end
