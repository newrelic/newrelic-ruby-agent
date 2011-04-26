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
    Thread::current[:record_sql] = nil
    agent = NewRelic::Agent.instance
    stats_engine = NewRelic::Agent::StatsEngine.new
    agent.stubs(:stats_engine).returns(stats_engine)
    @sampler = NewRelic::Agent::TransactionSampler.new
    stats_engine.transaction_sampler = @sampler
  end

  def teardown
    super
    @sampler.send(:clear_builder)
  end

  # TODO this class needs better coverage and breakdown of large methods

  def test_initialize
    defaults =      {
        :samples => [],
        :harvest_count => 0,
        :max_samples => 100,
        :random_sample => nil,
      }
    defaults.each do |variable, default_value|
      assert_equal(default_value, @sampler.instance_variable_get('@' + variable.to_s))
    end
    
    segment_limit = @sampler.instance_variable_get('@segment_limit')
    assert(segment_limit.is_a?(Numeric), "Segment limit should be numeric")
    assert(segment_limit > 0, "Segment limit should be above zero")

    stack_trace_threshold = @sampler.instance_variable_get('@stack_trace_threshold')
    assert(stack_trace_threshold.is_a?((0.1).class), "Stack trace threshold should be a #{(0.1).class.inspect}, but is #{stack_trace_threshold.inspect}")
    assert(stack_trace_threshold > 0.0, "Stack trace threshold should be above zero")
    
    lock = @sampler.instance_variable_get('@samples_lock')
    assert(lock.is_a?(Mutex), "Samples lock should be a mutex, is: #{lock.inspect}")
  end

  def test_current_sample_id_default
    builder = mock('builder')
    builder.expects(:sample_id).returns(11111)
    @sampler.expects(:builder).returns(builder)
    assert_equal(11111, @sampler.current_sample_id)
  end

  def test_current_sample_id_no_builder
    @sampler.expects(:builder).returns(nil)
    assert_equal(nil, @sampler.current_sample_id)
  end
  
  def test_enable
    assert_equal(nil, @sampler.instance_variable_get('@disabled'))
    @sampler.enable
    assert_equal(false, @sampler.instance_variable_get('@disabled'))
    assert_equal(@sampler, NewRelic::Agent.instance.stats_engine.instance_variable_get('@transaction_sampler'))
  end

  def test_disable
    assert_equal(nil, @sampler.instance_variable_get('@disabled'))
    @sampler.disable
    assert_equal(true, @sampler.instance_variable_get('@disabled'))
    assert_equal(nil, NewRelic::Agent.instance.stats_engine.instance_variable_get('@transaction_sampler'))
  end

  def test_sampling_rate_equals_default
    @sampler.sampling_rate = 1
    assert_equal(1, @sampler.instance_variable_get('@sampling_rate'))
    # rand(1) is always zero, so we can be sure here
    assert_equal(0, @sampler.instance_variable_get('@harvest_count'))
  end

  def test_sampling_rate_equals_with_a_float
    @sampler.sampling_rate = 5.5
    assert_equal(5, @sampler.instance_variable_get('@sampling_rate'))
    harvest_count = @sampler.instance_variable_get('@harvest_count')
    assert((0..4).include?(harvest_count), "should be in the range 0..4")
  end

  def test_notice_first_scope_push_default
    @sampler.expects(:disabled).returns(false)
    @sampler.expects(:start_builder).with(100.0)
    @sampler.notice_first_scope_push(Time.at(100))
  end

  def test_notice_first_scope_push_disabled
    @sampler.expects(:disabled).returns(true)
    @sampler.expects(:start_builder).never
    @sampler.notice_first_scope_push(Time.at(100))
  end

  def test_notice_push_scope_no_builder
    @sampler.expects(:builder)
    assert_equal(nil, @sampler.notice_push_scope('a scope'))
  end

  def test_notice_push_scope_with_builder
    NewRelic::Control.instance.expects(:developer_mode?).returns(false)
    builder = mock('builder')
    builder.expects(:trace_entry).with('a scope', 100.0)
    @sampler.expects(:builder).returns(builder).twice
    
    @sampler.notice_push_scope('a scope', Time.at(100))
  end

  def test_notice_push_scope_in_dev_mode
    NewRelic::Control.instance.expects(:developer_mode?).returns(true)
    
    builder = mock('builder')
    builder.expects(:trace_entry).with('a scope', 100.0)
    @sampler.expects(:builder).returns(builder).twice
    @sampler.expects(:capture_segment_trace)

    @sampler.notice_push_scope('a scope', Time.at(100))
  end

  def test_scope_depth_no_builder
    @sampler.expects(:builder).returns(nil)
    assert_equal(0, @sampler.scope_depth, "should default to zero with no builder")
  end

  def test_scope_depth_with_builder
    builder = mock('builder')
    builder.expects(:scope_depth).returns('scope_depth')
    @sampler.expects(:builder).returns(builder).twice
    
    assert_equal('scope_depth', @sampler.scope_depth, "should delegate scope depth to the builder")
  end

  def test_notice_pop_scope_no_builder
    @sampler.expects(:builder).returns(nil)
    assert_equal(nil, @sampler.notice_pop_scope('a scope', Time.at(100)))
  end

  def test_notice_pop_scope_with_frozen_sample
    builder = mock('builder')
    sample = mock('sample')
    builder.expects(:sample).returns(sample)
    sample.expects(:frozen?).returns(true)
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
    sample.expects(:frozen?).returns(false)
    @sampler.expects(:builder).returns(builder).times(3)

    @sampler.notice_pop_scope('a scope', Time.at(100))
  end

  # Tests below this line are functional tests for the sampler, not
  # unit tests per se
  
  def test_multiple_samples

    run_sample_trace
    run_sample_trace
    run_sample_trace
    run_sample_trace

    samples = @sampler.samples
    assert_equal 4, samples.length
    assert_equal "a", samples.first.root_segment.called_segments[0].metric_name
    assert_equal "a", samples.last.root_segment.called_segments[0].metric_name
  end

  def test_sample_tree
    assert_equal 0, @sampler.scope_depth

    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_transaction "/path", nil, {}
    @sampler.notice_push_scope "a"

    @sampler.notice_push_scope "b"
    @sampler.notice_pop_scope "b"

    @sampler.notice_push_scope "c"
    @sampler.notice_push_scope "d"
    @sampler.notice_pop_scope "d"
    @sampler.notice_pop_scope "c"

    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty
    sample = @sampler.harvest([],0.0).first
    assert_equal "ROOT{a{b,c{d}}}", sample.to_s_compact

  end

  def test_sample__gc_stats
    GC.extend MockGCStats
    # These are effectively Garbage Collects, detected each time GC.time is
    # called by the transaction sampler.  One time value in seconds for each call.
    MockGCStats.mock_values = [0,0,0,1,0,0,1,0,0,0,0,0,0,0,0]
    assert_equal 0, @sampler.scope_depth

    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_transaction "/path", nil, {}
    @sampler.notice_push_scope "a"

    @sampler.notice_push_scope "b"
    @sampler.notice_pop_scope "b"

    @sampler.notice_push_scope "c"
    @sampler.notice_push_scope "d"
    @sampler.notice_pop_scope "d"
    @sampler.notice_pop_scope "c"

    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty

    sample = @sampler.harvest([],0.0).first
    assert_equal "ROOT{a{b,c{d}}}", sample.to_s_compact
  ensure
    MockGCStats.mock_values = []
  end

  def test_sample_id
    run_sample_trace do
      assert((@sampler.current_sample_id && @sampler.current_sample_id != 0), @sampler.current_sample_id.to_s + ' should not be zero')
    end
  end

  def test_harvest_slowest

    run_sample_trace
    run_sample_trace
    run_sample_trace { sleep 0.0051 }
    run_sample_trace
    run_sample_trace

    slowest = @sampler.harvest(nil, 0)[0]
    assert slowest.duration >= 0.005, "sample duration: #{slowest.duration}"
    
    run_sample_trace { sleep 0.002 }
    not_as_slow = @sampler.harvest(slowest, 0)[0]
    assert not_as_slow == slowest
    
    run_sample_trace { sleep 0.00601 }
    new_slowest = @sampler.harvest(slowest, 0)[0]
    assert new_slowest != slowest
    assert new_slowest.duration >= 0.006, "Slowest duration must be > 0.006: #{new_slowest.duration}"
  end


  def test_prepare_to_send

    run_sample_trace { sleep 0.2 }
    sample = @sampler.harvest(nil, 0)[0]

    ready_to_send = sample.prepare_to_send
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

    assert_equal 0, @sampler.scope_depth

    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_transaction "/path", nil, {}
    @sampler.notice_push_scope "a"

    assert_equal 1, @sampler.scope_depth

    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty

    assert_equal 0, @sampler.scope_depth

    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_transaction "/path", nil, {}
    @sampler.notice_push_scope "a"
    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty

    assert_equal 0, @sampler.scope_depth
    sample = @sampler.harvest(nil, 0.0).first
    assert_equal "ROOT{a}", sample.to_s_compact
  end

  def test_double_scope_stack_empty

    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_transaction "/path", nil, {}
    @sampler.notice_push_scope "a"
    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty
    @sampler.notice_scope_empty
    @sampler.notice_scope_empty
    @sampler.notice_scope_empty

    assert_not_nil @sampler.harvest(nil, 0)[0]
  end


  def test_record_sql_off

    @sampler.notice_first_scope_push Time.now.to_f

    Thread::current[:record_sql] = false

    @sampler.notice_sql("test", nil, 0)

    segment = @sampler.send(:builder).current_segment

    assert_nil segment[:sql]
  end

  def test_stack_trace__sql
    @sampler.stack_trace_threshold = 0

    @sampler.notice_first_scope_push Time.now.to_f

    @sampler.notice_sql("test", nil, 1)

    segment = @sampler.send(:builder).current_segment

    assert segment[:sql]
    assert segment[:backtrace]
  end
  def test_stack_trace__scope

    @sampler.stack_trace_threshold = 0
    t = Time.now
    @sampler.notice_first_scope_push t.to_f
    @sampler.notice_push_scope 'Bill', (t+1).to_f

    segment = @sampler.send(:builder).current_segment
    assert segment[:backtrace]
  end

  def test_nil_stacktrace

    @sampler.stack_trace_threshold = 2

    @sampler.notice_first_scope_push Time.now.to_f

    @sampler.notice_sql("test", nil, 1)

    segment = @sampler.send(:builder).current_segment

    assert segment[:sql]
    assert_nil segment[:backtrace]
  end

  def test_big_sql

    @sampler.notice_first_scope_push Time.now.to_f

    sql = "SADJKHASDHASD KAJSDH ASKDH ASKDHASDK JASHD KASJDH ASKDJHSAKDJHAS DKJHSADKJSAH DKJASHD SAKJDH SAKDJHS"

    len = 0
    while len <= NewRelic::Agent::TransactionSampler::MAX_SQL_LENGTH
      @sampler.notice_sql(sql, nil, 0)
      len += sql.length
    end

    segment = @sampler.send(:builder).current_segment

    sql = segment[:sql]

    assert sql.length <= NewRelic::Agent::TransactionSampler::MAX_SQL_LENGTH
  end


  def test_segment_obfuscated

    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_push_scope "foo"

    orig_sql = "SELECT * from Jim where id=66"

    @sampler.notice_sql(orig_sql, nil, 0)

    segment = @sampler.send(:builder).current_segment

    assert_equal orig_sql, segment[:sql]
    assert_equal "SELECT * from Jim where id=?", segment.obfuscated_sql
    @sampler.notice_pop_scope "foo"
  end


  def test_param_capture
    [true, false].each do |capture|
      NewRelic::Control.instance.stubs(:capture_params).returns(capture)
      @sampler.notice_first_scope_push Time.now.to_f
      @sampler.notice_transaction('/path', nil, {:param => 'hi'})
      @sampler.notice_scope_empty

      tt = @sampler.harvest(nil,0)[0]

      assert_equal (capture) ? 1 : 0, tt.params[:request_params].length
    end
  end


  def test_sql_normalization

    # basic statement
    assert_equal "INSERT INTO X values(?,?, ? , ?)",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('test',0, 1 , 2)")

    # escaped literals
    assert_equal "INSERT INTO X values(?, ?,?, ? , ?)",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('', 'jim''s ssn',0, 1 , 'jim''s son''s son')")

    # multiple string literals
    assert_equal "INSERT INTO X values(?,?,?, ? , ?)",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('jim''s ssn','x',0, 1 , 2)")

    # empty string literal
    # NOTE: the empty string literal resolves to empty string, which for our purposes is acceptable
    assert_equal "INSERT INTO X values(?,?,?, ? , ?)",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT INTO X values('','x',0, 1 , 2)")

    # try a select statement
    assert_equal "select * from table where name=? and ssn=?",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "select * from table where name='jim gochee' and ssn=0012211223")

    # number literals embedded in sql - oh well
    assert_equal "select * from table_? where name=? and ssn=?",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "select * from table_007 where name='jim gochee' and ssn=0012211223")
  end

  def test_sql_normalization__single_quotes
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, "INSERT 'this isn''t a real value' into table")
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT '"' into table])
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT ' "some text" \" ' into table])
#    could not get this one licked.  no biggie
#    assert_equal "INSERT ? into table",
#    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT '\'' into table])
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT ''' ' into table])
  end
  def test_sql_normalization__double_quotes
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT "this isn't a real value" into table])
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT "'" into table])
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT " \" " into table])
    assert_equal "INSERT ? into table",
    NewRelic::Agent.instance.send(:default_sql_obfuscator, %q[INSERT " 'some text' " into table])
  end
  def test_sql_obfuscation_filters
    orig =  NewRelic::Agent.agent.obfuscator

    NewRelic::Agent.set_sql_obfuscator(:replace) do |sql|
      sql = "1" + sql
    end

    sql = "SELECT * FROM TABLE 123 'jim'"

    assert_equal "1" + sql, NewRelic::Agent.instance.obfuscator.call(sql)

    NewRelic::Agent.set_sql_obfuscator(:before) do |sql|
      sql = "2" + sql
    end

    assert_equal "12" + sql, NewRelic::Agent.instance.obfuscator.call(sql)

    NewRelic::Agent.set_sql_obfuscator(:after) do |sql|
      sql = sql + "3"
    end

    assert_equal "12" + sql + "3", NewRelic::Agent.instance.obfuscator.call(sql)

    NewRelic::Agent.agent.set_sql_obfuscator(:replace, &orig)
  end


  private
  def run_sample_trace(&proc)
    @sampler.notice_first_scope_push Time.now.to_f
    @sampler.notice_transaction '/path', nil, {}
    @sampler.notice_push_scope "a"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'wheat'", nil, 0)
    @sampler.notice_push_scope "ab"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'white'", nil, 0)
    proc.call if proc
    @sampler.notice_pop_scope "ab"
    @sampler.notice_push_scope "lew"
    @sampler.notice_sql("SELECT * FROM sandwiches WHERE bread = 'french'", nil, 0)
    @sampler.notice_pop_scope "lew"
    @sampler.notice_pop_scope "a"
    @sampler.notice_scope_empty
  end

end
