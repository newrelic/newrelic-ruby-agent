require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class NewRelic::Agent::Instrumentation::ActiveRecordInstrumentationTest < Test::Unit::TestCase
  require 'active_record_fixtures'
  include NewRelic::Agent::Instrumentation::ControllerInstrumentation

  # the db adapter library the tests are running under (e.g. sqlite3)
  def adapter
    if ActiveRecord::Base.respond_to?(:connection_config)
      ActiveRecord::Base.connection_config[:adapter]
    else
      # old versions of rails are usually tested against mysql
      'mysql'
    end
  end

  def setup
    super
    NewRelic::Agent.manual_start
    ActiveRecordFixtures.setup
    NewRelic::Agent.instance.transaction_sampler.reset!
    NewRelic::Agent.instance.stats_engine.clear_stats
  rescue => e
    puts e
    puts e.backtrace.join("\n")
  end

  def teardown
    super
    NewRelic::Agent.shutdown
  end

  #####################################################################
  # Note: If these tests are failing, most likely the problem is that #
  # the active record instrumentation is not loading for whichever    #
  # version of rails you're testing at the moment.                    #
  #####################################################################

  def test_agent_setup
    assert NewRelic::Agent.instance.class == NewRelic::Agent::Agent
  end

  def test_finder
    ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
    find_metric = "ActiveRecord/ActiveRecordFixtures::Order/find"

    assert_calls_metrics(find_metric) do
      all_finder(ActiveRecordFixtures::Order)
      check_metric_count(find_metric, 1)
      if NewRelic::Control.instance.rails_version >= "4"
        ActiveRecordFixtures::Order.where(:name =>  "jeff").load
      else
        ActiveRecordFixtures::Order.find_all_by_name "jeff"
      end
      check_metric_count(find_metric, 2)
    end
  end

  def test_exists
    return if NewRelic::Control.instance.rails_version < "2.3.4" ||
      NewRelic::Control.instance.rails_version >= "3.0.7"

    ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'

    find_metric = "ActiveRecord/ActiveRecordFixtures::Order/find"    

    assert_calls_metrics(find_metric) do
      ActiveRecordFixtures::Order.exists?(["name=?", 'jeff'])
      check_metric_count(find_metric, 1)
    end
  end

  # multiple duplicate find calls should only cause metric trigger on the first
  # call.  the others are ignored.
  def test_query_cache
    # Not sure why we get a transaction error with sqlite
    return if isSqlite?

    find_metric = "ActiveRecord/ActiveRecordFixtures::Order/find"
    ActiveRecordFixtures::Order.cache do
      m = ActiveRecordFixtures::Order.create :id => 1, :name => 'jeff'
      assert_calls_metrics(find_metric) do
        all_finder(ActiveRecordFixtures::Order)
      end

      check_metric_count(find_metric, 1)

      assert_calls_metrics(find_metric) do
        10.times { ActiveRecordFixtures::Order.find m.id }
      end
      check_metric_count(find_metric, 2)
    end
  end

  def test_metric_names_jruby
    # fails due to a bug in rails 3 - log does not provide the correct
    # transaction type - it returns 'SQL' instead of 'Foo Create', for example.
    return if rails3? || !defined?(JRuby)
    expected = %W[
      ActiveRecord/all
      ActiveRecord/find
      ActiveRecord/ActiveRecordFixtures::Order/find
      Database/SQL/insert
      RemoteService/sql/#{adapter}/localhost
    ]

    if NewRelic::Control.instance.rails_version < '2.1.0'
      expected += %W[ActiveRecord/save ActiveRecord/ActiveRecordFixtures::Order/save]
    end

    assert_calls_metrics(*expected) do
      m = ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
      m = ActiveRecordFixtures::Order.find(m.id)
      m.id = 999
      m.save!
    end
    metrics = NewRelic::Agent.instance.stats_engine.metrics

    compare_metrics expected, metrics
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/find", 1)
    # zero because jruby uses a different mysql adapter
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/create", 0)
  end

  def test_metric_names_sqlite
    # fails due to a bug in rails 3 - log does not provide the correct
    # transaction type - it returns 'SQL' instead of 'Foo Create', for example.
    return if rails3? || !isSqlite? || defined?(JRuby)

    expected = %W[
      ActiveRecord/all
      ActiveRecord/find
      ActiveRecord/ActiveRecordFixtures::Order/find
      ActiveRecord/create
      ActiveRecord/ActiveRecordFixtures::Order/create]

    if NewRelic::Control.instance.rails_version < '2.1.0'
      expected += %W[ActiveRecord/save ActiveRecord/ActiveRecordFixtures::Order/save]
    end

    assert_calls_metrics(*expected) do
      m = ActiveRecordFixtures::Order.create :id => 0, :name => 'jeff'
      m = ActiveRecordFixtures::Order.find(m.id)
      m.id = 999
      m.save!
    end
    metrics = NewRelic::Agent.instance.stats_engine.metrics

    compare_metrics expected, metrics
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/find", 1)
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/create", 1)
  end

  def test_metric_names_standard
    # fails due to a bug in rails 3 - log does not provide the correct
    # transaction type - it returns 'SQL' instead of 'Foo Create', for example.
    return if defined?(JRuby) || isSqlite?

    expected = %W[
      ActiveRecord/all
      ActiveRecord/find
      ActiveRecord/create
      ActiveRecord/ActiveRecordFixtures::Order/find
      ActiveRecord/ActiveRecordFixtures::Order/create
      Database/SQL/other
      RemoteService/sql/#{adapter}/localhost]

    if NewRelic::Control.instance.rails_version < '2.1.0'
      expected += ['ActiveRecord/save',
                   'ActiveRecord/ActiveRecordFixtures::Order/save']
    elsif NewRelic::Control.instance.rails_version >= '3.0.0'
      expected << 'Database/SQL/insert'
    end

    assert_calls_metrics(*expected) do
      m = ActiveRecordFixtures::Order.create :id => 1, :name => 'donkey'
      m = ActiveRecordFixtures::Order.find(m.id)
      m.id = 999
      m.save!
    end

    metrics = NewRelic::Agent.instance.stats_engine.metrics

    compare_metrics expected, metrics
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/find", 1)
    if NewRelic::Control.instance.rails_version < '3.0.0'
      check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/create", 1)
    else
      check_metric_count("Database/SQL/insert", 1)
    end
  end

  def test_join_metrics_jruby
    return unless defined?(JRuby)
    return if rails3?

    expected_metrics = %W[
    ActiveRecord/all
    ActiveRecord/destroy
    ActiveRecord/ActiveRecordFixtures::Order/destroy
    Database/SQL/insert
    Database/SQL/delete
    Database/SQL/show
    ActiveRecord/find
    ActiveRecord/ActiveRecordFixtures::Order/find
    ActiveRecord/ActiveRecordFixtures::Shipment/find
    RemoteService/sql/#{adapter}/localhost
    ]

    assert_calls_metrics(*expected_metrics) do
      m = ActiveRecordFixtures::Order.create :name => 'jeff'
      m = ActiveRecordFixtures::Order.find(m.id)
      s = m.shipments.create
      m.shipments.to_a
      m.destroy
    end

    metrics = NewRelic::Agent.instance.stats_engine.metrics

    compare_metrics expected_metrics, metrics

    check_metric_time('ActiveRecord/all', NewRelic::Agent.get_stats("ActiveRecord/all").total_exclusive_time, 0)
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/find", 1)
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Shipment/find", 1)
    check_metric_count("Database/SQL/insert", 3)
    check_metric_count("Database/SQL/delete", 1)
  end

  def test_join_metrics_sqlite
    return if (defined?(Rails) && Rails.respond_to?(:version) && Rails.version.to_i == 3)
    return if defined?(JRuby)
    return unless isSqlite?

    expected_metrics = %W[
    ActiveRecord/all
    ActiveRecord/destroy
    ActiveRecord/ActiveRecordFixtures::Order/destroy
    Database/SQL/insert
    Database/SQL/delete
    ActiveRecord/find
    ActiveRecord/ActiveRecordFixtures::Order/find
    ActiveRecord/ActiveRecordFixtures::Shipment/find
    ActiveRecord/create
    ActiveRecord/ActiveRecordFixtures::Shipment/create
    ActiveRecord/ActiveRecordFixtures::Order/create
    ]

    assert_calls_metrics(*expected_metrics) do
      m = ActiveRecordFixtures::Order.create :name => 'jeff'
      m = ActiveRecordFixtures::Order.find(m.id)
      s = m.shipments.create
      m.shipments.to_a
      m.destroy
    end

    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics expected_metrics, metrics
    if !(defined?(RUBY_DESCRIPTION) && RUBY_DESCRIPTION =~ /Enterprise Edition/)
      check_metric_time('ActiveRecord/all', NewRelic::Agent.get_stats("ActiveRecord/all").total_exclusive_time, 0)
    end
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/find", 1)
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Shipment/find", 1)
    check_metric_count("Database/SQL/insert", 3)
    check_metric_count("Database/SQL/delete", 1)
  end

  def test_join_metrics_standard
    return if (defined?(Rails) && Rails.respond_to?(:version) && Rails.version.to_i >= 3)
    return if defined?(JRuby) || isSqlite?

    expected_metrics = %W[
    ActiveRecord/all
    RemoteService/sql/#{adapter}/localhost
    ActiveRecord/destroy
    ActiveRecord/ActiveRecordFixtures::Order/destroy
    Database/SQL/insert
    Database/SQL/delete
    ActiveRecord/find
    ActiveRecord/ActiveRecordFixtures::Order/find
    ActiveRecord/ActiveRecordFixtures::Shipment/find
    Database/SQL/other
    Database/SQL/show
    ActiveRecord/create
    ActiveRecord/ActiveRecordFixtures::Shipment/create
    ActiveRecord/ActiveRecordFixtures::Order/create
    ]

    assert_calls_metrics(*expected_metrics) do
      m = ActiveRecordFixtures::Order.create :name => 'jeff'
      m = ActiveRecordFixtures::Order.find(m.id)
      s = m.shipments.create
      m.shipments.to_a
      m.destroy
    end

    metrics = NewRelic::Agent.instance.stats_engine.metrics

    compare_metrics expected_metrics, metrics
    if !(defined?(RUBY_DESCRIPTION) && RUBY_DESCRIPTION =~ /Enterprise Edition/)
      check_metric_time('ActiveRecord/all', NewRelic::Agent.get_stats("ActiveRecord/all").total_exclusive_time, 0)
    end
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Order/find", 1)
    check_metric_count("ActiveRecord/ActiveRecordFixtures::Shipment/find", 1)
    check_metric_count("Database/SQL/insert", 1)
    check_metric_count("Database/SQL/delete", 1)
  end

  def test_direct_sql
    assert_nil NewRelic::Agent::Instrumentation::MetricFrame.current
    assert_nil NewRelic::Agent.instance.stats_engine.scope_name
    assert_equal 0, NewRelic::Agent.instance.stats_engine.metrics.size, NewRelic::Agent.instance.stats_engine.metrics.inspect

    expected_metrics = %W[
    ActiveRecord/all
    Database/SQL/select
    RemoteService/sql/#{adapter}/localhost
    ]

    assert_calls_unscoped_metrics(*expected_metrics) do
      ActiveRecordFixtures::Order.connection.select_rows "select * from #{ActiveRecordFixtures::Order.table_name}"
    end

    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics(expected_metrics, metrics)

    check_unscoped_metric_count('Database/SQL/select', 1)

  end

  def test_other_sql
    expected_metrics = %W[
    ActiveRecord/all
    Database/SQL/other
    RemoteService/sql/#{adapter}/localhost
    ]
    assert_calls_unscoped_metrics(*expected_metrics) do
      ActiveRecordFixtures::Order.connection.execute "begin"
    end

    metrics = NewRelic::Agent.instance.stats_engine.metrics

    compare_metrics expected_metrics, metrics
    check_unscoped_metric_count('Database/SQL/other', 1)
  end

  def test_show_sql
    return if isSqlite?
    return if isPostgres?

    expected_metrics = %W[ActiveRecord/all Database/SQL/show RemoteService/sql/#{adapter}/localhost]

    assert_calls_metrics(*expected_metrics) do
      ActiveRecordFixtures::Order.connection.execute "show tables"
    end
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics expected_metrics, metrics
    check_unscoped_metric_count('Database/SQL/show', 1)
  end

  def test_blocked_instrumentation
    ActiveRecordFixtures::Order.add_delay
    NewRelic::Agent.disable_all_tracing do
      perform_action_with_newrelic_trace :name => 'bogosity' do
        all_finder(ActiveRecordFixtures::Order)
      end
    end
    assert_nil NewRelic::Agent.instance.transaction_sampler.last_sample
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics [], metrics
  end
  
  def test_run_explains
    perform_action_with_newrelic_trace :name => 'bogosity' do
      ActiveRecordFixtures::Order.add_delay
      all_finder(ActiveRecordFixtures::Order)
    end

    # that's a mouthful. perhaps we should ponder our API.
    segment = NewRelic::Agent.instance.transaction_sampler.last_sample \
      .root_segment.called_segments[0].called_segments[0].called_segments[0]
    regex = /^SELECT (["`]?#{ActiveRecordFixtures::Order.table_name}["`]?.)?\* FROM ["`]?#{ActiveRecordFixtures::Order.table_name}["`]?$/
    assert_match regex, segment.params[:sql].strip
  end
  
  def test_prepare_to_send
    perform_action_with_newrelic_trace :name => 'bogosity' do
      ActiveRecordFixtures::Order.add_delay
      all_finder(ActiveRecordFixtures::Order)
    end
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_not_nil sample

    includes_gc = false
    sample.each_segment {|s| includes_gc ||= s.metric_name =~ /GC/ }

    assert_equal (includes_gc ? 4 : 3), sample.count_segments, sample.to_s

    sql_segment = sample.root_segment.called_segments.first.called_segments.first.called_segments.first
    assert_not_nil sql_segment, sample.to_s
    assert_match /^SELECT /, sql_segment.params[:sql]
    assert sql_segment.duration > 0.0, "Segment duration must be greater than zero."
    sample = sample.prepare_to_send(:record_sql => :raw, :explain_sql => 0.0)
    sql_segment = sample.root_segment.called_segments.first.called_segments.first.called_segments.first
    assert_match /^SELECT /, sql_segment.params[:sql]
    explanations = sql_segment.params[:explain_plan]
    if isMysql? || isPostgres?
      assert_not_nil explanations, "No explains in segment: #{sql_segment}"
      assert_equal(2, explanations.size,
                   "No explains in segment: #{sql_segment}")
    end
  end

  def test_transaction_mysql
    return unless isMysql? && !defined?(JRuby)
    ActiveRecordFixtures.setup
    sample = NewRelic::Agent.instance.transaction_sampler.reset!
    perform_action_with_newrelic_trace :name => 'bogosity' do
      ActiveRecordFixtures::Order.add_delay
      all_finder(ActiveRecordFixtures::Order)
    end

    sample = NewRelic::Agent.instance.transaction_sampler.last_sample

    sample = sample.prepare_to_send(:record_sql => :obfuscated, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first.called_segments.first
    explanation = segment.params[:explain_plan]
    assert_not_nil explanation, "No explains in segment: #{segment}"
    assert_equal 2, explanation.size,"No explains in segment: #{segment}"

    assert_equal 10, explanation[0].size
    ['id', 'select_type', 'table'].each do |c|
      assert explanation[0].include?(c)
    end
    ['1', 'SIMPLE', ActiveRecordFixtures::Order.table_name].each do |c|
      assert explanation[1][0].include?(c)
    end

    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 1, s.call_count
  end

  def test_transaction_postgres
    return unless isPostgres?
    # note that our current test builds do not use postgres, this is
    # here strictly for troubleshooting, not CI builds
    sample = NewRelic::Agent.instance.transaction_sampler.reset!
    perform_action_with_newrelic_trace :name => 'bogosity' do
      ActiveRecordFixtures::Order.add_delay
      all_finder(ActiveRecordFixtures::Order)
    end

    sample = NewRelic::Agent.instance.transaction_sampler.last_sample

    sample = sample.prepare_to_send(:record_sql => :obfuscated, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first.called_segments.first
    explanations = segment.params[:explain_plan]

    assert_not_nil explanations, "No explains in segment: #{segment}"
    assert_equal 1, explanations.size,"No explains in segment: #{segment}"
    assert_equal 1, explanations.first.size

    assert_equal("Explain Plan", explanations[0][0])
    assert_match /Seq Scan on test_data/, explanations[0][1].join(";")

    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 1, s.call_count
  end

  def test_transaction_other
    return if isMysql? || isPostgres?
    sample = NewRelic::Agent.instance.transaction_sampler.reset!
    perform_action_with_newrelic_trace :name => 'bogosity' do
      ActiveRecordFixtures::Order.add_delay
      all_finder(ActiveRecordFixtures::Order)
    end

    sample = NewRelic::Agent.instance.transaction_sampler.last_sample

    sample = sample.prepare_to_send(:record_sql => :obfuscated, :explain_sql => 0.0)
    segment = sample.root_segment.called_segments.first.called_segments.first.called_segments.first

    s = NewRelic::Agent.get_stats("ActiveRecord/ActiveRecordFixtures::Order/find")
    assert_equal 1, s.call_count
  end

  # These are only valid for rails 2.1 and later
  if NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("2.1.0")
    ActiveRecordFixtures::Order.class_eval do
      if NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("4")
        scope :jeffs, lambda { where(:name => 'Jeff') }
      elsif NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("3.1")
        scope :jeffs, :conditions => { :name => 'Jeff' }
      else
        named_scope :jeffs, :conditions => { :name => 'Jeff' }
      end      
    end
    def test_named_scope
      ActiveRecordFixtures::Order.create :name => 'Jeff'

      find_metric = "ActiveRecord/ActiveRecordFixtures::Order/find"

      check_metric_count(find_metric, 0)
      assert_calls_metrics(find_metric) do
        if NewRelic::Control.instance.rails_version >= "4"
          x = ActiveRecordFixtures::Order.jeffs.load
        else
          x = ActiveRecordFixtures::Order.jeffs.find(:all)
        end
      end
      check_metric_count(find_metric, 1)
    end
  end

  # This is to make sure the all metric is recorded for exceptional cases
  def test_error_handling
    # have the AR select throw an error
    ActiveRecordFixtures::Order.connection.stubs(:log_info).with do | sql, x, y |
      raise "Error" if sql =~ /select/
      true
    end

    expected_metrics = %W[ActiveRecord/all Database/SQL/select RemoteService/sql/#{adapter}/localhost]

    assert_calls_metrics(*expected_metrics) do
      begin
        ActiveRecordFixtures::Order.connection.select_rows "select * from #{ActiveRecordFixtures::Order.table_name}"
      rescue RuntimeError => e
        # catch only the error we raise above
        raise unless e.message == 'Error'
      end
    end
    metrics = NewRelic::Agent.instance.stats_engine.metrics
    compare_metrics expected_metrics, metrics
    check_metric_count('Database/SQL/select', 1)
    check_metric_count('ActiveRecord/all', 1)
    check_metric_count("RemoteService/sql/#{adapter}/localhost", 1)
  end

  def test_rescue_handling
    # Not sure why we get a transaction error with sqlite
    return if isSqlite?

    begin
      ActiveRecordFixtures::Order.transaction do
        raise ActiveRecord::ActiveRecordError.new('preserve-me!')
      end
    rescue ActiveRecord::ActiveRecordError => e
      assert_equal 'preserve-me!', e.message
    end
  end
  
  def test_remote_service_metric_respects_dynamic_connection_config
    return unless isMysql?

#     puts NewRelic::Agent::Database.config.inspect
    
    ActiveRecordFixtures::Shipment.connection.execute('SHOW TABLES');
    assert(NewRelic::Agent.get_stats("RemoteService/sql/#{adapter}/localhost").call_count != 0)

    config = ActiveRecordFixtures::Shipment.connection.instance_eval { @config }    
    config[:host] = '127.0.0.1'
    connection = ActiveRecordFixtures::Shipment.establish_connection(config)
    
#     puts ActiveRecord::Base.connection.instance_eval { @config }.inspect
#     puts NewRelic::Agent::Database.config.inspect
    
    ActiveRecordFixtures::Shipment.connection.execute('SHOW TABLES');
    assert(NewRelic::Agent.get_stats("RemoteService/sql/#{adapter}/127.0.0.1").call_count != 0)

    config[:host] = 'localhost'
    ActiveRecordFixtures::Shipment.establish_connection(config)

#     raise NewRelic::Agent.instance.stats_engine.inspect
  end
  
  private

  def rails3?
    (defined?(Rails) && Rails.respond_to?(:version) && Rails.version.to_i >= 3)
  end

  def rails_env
    rails3? ? ::Rails.env : RAILS_ENV
  end

  def isPostgres?
    ActiveRecordFixtures::Order.configurations[rails_env]['adapter'] =~ /postgres/i
  end
  def isMysql?
    ActiveRecordFixtures::Order.connection.class.name =~ /mysql/i
  end

  def isSqlite?
    ActiveRecord::Base.configurations[rails_env]['adapter'] =~ /sqlite/i
  end

  def all_finder(relation)
    if NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("4.0")
      relation.all.load
    elsif NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("3.0")
      relation.all
    else
      relation.find(:all)
    end
  end
end
