require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'base64'
require 'thread'
require 'timeout'
require 'zlib'
require 'new_relic/agent/threaded_test'
require 'new_relic/agent/thread_profiler'

START_COMMAND = [[666,{
    "name" => "start_profiler",
    "arguments" => {
      "profile_id" => 42,
      "sample_period" => 0.02,
      "duration" => 0.025,
      "only_runnable_threads" => false,
      "only_request_threads" => false,
      "profile_agent_code" => false,
    }
  }]]

STOP_COMMAND = [[666,{
    "name" => "stop_profiler",
    "arguments" => {
      "profile_id" => 42,
      "report_data" => true,
    }
  }]]

STOP_AND_DISCARD_COMMAND = [[666,{
    "name" => "stop_profiler",
    "arguments" => {
      "profile_id" => 42,
      "report_data" => false,
    }
  }]]

NO_COMMAND = []

if !NewRelic::Agent::ThreadProfiler.is_supported?

class ThreadProfilerUnsupportedTest < Test::Unit::TestCase
  def setup
    @profiler = NewRelic::Agent::ThreadProfiler.new
  end

  def test_thread_profiling_isnt_supported
    assert_equal false, NewRelic::Agent::ThreadProfiler.is_supported?
  end

  def test_wont_start_when_not_supported
    @profiler.start(0, 0, 0, true)
    assert_equal false, @profiler.running?
  end

  def test_stop_is_safe_when_not_supported
    @profiler.start(0, 0, 0, true)
    @profiler.stop(true)
  end

  def test_wont_start_and_reports_error
    errors = nil
    @profiler.respond_to_commands(START_COMMAND) { |_, err| errors = err }
    assert_equal false, errors.nil?
    assert_equal false, @profiler.running?
  end

end

else

require 'json'

class ThreadProfilerTest < ThreadedTest
  def setup
    super
    @profiler = NewRelic::Agent::ThreadProfiler.new
  end

  def test_is_supported
    assert NewRelic::Agent::ThreadProfiler.is_supported?
  end

  def test_is_not_running
    assert !@profiler.running?
  end

  def test_is_running
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?
  end

  def test_is_not_finished_if_no_profile_started
    assert !@profiler.finished?
  end

  def test_can_stop_a_running_profile
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.stop(true)

    assert @profiler.finished?
    assert_not_nil @profiler.profile
  end

  def test_can_stop_a_running_profile_and_discard
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.stop(false)

    assert_nil @profiler.profile
  end

  def test_wont_crash_if_stopping_when_not_started
    @profiler.stop(true)
    assert_equal false, @profiler.running?
  end

  def test_respond_to_commands_with_no_commands_doesnt_run
    @profiler.respond_to_commands(NO_COMMAND)
    assert_equal false, @profiler.running?
  end

  def test_respond_to_commands_starts_running
    @profiler.respond_to_commands(START_COMMAND) {|_, err| start_error = err}
    assert_equal true, @profiler.running?
  end

  def test_respond_to_commands_stops
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.respond_to_commands(STOP_COMMAND)
    assert_equal true, @profiler.profile.finished?
  end

  def test_respond_to_commands_stops_and_discards
    @profiler.start(0, 0, 0, true)
    assert @profiler.running?

    @profiler.respond_to_commands(STOP_AND_DISCARD_COMMAND)
    assert_nil @profiler.profile
  end

  def test_respond_to_commands_wont_start_second_profile
    @profiler.start(0, 0, 0, true)
    original_profile = @profiler.profile

    @profiler.respond_to_commands(START_COMMAND)

    assert_equal original_profile, @profiler.profile
  end

  def test_response_to_commands_start_notifies_of_result
    saw_command_id = nil
    @profiler.respond_to_commands(START_COMMAND) { |id, err| saw_command_id = id }
    assert_equal 666, saw_command_id
  end

  def test_response_to_commands_start_notifies_of_error
    saw_command_id = nil
    error = nil

    @profiler.respond_to_commands(START_COMMAND)
    @profiler.respond_to_commands(START_COMMAND) { |id, err| saw_command_id = id; error = err }

    assert_equal 666, saw_command_id
    assert_not_nil error
  end

  def test_response_to_commands_stop_notifies_of_result
    saw_command_id = nil
    @profiler.start(0,0, 0, true)
    @profiler.respond_to_commands(STOP_COMMAND) { |id, err| saw_command_id = id }
    assert_equal 666, saw_command_id
  end

  def test_command_attributes_passed_along
    @profiler.respond_to_commands(START_COMMAND)
    assert_equal 42,  @profiler.profile.profile_id
    assert_equal 0.02, @profiler.profile.interval
    assert_equal false, @profiler.profile.profile_agent_code
  end

  def test_missing_name_in_command
    command = [[666,{ "arguments" => {} } ]]
    @profiler.respond_to_commands(command)

    assert_equal false, @profiler.running?
  end

  def test_malformed_agent_command
    command = [[666]]
    @profiler.respond_to_commands(command)

    assert_equal false, @profiler.running?
  end

