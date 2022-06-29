# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

SimpleCovHelper.command_name "test:multiverse[active_record]"
require_relative 'app/models/models'

class ActiveRecordInstrumentationTest < Minitest::Test
  include MultiverseHelpers
  setup_and_teardown_agent

  module VersionHelpers
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
        Gem::Version.new(::ActiveRecord::VERSION::STRING)
      else
        Gem::Version.new("2.1.0") # Can't tell between 2.1 and 2.2. Meh.
      end
    end
  end

  include VersionHelpers
  extend VersionHelpers

  def after_setup
    super
    NewRelic::Agent.drop_buffered_data
  end

  def test_metrics_for_calculation_methods
    in_web_transaction do
      Order.count
      Order.average(:id)
      Order.minimum(:id)
      Order.maximum(:id)
      Order.sum(:id)
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Order, 'select', :call_count => 5)
    else
      assert_generic_rollup_metrics('select')
    end
  end

  if active_record_version >= Gem::Version.new('3.2.0')
    def test_metrics_for_pluck
      in_web_transaction do
        Order.pluck(:id)
      end

      assert_activerecord_metrics(Order, 'select')
    end
  end

  if active_record_version >= Gem::Version.new('4.0.0')
    def test_metrics_for_ids
      in_web_transaction do
        Order.ids
      end

      assert_activerecord_metrics(Order, 'select')
    end
  end

  def test_metrics_for_create
    in_web_transaction do
      Order.create(:name => 'bob')
    end

    assert_activerecord_metrics(Order, 'create')
  end

  def test_metrics_for_create_via_association
    in_web_transaction do
      order = Order.create(:name => 'bob')
      order.shipments.create
      order.shipments.to_a
    end

    assert_activerecord_metrics(Order, 'create')
  end

  def test_metrics_for_find
    in_web_transaction do
      if active_record_major_version >= 4
        Order.where(:name => 'foo').load
      else
        Order.find_all_by_name('foo')
      end
    end

    assert_activerecord_metrics(Order, 'find')
  end

  def test_metrics_for_find_via_association
    in_web_transaction do
      order = Order.create(:name => 'bob')
      order.shipments.create
      order.shipments.to_a
    end

    assert_activerecord_metrics(Shipment, 'find')
  end

  def test_metrics_for_find_all
    in_web_transaction do
      case
      when active_record_major_version >= 4
        Order.all.load
      when active_record_major_version >= 3
        Order.all
      else
        Order.find(:all)
      end
    end

    assert_activerecord_metrics(Order, 'find')
  end

  def test_metrics_for_find_via_named_scope
    major_version = active_record_major_version
    minor_version = active_record_minor_version
    Order.class_eval do
      if major_version >= 4
        scope :jeffs, lambda { where(:name => 'Jeff') }
      elsif major_version == 3 && minor_version >= 1
        scope :jeffs, :conditions => {:name => 'Jeff'}
      else
        named_scope :jeffs, :conditions => {:name => 'Jeff'}
      end
    end

    in_web_transaction do
      if active_record_major_version >= 4
        Order.jeffs.load
      else
        Order.jeffs.find(:all)
      end
    end

    assert_activerecord_metrics(Order, 'find')
  end

  def test_metrics_for_exists
    in_web_transaction do
      Order.exists?(["name=?", "jeff"])
    end

    if active_record_major_version == 3 && [0, 1].include?(active_record_minor_version)
      # Bugginess in Rails 3.0 and 3.1 doesn't let us get ActiveRecord/find
      assert_generic_rollup_metrics('select')
    else
      assert_activerecord_metrics(Order, 'find')
    end
  end

  def test_metrics_for_update_all
    order1, order2 = nil

    in_web_transaction do
      order1 = Order.create(:name => 'foo')
      order2 = Order.create(:name => 'foo')
      Order.update_all(:name => 'zing')
    end

    assert_activerecord_metrics(Order, 'update')

    assert_equal('zing', order1.reload.name)
    assert_equal('zing', order2.reload.name)
  end

  def test_metrics_for_delete_all
    in_web_transaction do
      Order.create(:name => 'foo')
      Order.create(:name => 'foo')
      Order.delete_all
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Order, 'delete')
    else
      assert_generic_rollup_metrics('delete')
    end
  end

  def test_metrics_for_relation_delete
    in_web_transaction do
      order = Order.create(:name => "lava")
      Order.delete(order.id)
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Order, 'delete')
    else
      assert_generic_rollup_metrics('delete')
    end
  end

  # delete and touch did not exist in AR 2.2
  if active_record_version >= Gem::Version.new('3.0.0')
    def test_metrics_for_delete
      in_web_transaction do
        order = Order.create("name" => "burt")
        order.delete
      end

      assert_activerecord_metrics(Order, 'delete')
    end

    def test_metrics_for_touch
      in_web_transaction do
        order = Order.create("name" => "wendy")
        order.touch
      end

      assert_activerecord_metrics(Order, 'update')
    end
  end

  def test_metrics_for_relation_update
    in_web_transaction do
      order = Order.create(:name => 'foo')
      Order.update(order.id, :name => 'qux')
    end

    assert_activerecord_metrics(Order, 'update')
  end

  def test_create_via_association_equal
    in_web_transaction do
      u = User.create(:name => 'thom yorke')
      groups = [
        Group.new(:name => 'radiohead'),
        Group.new(:name => 'atoms for peace')
      ]
      u.groups = groups
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Group, 'create')
    else
      assert_generic_rollup_metrics('insert')
    end
  end

  # Can be Mysql2::Error or ActiveRecord::RecordNotUnique
  # depending on gem versions in play
  def mysql_not_unique_error_class
    /Mysql2\:\:Error|ActiveRecord\:\:RecordNotUnique|ActiveRecord\:\:JDBCError/
  end

  def test_noticed_error_at_segment_and_txn_when_violating_unique_contraints
    expected_error_class = mysql_not_unique_error_class
    txn = nil
    begin
      in_web_transaction do |web_txn|
        txn = web_txn
        u = User.create(:name => 'thom yorke')
        u2 = User.create(u.attributes)
      end
    rescue StandardError => e
      # NOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_error txn, /create|insert/i, expected_error_class, /duplicate entry/i
    assert_transaction_noticed_error txn, expected_error_class
  end

  def test_noticed_error_only_at_segment_when_violating_unique_contraints
    expected_error_class = mysql_not_unique_error_class
    txn = nil
    in_web_transaction do |web_txn|
      begin
        txn = web_txn
        u = User.create(:name => 'thom yorke')
        u2 = User.create(u.attributes)
      rescue StandardError => e
        # NOP -- allowing ONLY span to notice error
      end
    end

    assert_segment_noticed_error txn, /create|insert/i, expected_error_class, /duplicate entry/i
    refute_transaction_noticed_error txn, expected_error_class
  end

  def test_create_via_association_shovel
    in_web_transaction do
      u = User.create(:name => 'thom yorke')
      u.groups << Group.new(:name => 'radiohead')
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Group, 'create')
    else
      assert_generic_rollup_metrics('insert')
    end
  end

  def test_create_via_association_create
    in_web_transaction do
      u = User.create(:name => 'thom yorke')
      u.groups.create(:name => 'radiohead')
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Group, 'create')
    else
      assert_generic_rollup_metrics('insert')
    end
  end

  def test_create_via_association_create_bang
    in_web_transaction do
      u = User.create(:name => 'thom yorke')
      u.groups.create!(:name => 'radiohead')
    end

    if active_record_major_version >= 3
      assert_activerecord_metrics(Group, 'create')
    else
      assert_generic_rollup_metrics('insert')
    end
  end

  def test_destroy_via_dependent_destroy
    in_web_transaction do
      u = User.create(:name => 'robert')
      u.aliases << Alias.new
      u.destroy
    end

    assert_activerecord_metrics(User, 'delete')
    assert_activerecord_metrics(Alias, 'delete')
  end

  # update & update! didn't become public until 4.0
  if active_record_version >= Gem::Version.new('4.0.0')
    def test_metrics_for_update
      in_web_transaction do
        order = Order.create(:name => "wendy")
        order.update(:name => 'walter')
      end

      assert_activerecord_metrics(Order, 'update')
    end

    def test_metrics_for_update_bang
      in_web_transaction do
        order = Order.create(:name => "wendy")
        order.update!(:name => 'walter')
      end

      assert_activerecord_metrics(Order, 'update')
    end
  end

  def test_metrics_for_update_attribute
    in_web_transaction do
      order = Order.create(:name => "wendy")
      order.update_attribute(:name, 'walter')
    end

    assert_activerecord_metrics(Order, 'update')
  end

  def test_metrics_for_save
    in_web_transaction do
      order = Order.create(:name => "wendy")
      order.name = 'walter'
      order.save
    end

    assert_activerecord_metrics(Order, 'update')
  end

  def test_metrics_for_save_bang
    in_web_transaction do
      order = Order.create(:name => "wendy")
      order.name = 'walter'
      order.save!
    end

    assert_activerecord_metrics(Order, 'update')
  end

  def test_nested_metrics_dont_get_model_name
    in_web_transaction do
      order = Order.create(:name => "wendy")
      order.name = 'walter'
      order.save!
    end

    assert_metrics_recorded(["Datastore/operation/Memcached/get"])
    refute_metrics_match(/Memcached.*Order/)
  end

  def test_metrics_for_destroy
    in_web_transaction do
      order = Order.create("name" => "burt")
      order.destroy
    end

    assert_activerecord_metrics(Order, 'delete')
  end

  def test_metrics_for_direct_sql_select
    in_web_transaction do
      conn = Order.connection
      conn.select_rows("SELECT * FROM #{Order.table_name}")
    end

    assert_generic_rollup_metrics('select')
  end

  def test_metrics_for_direct_sql_other
    in_web_transaction do
      conn = Order.connection
      conn.execute("begin")
      conn.execute("commit")
    end

    assert_generic_rollup_metrics('other')
  end

  def test_metrics_for_direct_sql_show
    if supports_show_tables?
      in_web_transaction do
        conn = Order.connection
        conn.execute("show tables")
      end

      assert_generic_rollup_metrics('show')
    end
  end

  def test_still_records_metrics_in_error_cases
    # Let's trigger an active record SQL StatemntInvalid error
    assert_raises ::ActiveRecord::StatementInvalid do
      in_web_transaction do
        Order.connection.select_rows "select * from askdjfhkajsdhflkjh"
      end
    end

    assert_generic_rollup_metrics('select')
  end

  def test_passes_through_errors
    to_raise = ActiveRecord::ActiveRecordError.new('preserve-me!')
    actually_raised = assert_raises ActiveRecord::ActiveRecordError do
      Order.transaction do
        raise to_raise
      end
    end

    assert_same to_raise, actually_raised
  end

  def test_only_supportability_metrics_recorded_with_disable_all_tracing
    NewRelic::Agent.disable_all_tracing do
      in_web_transaction('bogosity') do
        Order.first
      end
    end
    refute last_transaction_trace
    assert_metrics_recorded_exclusive([
      "Supportability/API/disable_all_tracing",
      "Supportability/API/drop_buffered_data"
    ])
  end

  def test_records_transaction_trace_nodes
    in_web_transaction do
      Order.first
    end
    sample = last_transaction_trace
    metric = "Datastore/statement/#{current_product}/Order/find"
    node = find_node_with_name(sample, metric)
    assert_equal(metric, node.metric_name)

    statement = node.params[:sql]
    assert_match(/^SELECT /, statement.sql)

    assert_match(statement.adapter.to_s, adapter.to_s)
    refute_nil(statement.config)
    refute_nil(statement.explainer)
  end

  def test_gathers_explain_plans
    with_config(:'transaction_tracer.explain_threshold' => -0.1) do
      in_web_transaction do
        Order.first
      end

      sample = last_transaction_trace
      metric = "Datastore/statement/#{current_product}/Order/find"
      sql_node = find_node_with_name(sample, metric)

      assert_match(/^SELECT /, sql_node.params[:sql].sql)

      sample.prepare_to_send!
      explanations = sql_node.params[:explain_plan]
      if supports_explain_plans?
        refute_nil explanations, "No explains in node: #{sql_node}"
        assert_equal(2, explanations.size,
          "No explains in node: #{sql_node}")
      end
    end
  end

  def test_sql_samplers_get_proper_metrics
    with_config(:'transaction_tracer.explain_threshold' => -0.1) do
      in_web_transaction do
        Order.first
      end

      metric = "Datastore/statement/#{current_product}/Order/find"
      refute_nil find_sql_trace(metric)
    end
  end

  def test_records_metrics_on_background_transaction
    in_transaction('back it up') do
      Order.create(:name => 'bob')
    end

    assert_metrics_recorded(['Datastore/all', 'Datastore/allOther'])
    assert_metrics_not_recorded(['Datastore/allWeb'])
  end

  def test_cached_calls_are_not_recorded_with_find
    in_web_transaction do
      order = Order.create(:name => 'Oberon')
      Order.connection.cache do
        Order.find(order.id)
        Order.find(order.id)
        Order.find(order.id)
      end
    end

    assert_activerecord_metrics(Order, 'find', :call_count => 1)
  end

  def test_cached_calls_are_not_recorded_with_select_all
    # If this is the first create, ActiveRecord needs to warm up,
    # send some SQL SELECTS, etc.
    in_web_transaction do
      Order.create(:name => 'Oberon')
    end
    NewRelic::Agent.drop_buffered_data

    # the actual test is here
    query = "SELECT * FROM #{Order.table_name} WHERE name = 'Oberon'"
    in_web_transaction do
      Order.connection.cache do
        Order.connection.select_all(query)
        Order.connection.select_all(query)
        Order.connection.select_all(query)
      end
    end

    assert_metrics_recorded(
      {"Datastore/operation/#{current_product}/select" => {:call_count => 1}}
    )
  end

  def test_with_database_metric_name
    in_web_transaction do
      Order.create(:name => "eely")
      NewRelic::Agent.with_database_metric_name('Eel', 'squirm') do
        Order.connection.select_rows("SELECT id FROM #{Order.table_name}")
      end
    end

    assert_metrics_recorded(
      {
        "Datastore/statement/#{current_product}/Eel/squirm" => {:call_count => 1},
        "Datastore/operation/#{current_product}/squirm" => {:call_count => 1}
      }
    )
  end

  ## helpers

  def adapter
    adapter_string = Order.configurations[RAILS_ENV]['adapter']
    adapter_string.downcase.to_sym
  end

  def supports_show_tables?
    [:mysql, :postgres].include?(adapter)
  end

  def supports_explain_plans?
    [:mysql, :postgres].include?(adapter)
  end

  def current_product
    NewRelic::Agent::Instrumentation::ActiveRecordHelper::PRODUCT_NAMES[adapter.to_s]
  end

  def operation_for(op)
    is_5_2 = active_record_version >= Gem::Version.new('5.2.0.beta1')

    if op == 'create'
      active_record_major_version >= 3 && !is_5_2 ? 'insert' : 'create'
    elsif op == 'delete'
      active_record_major_version >= 3 && !is_5_2 ? 'delete' : 'destroy'
    else
      op
    end
  end

  def assert_activerecord_metrics(model, operation, stats = {})
    operation = operation_for(operation) if ['create', 'delete'].include?(operation)

    assert_metrics_recorded({
      "Datastore/statement/#{current_product}/#{model}/#{operation}" => stats,
      "Datastore/operation/#{current_product}/#{operation}" => {},
      "Datastore/allWeb" => {},
      "Datastore/all" => {}
    })
  end

  def assert_generic_rollup_metrics(operation)
    assert_metrics_recorded([
      "Datastore/operation/#{current_product}/#{operation}",
      "Datastore/allWeb",
      "Datastore/all"
    ])
  end
end
