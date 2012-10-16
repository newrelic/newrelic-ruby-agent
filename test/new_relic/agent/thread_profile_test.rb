require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'base64'
require 'json'
require 'thread'
require 'timeout'
require 'zlib'
require 'new_relic/agent/thread_profile'

class ThreadProfileTest < Test::Unit::TestCase

  def setup
    @single_trace = [
      "irb.rb:69:in `catch'",
      "irb.rb:69:in `start'",
      "irb:12:in `<main>'"
    ]

 end

  def test_profiler_polls_for_given_duration
    p = NewRelic::Agent::ThreadProfile.new(0, 0.21)
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

    p = NewRelic::Agent::ThreadProfile.new(0, 0.21)
    p.run

    sleep(0.22)

    assert_equal 2, p.poll_count
    assert_equal 6, p.sample_count

    other_thread.join
  end

  def test_profiler_collects_into_agent_bucket
    other_thread = Thread.new { sleep(0.3) }
    other_thread['newrelic_label'] = "Some Other New Relic Thread" 

    p = NewRelic::Agent::ThreadProfile.new(0, 0.21)
    p.run

    sleep(0.22)

    assert_equal 2, p.traces[:agent].size
  end

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

  def test_aggregate_builds_tree_from_first_trace
    profile = NewRelic::Agent::ThreadProfile.new(0, 0)
    result = profile.aggregate(@single_trace)

    tree = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-1])
    child = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-2], tree)
    NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-3], child)

    assert_equal tree, result
  end

  def test_aggregate_builds_tree_from_overlapping_traces
    profile = NewRelic::Agent::ThreadProfile.new(0, 0)
    result = profile.aggregate(@single_trace)
    result = profile.aggregate(@single_trace, [result])

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

    profile = NewRelic::Agent::ThreadProfile.new(0, 0)
    result = profile.aggregate(@single_trace)
    result = profile.aggregate(@single_trace, [result])

    tree = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-1])
    tree.runnable_count += 1 
 
    child = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-2], tree)
    grand = NewRelic::Agent::ThreadProfile::Node.new(@single_trace[-3], child)

    other_child = NewRelic::Agent::ThreadProfile::Node.new(other_trace[-2], tree)
    other_grand = NewRelic::Agent::ThreadProfile::Node.new(other_trace[-3], other_child)

    assert_equal tree, result
  end

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
    line = "irb.rb:69:in `catch'"
    parent = NewRelic::Agent::ThreadProfile::Node.new(line)
    child = NewRelic::Agent::ThreadProfile::Node.new(line)

    parent.add_child(child)
    parent.add_child(child)

    assert_equal 1, parent.children.size
  end

  def test_to_compressed_array
    profile = NewRelic::Agent::ThreadProfile.new(-1, 0)
    profile.instance_variable_set(:@start_time, 1350403938892.524)
    profile.instance_variable_set(:@stop_time, 1350403939904.375)
    profile.instance_variable_set(:@poll_count, 10)
    profile.instance_variable_set(:@sample_count, 2)

    trace = ["thread_profiler.py:1:in `<module>'"]
    10.times { profile.aggregate(trace, profile.traces[:other]) }

    trace = [
      "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:489:in `__bootstrap'", 
      "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:512:in `__bootstrap_inner'",
      "/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py:480:in `run'",
      "thread_profiler.py:76:in `_profiler_loop'",
      "thread_profiler.py:103:in `_run_profiler'",
      "thread_profiler.py:165:in `collect_thread_stacks'"]
    10.times { profile.aggregate(trace, profile.traces[:agent]) }
 
    expected = [42,
      [[
          -1, 
          1350403938892.524, 
          1350403939904.375, 
          10, 
          "eJy9klFPwjAUhf/LfW7WDQTUGBPUiYkGdAxelqXZRpGGrm1uS8xi/O924JQX\n9Un7dm77ndN7c19hlt7FCZxnWQZug7xYMYN6LSTHwDRA4KLWq53kl0CinEQh\nCUmW5zmBJH5axPPUk16MJ/E0/cGk0lLyyrGPS+uKamu943DQeX5HMtypz5In\nwv6vRCeZ1NoAGQ2PCDpvrOM1fRAlFtjQWyxq/qJxa+lj4zZaBeuuQpccrdDK\n0l4wolKU1OxftOoQLNTzIdL/EcjJafjnQYyVWjvrsDBMKNVOZBD1/jO27fPs\naBG+DoGr8fX9JJktpjftVry9A9unzGo=\n",
          2, 
          0
      ]]]

    with_config :agent_run_id => 42 do
      assert_equal expected, profile.to_compressed_array
    end
  end

  def test_compress
    original = '{"OTHER": [[["thread_profiler.py", "<module>", 1], 10, 0, []]], "REQUEST": [], "AGENT": [[["/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py", "__bootstrap", 489], 10, 0, [[["/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py", "__bootstrap_inner", 512], 10, 0, [[["/System/Library/Frameworks/Python.framework/Versions/2.7/lib/python2.7/threading.py", "run", 480], 10, 0, [[["thread_profiler.py", "_profiler_loop", 76], 10, 0, [[["thread_profiler.py", "_run_profiler", 103], 10, 0, [[["thread_profiler.py", "collect_thread_stacks", 165], 10, 0, []]]]]]]]]]]]], "BACKGROUND": []}'
    assert_equal( 
      "eJy9UtFOwjAU/ZWlz2QdKKCGmKBOTDSgY/iyLM02ijR0vcttiVmM/047J0LiA080bdJz2nPPbe/9IrP4KYzIjZckCTFr5NmSVQgrITn6VU06HhmVsNxKfmv33dSuoOPZmaSpBSQK3xbhPHYBHBxPwmncRqPzWhte0heRY4Y1fcSs5J+AG01fa7MG5a9+GfrOUQtQmvb8IZUip1Vzw6GfpIT6aNNhLAcw2mBWWXh5dX2Q01lcmVCKoyX73d5ZvHGrmpcGx27/V2uPmQRwPzQcnCSzJnvOVTq4OEVWgJS8MKw91SYrNtrJB/3jVvkbVnU3vn+eRLPF9KHpm+8dYyPRqg==",
      NewRelic::Agent::ThreadProfile.compress(original).gsub(/\n/, ''))
  end

  def test_finished
    profile = NewRelic::Agent::ThreadProfile.new(-1, 0)
    assert !profile.finished?

    profile.run.join

    assert profile.finished?
  end
end