end

class ThreadProfileTest < ThreadedTest

  def setup
    super

    @single_trace = [
      "irb.rb:69:in `catch'",
      "irb.rb:69:in `start'",
      "irb:12:in `<main>'"
    ]

    @profile = NewRelic::Agent::ThreadProfile.new(-1, 0.029, 0.01, true)
  end

  # Running Tests
  def test_profiler_collects_backtrace_from_every_thread
    FakeThread.list << FakeThread.new
    FakeThread.list << FakeThread.new

    @profile.run

    assert_equal 2, @profile.poll_count
    assert_equal 4, @profile.sample_count
  end

  def test_profiler_collects_into_request_bucket
    FakeThread.list << FakeThread.new(
      :bucket => :request,
      :backtrace => @single_trace)

    @profile.run

    assert_equal 1, @profile.traces[:request].size
  end

  def test_profiler_collects_into_background_bucket
    FakeThread.list << FakeThread.new(
      :bucket => :background,
      :backtrace => @single_trace)

    @profile.run

    assert_equal 1, @profile.traces[:background].size
  end

  def test_profiler_collects_into_other_bucket
    FakeThread.list << FakeThread.new(
      :bucket => :other,
      :backtrace => @single_trace)

    @profile.run

    assert_equal 1, @profile.traces[:other].size
  end

  def test_profiler_collects_into_agent_bucket
    FakeThread.list << FakeThread.new(
      :bucket => :agent,
      :backtrace => @single_trace)

    @profile.run

    assert_equal 1, @profile.traces[:agent].size
  end

  def test_profiler_ignores_agent_threads_when_told_to
    FakeThread.list << FakeThread.new(
      :bucket => :ignore,
      :backtrace => @single_trace)

    @profile.run

    @profile.traces.each do |key, trace|
      assert trace.empty?, "Trace :#{key} should have been empty"
    end
  end

  def test_profiler_tries_to_scrub_backtraces
    FakeThread.list << FakeThread.new(
      :bucket => :agent,
      :backtrace => @single_trace,
      :scrubbed_backtrace => @single_trace[0..0])

    @profile.run

    assert_equal [], @profile.traces[:agent].first.children
  end

  def test_profile_can_be_stopped
    # Can't easily stop in middle of processing since FakeThread's synchronous
    # Mark to bail immediately, then see we didn't record anything
    @profile.stop

    @profile.run

    assert_not_nil @profile.stop_time
    assert_equal true, @profile.finished?

    assert_equal 0, @profile.poll_count
    @profile.traces.each do |key, trace|
      assert_equal [], trace, "Trace for :#{key} should have been empty"
    end
  end

  def test_profiler_tracks_time
    @profile.run

    assert_not_nil @profile.start_time
    assert_not_nil @profile.stop_time
  end

  def test_finished
    assert !@profile.finished?

    @profile.run.join

    assert @profile.finished?
  end

  # Parsing and Aggregation Tests
  def test_parse_backtrace
    trace = [
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb:69:in `catch'",
      "/Users/jclark/.rbenv/versions/1.9.3-p194/lib/ruby/1.9.1/irb.rb:69:in `start'",
      "/Users/jclark/.rbenv/versions/1.9.3/bin/irb:12:in `<main>'"
    ]

    result = NewRelic::Agent::ThreadProfile.parse_backtrace(trace)
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

  def test_aggregate_empty_trace
    result = @profile.aggregate([])
    assert_nil result
  end

  def test_aggregate_nil_trace
    result = @profile.aggregate(nil)
    assert_nil result
  end

  def test_aggregate_builds_tree_from_first_trace
    result = @profile.aggregate(@single_trace)

    tree = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-1])
    child = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-2], tree)
    NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-3], child)

    assert_equal tree, result
  end

  def test_aggregate_builds_tree_from_overlapping_traces
    result = @profile.aggregate(@single_trace)
    result = @profile.aggregate(@single_trace, [result])

    tree = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-1])
    tree.runnable_count += 1
    child = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-2], tree)
    child.runnable_count += 1
    grand = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-3], child)
    grand.runnable_count += 1

    assert_equal tree, result
  end

  def test_aggregate_builds_tree_from_diverging_traces
    other_trace = [
      "irb.rb:69:in `catch'",
      "chunky_bacon.rb:42:in `start'",
      "irb:12:in `<main>'"
    ]

    result = @profile.aggregate(@single_trace)
    result = @profile.aggregate(@single_trace, [result])

    tree = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-1])
    tree.runnable_count += 1

    child = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-2], tree)
    grand = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-3], child)

    other_child = NewRelic::Agent::ThreadProfile::Node.new(other_trace[-2], tree)
    other_grand = NewRelic::Agent::ThreadProfile::Node.new(other_trace[-3], other_child)

    assert_equal tree, result
  end

  def test_prune_tree
    @profile.aggregate(@single_trace)

    t = @profile.prune!(1)

    assert_equal 0, @profile.traces[:request].first.children.size
  end

  def test_prune_keeps_highest_counts
    @profile.aggregate(@single_trace, @profile.traces[:request])
    @profile.aggregate(@single_trace, @profile.traces[:other])
    @profile.aggregate(@single_trace, @profile.traces[:other])

    @profile.prune!(1)

    assert_equal [], @profile.traces[:request]
    assert_equal 1, @profile.traces[:other].size
    assert_equal [], @profile.traces[:other][0].children
  end

  def test_prune_keeps_highest_count_then_depths
    @profile.aggregate(@single_trace, @profile.traces[:request])
    @profile.aggregate(@single_trace, @profile.traces[:other])

    @profile.prune!(2)

    assert_equal 1, @profile.traces[:request].size
    assert_equal 1, @profile.traces[:other].size
    assert_equal [], @profile.traces[:request][0].children
    assert_equal [], @profile.traces[:other][0].children
  end

  def test_to_compressed_array
    @profile.instance_variable_set(:@start_time, 1350403938892.524)
    @profile.instance_variable_set(:@stop_time, 1350403939904.375)
    @profile.instance_variable_set(:@poll_count, 10)
    @profile.instance_variable_set(:@sample_count, 2)

    trace = ["thread_profiler.py:1:in `<module>'"]
    10.times { @profile.aggregate(trace, @profile.traces[:other]) }

    trace = [
      "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:489:in `__bootstrap'", 
      "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:512:in `__bootstrap_inner'",
      "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:480:in `run'",
      "thread_profiler.py:76:in `_profiler_loop'",
      "thread_profiler.py:103:in `_run_profiler'",
      "thread_profiler.py:165:in `collect_thread_stacks'"]
    10.times { @profile.aggregate(trace, @profile.traces[:agent]) }
 
    expected = [[
          -1, 
          1350403938892.524, 
          1350403939904.375, 
          10, 
          "eJy9klFPwjAUhf/LfW7WDQTUGBPUiYkGdAxelqXZRpGGrm1uS8xi/O924JQX\n9Un7dm77ndN7c19hlt7FCZxnWQZug7xYMYN6LSTHwDRA4KLWq53kl0CinEQh\nCUmW5zmBJH5axPPUk16MJ/E0/cGk0lLyyrGPS+uKamu943DQeX5HMtypz5In\nwv6vRCeZ1NoAGQ2PCDpvrOM1fRAlFtjQWyxq/qJxa+lj4zZaBeuuQpccrdDK\n0l4wolKU1OxftOoQLNTzIdL/EcjJafjnQYyVWjvrsDBMKNVOZBD1/jO27fPs\naBG+DoGr8fX9JJktpjftVry9A9unzGo=\n",
          2, 
          0
      ]]

    assert_equal expected, @profile.to_compressed_array
  end

  def test_compress
    original = '{"OTHER": [[["thread_profiler.py", "<module>", 1], 10, 0, []]], "REQUEST": [], "AGENT": [[["/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py", "__bootstrap", 489], 10, 0, [[["/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py", "__bootstrap_inner", 512], 10, 0, [[["/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py", "run", 480], 10, 0, [[["thread_profiler.py", "_profiler_loop", 76], 10, 0, [[["thread_profiler.py", "_run_profiler", 103], 10, 0, [[["thread_profiler.py", "collect_thread_stacks", 165], 10, 0, []]]]]]]]]]]]], "BACKGROUND": []}'
    assert_equal( 
      "eJy9UtFOwjAU/ZWlz2QdKKCGmKBOTDSgY/iyLM02ijR0vcttiVmM/047J0LiA080bdJz2nPPbe/9IrP4KYzIjZckCTFr5NmSVQgrITn6VU06HhmVsNxKfmv33dSuoOPZmaSpBSQK3xbhPHYBHBxPwmncRqPzWhte0heRY4Y1fcSs5J+AG01fa7MG5a9+GfrOUQtQmvb8IZUip1Vzw6GfpIT6aNNhLAcw2mBWWXh5dX2Q01lcmVCKoyX73d5ZvHGrmpcGx27/V2uPmQRwPzQcnCSzJnvOVTq4OEVWgJS8MKw91SYrNtrJB/3jVvkbVnU3vn+eRLPF9KHpm+8dYyPRqg==",
      NewRelic::Agent::ThreadProfile.compress(original).gsub(/\n/, ''))
  end
