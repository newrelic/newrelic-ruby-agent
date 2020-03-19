# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module MongoOperationTests
  def test_records_metrics_for_insert
    in_transaction do
      @collection.insert(@tribble)
    end

    metrics = build_test_metrics(:insert)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @collection.find(@tribble).to_a
    end

    metrics = build_test_metrics(:find)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_one
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @collection.find_one
    end

    metrics = build_test_metrics(:findOne)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_remove
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @collection.remove(@tribble).to_a
    end

    metrics = build_test_metrics(:remove)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_save
    in_transaction do
      @collection.save(@tribble)
    end

    metrics = build_test_metrics(:save)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_save_does_not_record_insert
    in_transaction do
      @collection.save(@tribble)
    end

    metrics = build_test_metrics(:save)
    metrics_with_attributes(metrics)

    assert_metrics_not_recorded(['Datastore/operation/MongoDB/insert'])
  end

  def test_records_metrics_for_update
    updated = @tribble.dup
    updated['name'] = 'codemonkey'

    in_transaction do
      @collection.update(@tribble, updated)
    end

    metrics = build_test_metrics(:update)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_distinct
    in_transaction do
      @collection.distinct('name')
    end

    metrics = build_test_metrics(:distinct)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_count
    in_transaction do
      @collection.count
    end

    metrics = build_test_metrics(:count)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_group
    begin
      in_transaction do
        @collection.group({:key => "name",
                           :initial => {:count => 0},
                           :reduce => "function(k,v) { v.count += 1; }" })
      end
    rescue Mongo::OperationFailure
      # We get occasional group failures, but should still record metrics
    end

    metrics = build_test_metrics(:group)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_and_modify
    updated = @tribble.dup
    updated['name'] = 'codemonkey'

    in_transaction do
      @collection.find_and_modify(:query => @tribble, :update => updated)
    end

    metrics = build_test_metrics(:findAndModify)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_find_and_remove
    in_transaction do
      @collection.find_and_modify(:query => @tribble, :remove =>true)
    end

    metrics = build_test_metrics(:findAndRemove)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_create_index
    in_transaction do
      @collection.create_index([[unique_field_name, Mongo::ASCENDING]])
    end

    # The createIndexes command was added to the mongo server in version 2.6.
    # As of version 1.10.0 of the Ruby driver, the driver will attempt to
    # service a create_index call by first issuing a createIndexes command to
    # the server. If the server replies that it doesn't know this command, the
    # driver will re-issue an equivalent createIndex command.
    #
    # So, if we're running with version 1.10.0 or later of the driver, we expect
    # some additional metrics to be recorded.
    client_is_1_10_or_later = NewRelic::Agent::Datastores::Mongo.is_version_1_10_or_later?

    create_index_metrics   = metrics_with_attributes(build_test_metrics(:createIndex))
    create_indexes_metrics = metrics_with_attributes(build_test_metrics(:createIndexes))

    if !client_is_1_10_or_later
      metrics = create_index_metrics
    elsif client_is_1_10_or_later && !server_is_2_6_or_later?
      metrics = create_index_metrics.merge(create_indexes_metrics)
      metrics['Datastore/MongoDB/allWeb'][:call_count] += 1
      metrics['Datastore/MongoDB/all'][:call_count]    += 1
      metrics['Datastore/allWeb'][:call_count] += 1
      metrics['Datastore/all'][:call_count]    += 1
    elsif client_is_1_10_or_later && server_is_2_6_or_later?
      metrics = create_indexes_metrics
    end

    assert_metrics_recorded(metrics)
  end

  def test_records_metrics_for_ensure_index
    in_transaction do
      @collection.ensure_index([[unique_field_name, Mongo::ASCENDING]])
    end

    metrics = build_test_metrics(:ensureIndex)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_ensure_index_with_symbol
    in_transaction do
      @collection.ensure_index(unique_field_name.to_sym)
    end

    metrics = build_test_metrics(:ensureIndex)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_ensure_index_with_string
    in_transaction do
      @collection.ensure_index(unique_field_name)
    end

    metrics = build_test_metrics(:ensureIndex)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_ensure_index_does_not_record_insert
    in_transaction do
      @collection.ensure_index([[unique_field_name, Mongo::ASCENDING]])
    end

    assert_metrics_not_recorded(['Datastore/operation/MongoDB/insert'])
  end

  def test_ensure_index_does_call_ensure_index
    options = [[unique_field_name, Mongo::ASCENDING]]
    in_transaction do
      @collection.expects(:ensure_index_without_new_relic_trace).with(options, any_parameters).once
      @collection.ensure_index(options)
    end
  end

  def test_records_metrics_for_drop_index
    name =  @collection.create_index([[unique_field_name, Mongo::ASCENDING]])
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @collection.drop_index(name)
    end

    metrics = build_test_metrics(:dropIndex)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_drop_indexes
    @collection.create_index([[unique_field_name, Mongo::ASCENDING]])
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @collection.drop_indexes
    end

    metrics = build_test_metrics(:dropIndexes)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_records_metrics_for_reindex
    @collection.create_index([[unique_field_name, Mongo::ASCENDING]])
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @database.command({ :reIndex => @collection_name })
    end

    metrics = build_test_metrics(:reIndex)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_rename_collection
    ensure_collection_exists

    in_transaction do
      @collection.rename("renamed_#{@collection_name}")
    end

    metrics = build_test_metrics(:renameCollection)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  ensure
    @collection_name = "renamed_#{@collection_name}"
  end

  def test_rename_collection_via_db
    ensure_collection_exists

    in_transaction do
      @database.rename_collection(@collection_name, "renamed_#{@collection_name}")
    end

    metrics = build_test_metrics(:renameCollection)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  ensure
    @collection_name = "renamed_#{@collection_name}"
  end

  def test_drop_collection
    ensure_collection_exists

    in_transaction do
      @database.drop_collection(@collection_name)
    end

    metrics = build_test_metrics(:drop)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_collstats
    @collection.insert(@tribble)
    NewRelic::Agent.drop_buffered_data

    in_transaction do
      @collection.stats
    end

    metrics = build_test_metrics(:collstats)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_web_scoped_metrics
    in_web_transaction("webby") do
      @collection.insert(@tribble)
    end

    metric = statement_metric(:insert)
    assert_metrics_recorded([[metric, "webby"]])
  end

  def test_background_scoped_metrics
    in_background_transaction("backed-up") do
      @collection.insert(@tribble)
    end

    metric = statement_metric(:insert)
    assert_metrics_recorded([[metric, "backed-up"]])
  end

  def test_notices_nosql
    node = nil

    in_transaction do
      @collection.insert(@tribble)
    end

    node = find_last_transaction_node

    expected = {
      :database   => @database_name,
      :collection => @collection_name,
      :operation  => :insert
    }

    result = node.params[:statement]
    assert_equal expected, result
  end

  def test_noticed_nosql_includes_operation
    node = nil

    in_transaction do
      @collection.insert(@tribble)
    end

    node = find_last_transaction_node
    query = node.params[:statement]

    assert_equal :insert, query[:operation]
  end

  def test_noticed_nosql_includes_update_operation
    node = nil

    in_transaction do
      updated = @tribble.dup
      updated['name'] = 't-rex'
      @collection.update(@tribble, updated)
    end

    node = find_last_transaction_node
    query = node.params[:statement]

    assert_equal :update, query[:operation]
  end

  def test_noticed_nosql_includes_save_operation
    node = nil

    in_transaction do
      @collection.save(@tribble)
    end

    node = find_last_transaction_node
    query = node.params[:statement]
    assert_equal :save, query[:operation]
  end

  def test_noticed_nosql_includes_ensure_index_operation
    node = nil

    in_transaction do
      @collection.ensure_index([[unique_field_name, Mongo::ASCENDING]])
    end

    node = find_last_transaction_node
    assert_ensure_index_in_transaction_node(node)
  end

  def test_noticed_nosql_includes_ensure_index_operation_with_symbol
    node = nil

    in_transaction do
      @collection.ensure_index(unique_field_name.to_sym)
    end

    node = find_last_transaction_node
    assert_ensure_index_in_transaction_node(node)
  end

  def test_noticed_nosql_includes_ensure_index_operation_with_string
    node = nil

    in_transaction do
      @collection.ensure_index(unique_field_name)
    end

    node = find_last_transaction_node
    assert_ensure_index_in_transaction_node(node)
  end

  def assert_ensure_index_in_transaction_node(node)
    query = node.params[:statement]
    result = query[:operation]

    assert_equal :ensureIndex, result
  end

  def test_noticed_nosql_does_not_contain_documents
    node = nil

    in_transaction do
      @collection.insert({'name' => 'soterios johnson'})
    end

    node = find_last_transaction_node
    statement = node.params[:statement]

    refute statement.keys.include?(:documents), "Noticed NoSQL should not include documents: #{statement}"
  end

  def test_noticed_nosql_does_not_contain_selector_values
    @collection.insert({'password' => '$ecret'})
    node = nil

    in_transaction do
      @collection.remove({'password' => '$ecret'})
    end

    node = find_last_transaction_node
    statement = node.params[:statement]

    refute statement.inspect.include?('$secret')
    assert_equal '?', statement[:selector]['password']
  end

  def test_web_requests_record_all_web_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    in_web_transaction do
      @collection.insert(@tribble)
    end

    metrics = build_test_metrics(:insert)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_web_requests_do_not_record_all_other_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)

    in_web_transaction do
      @collection.insert(@tribble)
    end

    assert_metrics_not_recorded(['Datastore/allOther'])
  end

  def test_other_requests_record_all_other_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)

    in_background_transaction do
      @collection.insert(@tribble)
    end

    metrics = build_test_metrics(:insert)
    expected = metrics_with_attributes(metrics)

    assert_metrics_recorded(expected)
  end

  def test_other_requests_do_not_record_all_web_metric
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)

    in_background_transaction do
      @collection.insert(@tribble)
    end

    assert_metrics_not_recorded(['Datastore/allWeb'])
  end

  def unique_field_name
    "field#{fake_guid(10)}"
  end

  def ensure_collection_exists
    @collection.insert(:junk => "data")
    NewRelic::Agent.drop_buffered_data
  end

  def server_is_2_6_or_later?
    client = @collection.db.respond_to?(:client) && @collection.db.client
    return false unless client
    client.respond_to?(:max_wire_version) && client.max_wire_version >= 2
  end

  def statement_metric(action)
    metrics = build_test_metrics(action)
    metrics.select { |m| m.start_with?("Datastore/statement") }.first
  end
end
