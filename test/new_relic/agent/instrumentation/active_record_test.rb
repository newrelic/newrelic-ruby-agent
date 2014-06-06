# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if defined?(::Rails)

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'active_record_fixtures'

class NewRelic::Agent::Instrumentation::NewActiveRecordInstrumentationTest < Minitest::Test
  def setup
    super
    NewRelic::Agent.manual_start
    ActiveRecord::Base.establish_connection unless ActiveRecord::Base.connection.active?
    ActiveRecordFixtures.setup
    NewRelic::Agent.instance.transaction_sampler.reset!
    NewRelic::Agent.instance.stats_engine.clear_stats
  end

  def teardown
    super
    NewRelic::Agent::TransactionState.tl_get.reset
    NewRelic::Agent.shutdown
  end

  def test_metrics_for_create
    in_web_transaction do
      ActiveRecordFixtures::Order.create(:name => 'bob')
    end

    if active_record_major_version >= 3
      assert_generic_rollup_metrics('insert')
    else
      assert_activerecord_metrics(ActiveRecordFixtures::Order, 'create')
    end
    assert_remote_service_metrics
  end

  def test_metrics_for_create_via_association
    in_web_transaction do
      order = ActiveRecordFixtures::Order.create(:name => 'bob')
      order.shipments.create
      order.shipments.to_a
    end

    assert_generic_rollup_metrics('insert')
    assert_remote_service_metrics
  end

  def test_metrics_for_find
    in_web_transaction do
      if active_record_major_version >= 4
        ActiveRecordFixtures::Order.where(:name => 'foo').load
      else
        ActiveRecordFixtures::Order.find_all_by_name('foo')
      end
    end

    assert_activerecord_metrics(ActiveRecordFixtures::Order, 'find')
    assert_remote_service_metrics
  end

  def test_metrics_for_find_by_id
    in_web_transaction do
      order = ActiveRecordFixtures::Order.create(:name => 'kathy')
      ActiveRecordFixtures::Order.find(order.id)
    end

    assert_activerecord_metrics(ActiveRecordFixtures::Order, 'find')
    assert_remote_service_metrics
  end

  def test_metrics_for_find_via_association
    in_web_transaction do
      order = ActiveRecordFixtures::Order.create(:name => 'bob')
      order.shipments.create
      order.shipments.to_a
    end

    assert_activerecord_metrics(ActiveRecordFixtures::Shipment, 'find')
    assert_remote_service_metrics
  end

  def test_metrics_for_find_all
    in_web_transaction do
      case
      when active_record_major_version >= 4
        ActiveRecordFixtures::Order.all.load
      when active_record_major_version >= 3
        ActiveRecordFixtures::Order.all
      else
        ActiveRecordFixtures::Order.find(:all)
      end
    end

    assert_activerecord_metrics(ActiveRecordFixtures::Order, 'find')
    assert_remote_service_metrics
  end

  def test_metrics_for_find_via_named_scope
    ActiveRecordFixtures::Order.class_eval do
      if NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("4")
        scope :jeffs, lambda { where(:name => 'Jeff') }
      elsif NewRelic::Control.instance.rails_version >= NewRelic::VersionNumber.new("3.1")
        scope :jeffs, :conditions => { :name => 'Jeff' }
      else
        named_scope :jeffs, :conditions => { :name => 'Jeff' }
      end
    end

    in_web_transaction do
      if active_record_major_version >= 4
        ActiveRecordFixtures::Order.jeffs.load
      else
        ActiveRecordFixtures::Order.jeffs.find(:all)
      end
    end

    assert_activerecord_metrics(ActiveRecordFixtures::Order, 'find')
    assert_remote_service_metrics
  end

  def test_metrics_for_exists
    in_web_transaction do
      ActiveRecordFixtures::Order.exists?(["name=?", "jeff"])
    end

    if active_record_major_version == 3 && [0,1].include?(active_record_minor_version)
      # Bugginess in Rails 3.0 and 3.1 doesn't let us get ActiveRecord/find
      assert_generic_rollup_metrics('select')
    else
      assert_activerecord_metrics(ActiveRecordFixtures::Order, 'find')
    end
    assert_remote_service_metrics
  end

  def test_metrics_for_update
    in_web_transaction do
      order = ActiveRecordFixtures::Order.create(:name => "wendy")
      order.name = 'walter'
      order.save
    end

    if active_record_major_version >= 3
      assert_generic_rollup_metrics('update')
    else
      assert_activerecord_metrics(ActiveRecordFixtures::Order, 'save')
    end
    assert_remote_service_metrics
  end

  def test_metrics_for_destroy
    in_web_transaction do
      order = ActiveRecordFixtures::Order.create("name" => "burt")
      order.destroy
    end

    if active_record_major_version >= 3
      assert_generic_rollup_metrics('delete')
    else
      assert_activerecord_metrics(ActiveRecordFixtures::Order, 'destroy')
    end
    assert_remote_service_metrics
  end

  def test_metrics_for_direct_sql_select
    in_web_transaction do
      conn = ActiveRecordFixtures::Order.connection
      conn.select_rows("SELECT * FROM #{ActiveRecordFixtures::Order.table_name}")
    end

    assert_generic_rollup_metrics('select')
    assert_remote_service_metrics
  end

  def test_metrics_for_direct_sql_other
    in_web_transaction do
      conn = ActiveRecordFixtures::Order.connection
      conn.execute("begin")
      conn.execute("commit")
    end

    assert_generic_rollup_metrics('other')
    assert_remote_service_metrics
  end

  def test_metrics_for_direct_sql_show
    if supports_show_tables?
      in_web_transaction do
        conn = ActiveRecordFixtures::Order.connection
        conn.execute("show tables")
      end

      assert_generic_rollup_metrics('show')
      assert_remote_service_metrics
    end
  end

  def test_still_records_metrics_in_error_cases
    # have the AR select throw an error
    ActiveRecordFixtures::Order.connection.stubs(:log_info).with do |sql, *|
      raise "Error" if sql =~ /select/
      true
    end

    in_web_transaction do
      begin
        ActiveRecordFixtures::Order.connection.select_rows "select * from #{ActiveRecordFixtures::Order.table_name}"
      rescue RuntimeError => e
        # catch only the error we raise above
        raise unless e.message == 'Error'
      end
    end

    assert_generic_rollup_metrics('select')
    assert_remote_service_metrics
  end

  def test_passes_through_errors
    begin
      ActiveRecordFixtures::Order.transaction do
        raise ActiveRecord::ActiveRecordError.new('preserve-me!')
      end
    rescue ActiveRecord::ActiveRecordError => e
      assert_equal 'preserve-me!', e.message
    end
  end

  def test_no_metrics_recorded_with_disable_all_tracing
    NewRelic::Agent.disable_all_tracing do
      in_web_transaction('bogosity') do
        ActiveRecordFixtures::Order.first
      end
    end
    assert_nil NewRelic::Agent.instance.transaction_sampler.last_sample
    assert_metrics_recorded_exclusive([])
  end

  def test_records_transaction_trace_nodes
    in_web_transaction do
      ActiveRecordFixtures::Order.first
    end
    sample = NewRelic::Agent.instance.transaction_sampler.last_sample
    segment = find_segment_with_name(sample, 'ActiveRecord/ActiveRecordFixtures::Order/find')

    assert_equal('ActiveRecord/ActiveRecordFixtures::Order/find', segment.metric_name)

    sql = segment.params[:sql]
    assert_match(/^SELECT /, sql)

    assert_equal(adapter.to_s, sql.adapter)
    refute_nil(sql.config)
    refute_nil(sql.explainer)
  end

  def test_gathers_explain_plans
    with_config(:'transaction_tracer.explain_threshold' => -0.1) do
      in_web_transaction do
        ActiveRecordFixtures::Order.first
      end

      sample = NewRelic::Agent.instance.transaction_sampler.last_sample
      sql_segment = find_segment_with_name(sample, 'ActiveRecord/ActiveRecordFixtures::Order/find')

      assert_match(/^SELECT /, sql_segment.params[:sql])

      sample.prepare_to_send!
      explanations = sql_segment.params[:explain_plan]
      if supports_explain_plans?
        refute_nil explanations, "No explains in segment: #{sql_segment}"
        assert_equal(2, explanations.size,
                     "No explains in segment: #{sql_segment}")
      end
    end
  end

  def test_records_metrics_on_background_transaction
    in_transaction('back it up') do
      ActiveRecordFixtures::Order.create(:name => 'bob')
    end

    assert_metrics_recorded(['Datastore/allOther'])
    assert_metrics_not_recorded(['ActiveRecord/all'])
  end

  def test_remote_service_metric_respects_dynamic_connection_config
    if supports_remote_service_metrics?
      q = "SELECT * FROM #{ActiveRecordFixtures::Shipment.table_name} LIMIT 1"
      ActiveRecordFixtures::Shipment.connection.execute(q)
      assert_remote_service_metrics

      config = ActiveRecordFixtures::Shipment.connection.instance_eval { @config }
      config[:host] = '127.0.0.1'
      ActiveRecordFixtures::Shipment.establish_connection(config)

      ActiveRecordFixtures::Shipment.connection.execute(q)
      assert_remote_service_metrics('127.0.0.1')

      config[:host] = 'localhost'
      ActiveRecordFixtures::Shipment.establish_connection(config)
    end
  end

  # helpers

  def rails_env
    Rails.env
  end

  def adapter
    adapter_string = ActiveRecordFixtures::Order.configurations[rails_env]['adapter']
    case adapter_string
    when /postgres/i then :postgres
    when /mysql/i    then :mysql
    when /sqlite/i   then :sqlite3
    else
      adapter_string.downcase.to_sym
    end
  end

  def supports_show_tables?
    [:mysql, :postgres].include?(adapter)
  end

  def supports_remote_service_metrics?
    [:mysql, :postgres].include?(adapter)
  end

  def supports_explain_plans?
    [:mysql, :postgres].include?(adapter)
  end

  def active_record_major_version
    if defined?(::ActiveRecord::VERSION::MAJOR)
      ::ActiveRecord::VERSION::MAJOR.to_i
    else
      2
    end
  end

  def active_record_minor_version
    if defined?(::ActiveRecord::VERSION::MINOR)
      ::ActiveRecord::VERSION::MINOR.to_i
    else
      1
    end
  end

  def active_record_version
    if defined?(::ActiveRecord::VERSION::MINOR)
      NewRelic::VersionNumber.new(::ActiveRecord::VERSION::STRING)
    else
      NewRelic::VersionNumber.new("2.1.0")  # Can't tell between 2.1 and 2.2. Meh.
    end
  end

  def assert_activerecord_metrics(model, operation)
    assert_metrics_recorded([
      "ActiveRecord/all",
      "ActiveRecord/#{operation}",
      "ActiveRecord/#{model}/#{operation}",
      "Datastore/all"
    ])
  end

  def assert_generic_rollup_metrics(operation)
    assert_metrics_recorded([
      "ActiveRecord/all",
      "Database/SQL/#{operation}",
      "Datastore/all"
    ])
  end

  def assert_remote_service_metrics(host='localhost')
    if supports_remote_service_metrics?
      assert_metrics_recorded([
        "RemoteService/sql/#{adapter}/#{host}"
      ])
    end
  end
end

else
  puts "Skipping tests in #{__FILE__} because Rails is unavailable"
end