end

class ThreadProfileNodeTest < Test::Unit::TestCase
  SINGLE_LINE = "irb.rb:69:in `catch'"

  def test_single_node_converts_to_array
    line = "irb.rb:69:in `catch'"
    node = NewRelic::Agent::ThreadProfile::Node.new(line)

    assert_equal([
        ["irb.rb", "catch", 69],
        0, 0,
        []],
      node.to_array)
  end

  def test_multiple_nodes_converts_to_array
    line = "irb.rb:69:in `catch'"
    child_line = "bacon.rb:42:in `yum'"
    node = NewRelic::Agent::ThreadProfile::Node.new(line)
    child = NewRelic::Agent::ThreadProfile::Node.new(child_line, node)

    assert_equal([
        ["irb.rb", "catch", 69],
        0, 0,
        [
          [
            ['bacon.rb', 'yum', 42],
            0,0,
            []
          ]
        ]],
      node.to_array)
  end

  def test_add_child_twice
    parent = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE)
    child = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE)

    parent.add_child(child)
    parent.add_child(child)

    assert_equal 1, parent.children.size
  end

  def test_prune_keeps_children
    parent = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE)
    child = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE, parent)

    parent.prune!

    assert_equal [child], parent.children
  end

  def test_prune_removes_children
    parent = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE)
    child = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE, parent)

    child.to_prune = true
    parent.prune!

    assert_equal [], parent.children
  end

  def test_prune_removes_grandchildren
    parent = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE)
    child = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE, parent)
    grandchild = NewRelic::Agent::ThreadProfile::Node.new(SINGLE_LINE, child)

    grandchild.to_prune = true
    parent.prune!

    assert_equal [child], parent.children
    assert_equal [], child.children
  end

end
end
