# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class OpenSearchInstrumentationTest < Minitest::Test
  def setup
    @client = OpenSearch::Client.new(
      host: "https://localhost:#{port}",
      user: 'admin',
      password: 'sn33ZeGesundheit!',
      transport_options: {ssl: {verify: false}}
    )

    @client.cluster.health
    @client.index(index: 'my-index', id: 1, body: {title: 'Test'})
    @client.indices.refresh(index: 'my-index')
  end

  def teardown
    @client = nil
    @segment = nil
  end

  def search
    txn = in_transaction do
      @client.search(index: 'my-index', body: {query: {match: {title: 'test'}}})
    end

    @segment = txn.segments[1]
  end

  def test_datastore_segment_created
    search

    assert_equal NewRelic::Agent::Transaction::DatastoreSegment, @segment.class
  end

  def test_segment_opensearch_product
    search

    assert_equal 'OpenSearch', @segment.product
  end

  def test_segment_operation_is_search_when_search_method_called
    search

    assert_equal 'search', @segment.operation
  end

  def test_segment_operation_is_index_when_index_method_called
    txn = in_transaction do
      @client.index(index: 'my-index', id: 1, body: {title: 'Test'})
    end

    segment = txn.segments[1]

    assert_equal 'index', segment.operation
  end

  def test_segment_operation_returns_OPERATION_when_api_not_called
    # stubbing the constant to make sure it takes over when there's a nil value for nr_operation
    NewRelic::Agent::Instrumentation::Elasticsearch.stub_const(:OPERATION, 'subdued-excitement') do
      txn = in_transaction { @client.perform_request('GET', '/_search', {q: 'hi'}) }
      segment = txn.segments[1]

      assert_equal NewRelic::Agent::Instrumentation::OpenSearch::OPERATION, segment.operation
    end
  end

  def test_segment_host
    search

    assert_equal Socket.gethostname, @segment.host
  end

  def test_segment_port_path_or_id_uses_port
    search

    assert_equal port.to_s, @segment.port_path_or_id
  end

  def test_segment_database_name
    search

    assert_equal 'docker-cluster', @segment.database_name
  end

  def test_cluster_name_doesnt_try_again_if_defined_but_nil
    original = @client.instance_variable_get(:@transport).instance_variable_get(:@nr_cluster_name)
    @client.instance_variable_get(:@transport).instance_variable_set(:@nr_cluster_name, nil)
    search
    @client.instance_variable_get(:@transport).instance_variable_set(:@nr_cluster_name, original)

    assert_nil @segment.database_name
  end

  def test_nosql_statement_recorded_params_obfuscated
    with_config(:'opensearch.obfuscate_queries' => true) do
      txn = in_transaction do
        # passing q: title sets the perform_request method's params argument to
        # {q: 'title'} and leaves the body argument nil
        @client.search(index: 'my-index', q: '?')
      end
      segment = txn.segments[1]
      obfuscated_query = {q: '?'}

      assert_equal obfuscated_query, segment.nosql_statement
    end
  end

  def test_nosql_statement_recorded_params_not_obfuscated
    with_config(:'opensearch.obfuscate_queries' => false) do
      txn = in_transaction do
        # passing `q: title` sets the perform_request method's params argument
        # to {q: 'title'} and leaves the body argument nil
        @client.search(index: 'my-index', q: 'title')
      end
      segment = txn.segments[1]
      not_obfuscated_query = {q: 'title'}

      assert_equal not_obfuscated_query, segment.nosql_statement
    end
  end

  def test_nosql_statement_recorded_body_obfuscated
    with_config(:'opensearch.obfuscate_queries' => true) do
      txn = in_transaction do
        query = {query: {match: {title: 'test'}}}
        @client.search(index: 'my-index', body: query)
      end
      segment = txn.segments[1]
      obfuscated_query = {query: {match: {title: '?'}}}

      assert_equal obfuscated_query, segment.nosql_statement
    end
  end

  def test_nosql_statement_recorded_body_not_obfuscated
    with_config(:'opensearch.obfuscate_queries' => false) do
      query = {query: {match: {title: 'test'}}}
      txn = in_transaction do
        @client.search(index: 'my-index', body: query)
      end
      segment = txn.segments[1]

      assert_equal query, segment.nosql_statement
    end
  end

  def test_statement_captured
    with_config(:'opensearch.capture_queries' => true) do
      query = {query: {match: {title: 'test'}}}
      ob_query = {query: {match: {title: '?'}}}
      txn = in_transaction do
        @client.search(index: 'my-index', body: query)
      end
      segment = txn.segments[1]

      assert_equal ob_query, segment.nosql_statement
    end
  end

  def test_statement_not_captured
    with_config(:'opensearch.capture_queries' => false) do
      query = {query: {match: {title: 'test'}}}
      txn = in_transaction do
        @client.search(index: 'my-index', body: query)
      end
      segment = txn.segments[1]

      assert_nil segment.nosql_statement
    end
  end

  def test_segment_error_captured_if_raised
    txn = nil
    begin
      in_transaction('opensearch') do |elastic_txn|
        txn = elastic_txn
        simulate_transport_error
      end
    rescue StandardError => e
      # NOOP -- allowing span and transaction to notice error
    end

    expected_error_class_name = OpenSearch::Transport::Transport::Error.name

    assert_segment_noticed_error txn, /opensearch$/, expected_error_class_name, /Error/i
    assert_transaction_noticed_error txn, expected_error_class_name
  end

  private

  def simulate_transport_error
    @client.stub(:search, raise(transport_error_class.new)) do
      @client.search(index: 'my-index', q: 'title')
    end
  end

  def port
    9200 # remove once we decide on a port
  end
end
