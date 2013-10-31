# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::TransactionSamplerTest < Test::Unit::TestCase

  module MockGCStats

    def time
      return 0 if @@values.empty?
      raise "too many calls" if @@index >= @@values.size
      @@curtime ||= 0
      @@curtime += (@@values[@@index] * 1e09).to_i
      @@index += 1
      @@curtime
    end

    def self.mock_values= array
      @@values = array
      @@index = 0
    end

  end

  def setup
    NewRelic::Agent::TransactionState.clear
    agent = NewRelic::Agent.instance
    stats_engine = NewRelic::Agent::StatsEngine.new
    agent.stubs(:stats_engine).returns(stats_engine)
    @sampler = NewRelic::Agent::TransactionSampler.new
    stats_engine.transaction_sampler = @sampler
    @old_sampler = NewRelic::Agent.instance.transaction_sampler
    NewRelic::Agent.instance.instance_variable_set(:@transaction_sampler, @sampler)
    @test_config = { :'transaction_tracer.enabled' => true }
    NewRelic::Agent.config.apply_config(@test_config)
    @txn = stub('txn', :name => '/path', :custom_parameters => {})
  end

  def teardown
    super
    NewRelic::Agent::TransactionState.clear
    NewRelic::Agent.config.remove_config(@test_config)
    NewRelic::Agent.instance.instance_variable_set(:@transaction_sampler, @old_sampler)
  end

  def test_notice_first_scope_push_default
    @sampler.expects(:start_builder).with(100.0)
    @sampler.notice_first_scope_push(Time.at(100))
  end

  def test_notice_first_scope_push_disabled
    with_config(:'transaction_tracer.enabled' => false,
                :developer_mode => false) do
      @sampler.expects(:start_builder).never
      @sampler.notice_first_scope_push(Time.at(100))
    end
  end

  def test_notice_push_scope_no_builder
    @sampler.expects(:builder)
    assert_equal(nil, @sampler.notice_push_scope())
  end

  def test_notice_push_scope_with_builder
    with_config(:developer_mode => false) do
      builder = mock('builder')
      builder.expects(:trace_entry).with(100.0)
      @sampler.expects(:builder).returns(builder).twice
      @sampler.notice_push_scope(Time.at(100))
    end
  end

  def test_notice_pop_scope_no_builder
    @sampler.expects(:builder).returns(nil)
    assert_equal(nil, @sampler.notice_pop_scope('a scope', Time.at(100)))
  end

  def test_notice_pop_scope_with_finished_sample
    builder = mock('builder')
    sample = mock('sample')
    builder.expects(:sample).returns(sample)
    sample.expects(:finished).returns(true)
    @sampler.expects(:builder).returns(builder).twice

    assert_raise(RuntimeError) do
      @sampler.notice_pop_scope('a scope', Time.at(100))
    end
  end

  def test_notice_pop_scope_builder_delegation
    builder = mock('builder')
    builder.expects(:trace_exit).with('a scope', 100.0)
    sample = mock('sample')
    builder.expects(:sample).returns(sample)
    sample.expects(:finished).returns(false)
    @sampler.expects(:builder).returns(builder).times(3)

    @sampler.notice_pop_scope('a scope', Time.at(100))
  end

  def test_notice_scope_empty_no_builder
    @sampler.expects(:builder).returns(nil)
    assert_equal(nil, @sampler.notice_scope_empty(@txn))
  end

  def test_notice_scope_empty_ignored_transaction
    builder = mock('builder')
    # the builder should be cached, so only called once
    @sampler.expects(:builder).returns(builder).once

    builder.expects(:finish_trace).with(100.0, {})

    @sampler.expects(:clear_builder)

    builder.expects(:ignored?).returns(true)
    builder.expects(:set_transaction_name).returns(true)

    assert_equal(nil, @sampler.notice_scope_empty(@txn, Time.at(100)))
  end

  def test_notice_scope_empty_with_builder
    builder = mock('builder')
    @sampler.stubs(:builder).returns(builder)


    builder.expects(:finish_trace).with(100.0, {})
    @sampler.expects(:clear_builder)

    builder.expects(:ignored?).returns(false)
    builder.expects(:set_transaction_info).returns(true)
    builder.expects(:set_transaction_name).returns(true)

    sample = mock('sample')
    builder.expects(:sample).returns(sample)
    @sampler.expects(:store_sample).with(sample)

    @sampler.notice_transaction(nil, {})
    @sampler.notice_scope_empty(@txn, Time.at(100))

    assert_equal(sample, @sampler.instance_variable_get('@last_sample'))
  end

  def test_ignore_transaction_no_builder
    @sampler.expects(:builder).returns(nil).once
    @sampler.ignore_transaction
  end

  def test_ignore_transaction_with_builder
    builder = mock('builder')
    builder.expects(:ignore_transaction)
    @sampler.expects(:builder).returns(builder).twice
    @sampler.ignore_transaction
  end

  def test_notice_profile_no_builder
    @sampler.expects(:builder).returns(nil).once
    @sampler.notice_profile(nil)
  end

  def test_notice_profile_with_builder
    profile = mock('profile')
    builder = mock('builder')
    @sampler.expects(:builder).returns(builder).twice
    builder.expects(:set_profile).with(profile)

    @sampler.notice_profile(profile)
  end

  def test_notice_transaction_cpu_time_no_builder
    @sampler.expects(:builder).returns(nil).once
    @sampler.notice_transaction_cpu_time(0.0)
  end

  def test_notice_transaction_cpu_time_with_builder
    cpu_time = mock('cpu_time')
    builder = mock('builder')
    @sampler.expects(:builder).returns(builder).twice
    builder.expects(:set_transaction_cpu_time).with(cpu_time)

    @sampler.notice_transaction_cpu_time(cpu_time)
  end

  def test_notice_extra_data_no_builder
    @sampler.expects(:builder).returns(nil).once
    @sampler.send(:notice_extra_data, nil, nil, nil)
  end

  def test_notice_extra_data_no_segment
    builder = mock('builder')
    @sampler.expects(:builder).returns(builder).twice
    builder.expects(:current_segment).returns(nil)
    @sampler.send(:notice_extra_data, nil, nil, nil)
  end

  def test_notice_extra_data_with_segment_no_old_message_no_config_key
    key = :a_key
    builder = mock('builder')
    segment = mock('segment')
    @sampler.expects(:builder).returns(builder).twice
    builder.expects(:current_segment).returns(segment)
    segment.expects(:[]).with(key).returns(nil)
    @sampler.expects(:append_new_message).with(nil, 'a message').returns('a message')
    NewRelic::Agent::TransactionSampler.expects(:truncate_message) \
      .with('a message').returns('truncated_message')
    segment.expects(:[]=).with(key, 'truncated_message')
    @sampler.expects(:append_backtrace).with(segment, 1.0)
    @sampler.send(:notice_extra_data, 'a message', 1.0, key)
  end

  def test_truncate_message_short_message
    message = 'a message'
    assert_equal(message, NewRelic::Agent::TransactionSampler.truncate_message(message))
  end

  def test_truncate_message_long_message
    message = 'a' * 16384
    truncated_message = NewRelic::Agent::TransactionSampler.truncate_message(message)
    assert_equal(16384, truncated_message.length)
    assert_equal('a' * 16381 + '...', truncated_message)
  end

  def test_append_new_message_no_old_message
    old_message = nil
    new_message = 'a message'
    assert_equal(new_message, @sampler.append_new_message(old_message, new_message))
  end

  def test_append_new_message_with_old_message
    old_message = 'old message'
    new_message = ' a message'
    assert_equal("old message;\n a message", @sampler.append_new_message(old_message, new_message))
  end

  def test_append_backtrace_under_duration
    with_config(:'transaction_tracer.stack_trace_threshold' => 2.0) do
      segment = mock('segment')
      segment.expects(:[]=).with(:backtrace, any_parameters).never
      @sampler.append_backtrace(mock('segment'), 1.0)
    end
  end

  def test_append_backtrace_over_duration
    with_config(:'transaction_tracer.stack_trace_threshold' => 2.0) do
      segment = mock('segment')
      # note the mocha expectation matcher - you can't hardcode a
      # backtrace so we match on any string, which should be okay.
      segment.expects(:[]=).with(:backtrace, instance_of(String))
      @sampler.append_backtrace(segment, 2.5)
    end
  end

  def test_notice_sql_recording_sql
    NewRelic::Agent::TransactionState.get.record_sql = true
    @sampler.expects(:notice_extra_data).with('some sql', 1.0, :sql)
    @sampler.notice_sql('some sql', {:config => 'a config'}, 1.0)
  end

  def test_notice_sql_not_recording
    NewRelic::Agent::TransactionState.get.record_sql = false
    @sampler.expects(:notice_extra_data).with('some sql', 1.0, :sql).never # <--- important
    @sampler.notice_sql('some sql', {:config => 'a config'}, 1.0)
  end

  def test_notice_nosql
    @sampler.expects(:notice_extra_data).with('a key', 1.0, :key)
    @sampler.notice_nosql('a key', 1.0)
  end

  def test_harvest_when_disabled
    with_config(:'transaction_tracer.enabled' => false,
                :developer_mode => false) do
      assert_equal([], @sampler.harvest)
    end
  end

  def test_harvest_defaults
    # making sure the sampler clears out the old samples
    @sampler.instance_eval do
      @last_sample = 'a sample'
    end

    assert_equal([], @sampler.harvest)

    # make sure the samples have been cleared
    assert_equal(nil, @sampler.instance_variable_get('@last_sample'))
  end

  def test_harvest_no_data
    assert_equal([], @sampler.harvest)
  end

  def test_add_samples_holds_onto_previous_result
    sample = sample_with(:duration => 1)
    @sampler.merge!([sample])
    assert_equal([sample], @sampler.harvest)
  end

  def test_merge_avoids_dups
    sample = sample_with(:duration => 1)
    @sampler.merge!([sample, sample])
    assert_equal([sample], @sampler.harvest)
  end

  def test_harvest_avoids_dups_from_harvested_samples
    sample = sample_with(:duration => 2.5, :force_persist => false)
    @sampler.store_sample(sample)
    @sampler.store_sample(sample)

    assert_equal([sample], @sampler.harvest)
  end

  def test_merge_avoids_dups_from_forced
    sample = sample_with(:duration => 1, :force_persist => true)
    @sampler.merge!([sample, sample])
    assert_equal([sample], @sampler.harvest)
  end

  def test_harvest_adding_slowest
    sample = sample_with(:duration => 2.5, :force_persist => false)
    @sampler.store_sample(sample)

    assert_equal([sample], @sampler.harvest)
  end

  def test_harvest_new_slower_sample_replaces_older
    faster_sample = sample_with(:duration => 5.0)
    slower_sample = sample_with(:duration => 10.0)

    @sampler.store_sample(slower_sample)
    @sampler.merge!([faster_sample])

    assert_equal([slower_sample], @sampler.harvest)
  end

  def test_harvest_keep_older_slower_sample
    faster_sample = sample_with(:duration => 5.0)
    slower_sample = sample_with(:duration => 10.0)

    @sampler.store_sample(faster_sample)
    @sampler.merge!([slower_sample])

    assert_equal([slower_sample], @sampler.harvest)
  end

  def test_harvest_keep_force_persist_in_previous_results
    unforced_sample = sample_with(:duration => 10, :force_persist => false)
    forced_sample = sample_with(:duration => 1, :force_persist => true)

    @sampler.merge!([unforced_sample, forced_sample])
    result = @sampler.harvest

    assert_includes(result, unforced_sample)
    assert_includes(result, forced_sample)
  end

  def test_harvest_keeps_force_persist_in_new_results
    forced_sample = sample_with(:duration => 1, :force_persist => true)
    @sampler.store_sample(forced_sample)

    unforced_sample = sample_with(:duration => 10, :force_persist => false)
    @sampler.store_sample(unforced_sample)

    result = @sampler.harvest

    assert_includes(result, unforced_sample)
    assert_includes(result, forced_sample)
  end

  def test_harvest_keeps_forced_from_new_and_previous_results
    new_forced = sample_with(:duration => 1, :force_persist => true)
    @sampler.store_sample(new_forced)

    old_forced = sample_with(:duration => 1, :force_persist => true)

    @sampler.merge!([old_forced])
    result = @sampler.harvest

    assert_includes(result, new_forced)
    assert_includes(result, old_forced)
  end

  FORCE_PERSIST_MAX = NewRelic::Agent::Transaction::ForcePersistSampleBuffer::CAPACITY
  SLOWEST_SAMPLE_MAX = NewRelic::Agent::Transaction::SlowestSampleBuffer::CAPACITY
  XRAY_SAMPLE_MAX = NewRelic::Agent.config[:'xray_session.max_samples']

  def test_harvest_respects_limits_from_previous
    slowest = sample_with(:duration => 10.0)
    previous = [slowest]

    forced_samples = generate_samples(100, :force_persist => true)
    previous.concat(forced_samples)

    xray_samples = generate_samples(100, :transaction_name => "Active/xray")
    previous.concat(xray_samples)

    result = nil
    with_active_xray_session("Active/xray") do
      @sampler.merge!(previous)
      result = @sampler.harvest
    end

    expected = [slowest]
    expected = expected.concat(forced_samples.last(FORCE_PERSIST_MAX))
    expected = expected.concat(xray_samples.first(XRAY_SAMPLE_MAX))

    assert_equal_unordered(expected, result)
  end

  def test_harvest_respects_limits_from_current_traces
    slowest = sample_with(:duration => 10.0)
    @sampler.store_sample(slowest)

    forced_samples = generate_samples(100, :force_persist => true)
    forced_samples.each do |forced|
      @sampler.store_sample(forced)
    end

    xray_samples = generate_samples(100, :transaction_name => "Active/xray")
    with_active_xray_session("Active/xray") do
      xray_samples.each do |xrayed|
        @sampler.store_sample(xrayed)
      end
    end

    result = @sampler.harvest

    expected = [slowest]
    expected = expected.concat(forced_samples.last(FORCE_PERSIST_MAX))
    expected = expected.concat(xray_samples.first(XRAY_SAMPLE_MAX))
    assert_equal_unordered(expected, result)
  end

  class BoundlessBuffer < NewRelic::Agent::Transaction::TransactionSampleBuffer
    def capacity
      1.0 / 0 # Can't use Float::INFINITY on older Rubies :(
    end
  end

  def test_harvest_has_hard_maximum
    boundless_buffer = BoundlessBuffer.new

    buffers = @sampler.instance_variable_get(:@sample_buffers)
    buffers << boundless_buffer

    samples = generate_samples(100)
    samples.each do |sample|
      @sampler.store_sample(sample)
    end

    result = @sampler.harvest
    assert_equal NewRelic::Agent::Transaction::TransactionSampleBuffer::SINGLE_BUFFER_MAX, result.length
  end

  def test_start_builder_default
    NewRelic::Agent.expects(:is_execution_traced?).returns(true)
    @sampler.send(:start_builder)
    assert(NewRelic::Agent::TransactionState.get.transaction_sample_builder \
             .is_a?(NewRelic::Agent::TransactionSampleBuilder),
           "should set up a new builder by default")
  end

  def test_start_builder_disabled
    NewRelic::Agent::TransactionState.get.transaction_sample_builder = 'not nil.'
    with_config(:'transaction_tracer.enabled' => false,
                :developer_mode => false) do
      @sampler.send(:start_builder)
      assert_equal(nil, NewRelic::Agent::TransactionState.get.transaction_sample_builder,
                   "should clear the transaction builder when disabled")
    end
  end

  def test_start_builder_dont_replace_existing_builder
    fake_builder = mock('transaction sample builder')
    NewRelic::Agent::TransactionState.get.transaction_sample_builder = fake_builder
    @sampler.send(:start_builder)
    assert_equal(fake_builder, NewRelic::Agent::TransactionState.get.transaction_sample_builder,
                 "should not overwrite an existing transaction sample builder")
    NewRelic::Agent::TransactionState.get.transaction_sample_builder = nil
  end

  def test_builder
    NewRelic::Agent::TransactionState.get.transaction_sample_builder = 'shamalamadingdong, brother.'
    assert_equal('shamalamadingdong, brother.', @sampler.send(:builder),
                 'should return the value from the thread local variable')
    NewRelic::Agent::TransactionState.get.transaction_sample_builder = nil
  end

  def test_clear_builder
    NewRelic::Agent::TransactionState.get.transaction_sample_builder = 'shamalamadingdong, brother.'
    assert_equal(nil, @sampler.send(:clear_builder), 'should clear the thread local variable')
  end

  # Tests below this line are functional tests for the sampler, not
  # unit tests per se - some overlap with the tests above, but
  # generally usefully so


  def test_sample_tree
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_transaction(nil, {})
      @sampler.notice_push_scope

      @sampler.notice_push_scope
      @sampler.notice_pop_scope "b"

      @sampler.notice_push_scope
      @sampler.notice_push_scope
      @sampler.notice_pop_scope "d"
      @sampler.notice_pop_scope "c"

      @sampler.notice_pop_scope "a"
      @sampler.notice_scope_empty(@txn)
      sample = @sampler.harvest.first
      assert_equal "ROOT{a{b,c{d}}}", sample.to_s_compact
    end
  end

  def test_sample__gc_stats
    GC.extend MockGCStats
    # These are effectively Garbage Collects, detected each time GC.time is
    # called by the transaction sampler.  One time value in seconds for each call.
    MockGCStats.mock_values = [0,0,0,1,0,0,1,0,0,0,0,0,0,0,0]

    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_transaction(nil, {})
      @sampler.notice_push_scope

      @sampler.notice_push_scope
      @sampler.notice_pop_scope "b"

      @sampler.notice_push_scope
      @sampler.notice_push_scope
      @sampler.notice_pop_scope "d"
      @sampler.notice_pop_scope "c"

      @sampler.notice_pop_scope "a"
      @sampler.notice_scope_empty(@txn)

      sample = @sampler.harvest.first
      assert_equal "ROOT{a{b,c{d}}}", sample.to_s_compact
    end
  ensure
    MockGCStats.mock_values = []
  end

  # NB this test occasionally fails due to a GC during one of the
  # sample traces, for example. It's unfortunate, but we can't
  # reliably turn off GC on all versions of ruby under test
  def test_harvest_slowest
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      run_sample_trace(0,0.1)
      run_sample_trace(0,0.1)
      # two second duration
      run_sample_trace(0,2)
      run_sample_trace(0,0.1)
      run_sample_trace(0,0.1)

      slowest = @sampler.harvest[0]
      first_duration = slowest.duration
      assert((first_duration.round >= 2),
             "expected sample duration = 2, but was: #{slowest.duration.inspect}")

      # 1 second duration
      run_sample_trace(0,1)
      @sampler.merge!([slowest])
      not_as_slow = @sampler.harvest[0]
      assert((not_as_slow == slowest), "Should re-harvest the same transaction since it should be slower than the new transaction - expected #{slowest.inspect} but got #{not_as_slow.inspect}")

      run_sample_trace(0,10)

      @sampler.merge!([slowest])
      new_slowest = @sampler.harvest[0]
      assert((new_slowest != slowest), "Should not harvest the same trace since the new one should be slower")
      assert_equal(new_slowest.duration.round, 10, "Slowest duration must be = 10, but was: #{new_slowest.duration.inspect}")
    end
  end

  def test_prepare_to_send
    sample = with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      run_sample_trace { sleep 0.002 }
      @sampler.harvest[0]
    end

    ready_to_send = sample.prepare_to_send!
    assert sample.duration == ready_to_send.duration

    assert ready_to_send.start_time.is_a?(Time)
  end

  def test_multithread
    threads = []

    5.times do
      t = Thread.new(@sampler) do |the_sampler|
        @sampler = the_sampler
        10.times do
          run_sample_trace { sleep 0.0001 }
        end
      end

      threads << t
    end
    threads.each {|t| t.join }
  end

  def test_sample_with_parallel_paths
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_transaction(nil, {})
      @sampler.notice_push_scope

      assert_equal 1, @sampler.builder.scope_depth

      @sampler.notice_pop_scope "a"
      @sampler.notice_scope_empty(@txn)

      assert_nil @sampler.builder

      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_transaction(nil, {})
      @sampler.notice_push_scope
      @sampler.notice_pop_scope "a"
      @sampler.notice_scope_empty(@txn)

      assert_nil @sampler.builder

      assert_equal "ROOT{a}", @sampler.last_sample.to_s_compact
    end
  end

  def test_double_scope_stack_empty
    with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_transaction(nil, {})
      @sampler.notice_push_scope
      @sampler.notice_pop_scope "a"
      @sampler.notice_scope_empty(@txn)
      @sampler.notice_scope_empty(@txn)
      @sampler.notice_scope_empty(@txn)
      @sampler.notice_scope_empty(@txn)

      assert_not_nil @sampler.harvest[0]
    end
  end


  def test_record_sql_off
    @sampler.notice_first_scope_push Time.now.to_f

    NewRelic::Agent::TransactionState.get.record_sql = false

    @sampler.notice_sql("test", {}, 0)

    segment = @sampler.send(:builder).current_segment

    assert_nil segment[:sql]
  end

  def test_stack_trace__sql
    with_config(:'transaction_tracer.stack_trace_threshold' => 0) do
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_sql("test", {}, 1)
      segment = @sampler.send(:builder).current_segment

      assert segment[:sql]
      assert segment[:backtrace]
    end
  end

  def test_stack_trace__scope
    with_config(:'transaction_tracer.stack_trace_threshold' => 0) do
      t = Time.now
      @sampler.notice_first_scope_push t.to_f
      @sampler.notice_push_scope((t+1).to_f)

      segment = @sampler.send(:builder).current_segment
      assert segment[:backtrace]
    end
  end

  def test_nil_stacktrace
    with_config(:'transaction_tracer.stack_trace_threshold' => 2) do
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_sql("test", {}, 1)
      segment = @sampler.send(:builder).current_segment

      assert segment[:sql]
      assert_nil segment[:backtrace]
    end
  end

  def test_big_sql
    @sampler.notice_first_scope_push Time.now.to_f

    sql = "SADJKHASDHASD KAJSDH ASKDH ASKDHASDK JASHD KASJDH ASKDJHSAKDJHAS DKJHSADKJSAH DKJASHD SAKJDH SAKDJHS"

    len = 0
    while len <= 16384
      @sampler.notice_sql(sql, {}, 0)
      len += sql.length
    end

    segment = @sampler.send(:builder).current_segment

    sql = segment[:sql]

    assert sql.length <= 16384
  end

  def test_segment_obfuscated
    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_push_scope

    orig_sql = "SELECT * from Jim where id=66"

    @sampler.notice_sql(orig_sql, {}, 0)

    segment = @sampler.send(:builder).current_segment

    assert_equal orig_sql, segment[:sql]
    assert_equal "SELECT * from Jim where id=?", segment.obfuscated_sql
    @sampler.notice_pop_scope "foo"
  end

  def test_param_capture
    [true, false].each do |capture|
      with_config(:capture_params => capture) do
        tt = with_config(:'transaction_tracer.transaction_threshold' => 0.0) do
          @sampler.notice_first_scope_push Time.now.to_f
          @sampler.notice_transaction(nil, :param => 'hi')
          @sampler.notice_scope_empty(@txn)
          @sampler.harvest[0]
        end

        assert_equal (capture ? 1 : 0), tt.params[:request_params].length
      end
    end
  end

  def test_should_not_collect_segments_beyond_limit
    with_config(:'transaction_tracer.limit_segments' => 3) do
      run_sample_trace do
        @sampler.notice_push_scope
        @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'hallah'", {}, 0)
        @sampler.notice_push_scope
        @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'semolina'", {}, 0)
        @sampler.notice_pop_scope "a11"
        @sampler.notice_pop_scope "a1"
      end
      assert_equal 3, @sampler.last_sample.count_segments
    end
  end

  def test_renaming_current_segment_midflight
    @sampler.start_builder
    segment = @sampler.notice_push_scope
    segment.metric_name = 'External/www.google.com/Net::HTTP/GET'
    assert_nothing_raised do
      @sampler.notice_pop_scope( 'External/www.google.com/Net::HTTP/GET' )
    end
  end

  def test_adding_segment_parameters
    @sampler.start_builder
    @sampler.notice_push_scope
    @sampler.add_segment_parameters( :transaction_guid => '97612F92E6194080' )
    assert_equal '97612F92E6194080', @sampler.builder.current_segment[:transaction_guid]
  end

  def test_large_transaction_trace_harvest
    config = {
      :'transaction_tracer.enabled' => true,
      :'transaction_tracer.transaction_threshold' => 0,
      :'transaction_tracer.limit_segments' => 100
    }
    with_config(config) do
      run_long_sample_trace(110)

      samples = nil
      assert_nothing_raised do
        samples = @sampler.harvest
      end
      assert_equal(1, samples.size)

      # Verify that the TT stopped recording after 100 nodes
      assert_equal(100, samples.first.count_segments)
    end
  end

  def test_build_database_statement_uses_override_obfuscation_adapter_if_connection_config_is_nil
    with_config(:override_sql_obfuscation_adapter => 'GumbyDB') do
      config = nil
      sql = "SELECT * FROM \"horses\" WHERE \"name\" = 'pokey'"
      statement = @sampler.build_database_statement(sql, config, Proc.new {})
      assert_equal 'GumbyDB', statement.adapter
    end
  end

  def test_build_database_statement_uses_override_obfuscation_adapter_if_connection_config_adapter_is_mysql
    with_config(:override_sql_obfuscation_adapter => 'GumbyDB') do
      config = {:adapter => 'mysql'}
      sql = "SELECT * FROM \"horses\" WHERE \"name\" = 'pokey'"
      statement = @sampler.build_database_statement(sql, config, nil)
      assert_equal 'GumbyDB', statement.adapter
    end
  end

  class Dummy
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    def run(n)
      n.times do
        perform_action_with_newrelic_trace("smile") do
        end
      end
    end
  end

  # TODO: this test seems to be destabilizing CI in a way that I don't grok.
  def sadly_do_not_test_harvest_during_transaction_safety
    n = 3000
    harvester = Thread.new do
      n.times { @sampler.harvest }
    end

    assert_nothing_raised { Dummy.new.run(n) }

    harvester.join
  end

  private

  SAMPLE_DEFAULTS = {
    :threshold => 1.0,
    :force_persist => false,
    :transaction_name => nil
  }

  def sample_with(incoming_opts = {})
    opts = SAMPLE_DEFAULTS.dup
    opts.merge!(incoming_opts)

    sample = NewRelic::TransactionSample.new
    sample.threshold = opts[:threshold]
    sample.force_persist = opts[:force_persist]
    sample.transaction_name = opts[:transaction_name]
    sample.stubs(:duration).returns(opts[:duration])
    sample
  end

  def generate_samples(count, opts = {})
    (1..count).map do |millis|
      sample_with(opts.merge(:duration => (millis / 1000.0)))
    end
  end

  def with_active_xray_session(name)
    xray_session_id = 1234
    xray_session = NewRelic::Agent::Commands::XraySession.new({
      "x_ray_id" => xray_session_id,
      "key_transaction_name" => name,
      "run_profiler" => false
    })

    xray_session_collection = NewRelic::Agent.instance.agent_command_router.xray_session_collection
    xray_session_collection.send(:add_session, xray_session)
    @sampler.xray_sample_buffer.xray_session_collection = xray_session_collection

    yield
  ensure
    xray_session_collection.send(:remove_session_by_id, xray_session_id)
  end

  def run_long_sample_trace(n)
    @sampler.notice_transaction(nil, {})
    @sampler.notice_first_scope_push(Time.now.to_f)
    n.times do |i|
      @sampler.notice_push_scope
      yield if block_given?
      @sampler.notice_pop_scope "node#{i}"
    end
    @sampler.notice_scope_empty(@txn, Time.now.to_f)
  end

  def run_sample_trace(start = Time.now.to_f, stop = nil)
    @sampler.notice_transaction(nil, {})
    @sampler.notice_first_scope_push start
    @sampler.notice_push_scope
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", {}, 0)
    @sampler.notice_push_scope
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", {}, 0)
    yield if block_given?
    @sampler.notice_pop_scope "ab"
    @sampler.notice_push_scope
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", {}, 0)
    @sampler.notice_pop_scope "ac"
    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty(@txn, (stop || Time.now.to_f))
  end
end
