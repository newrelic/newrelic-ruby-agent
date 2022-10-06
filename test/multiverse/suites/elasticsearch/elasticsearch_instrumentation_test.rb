# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'elasticsearch'

class ElasticsearchInstrumentationTest < Minitest::Test
  def setup
    # Keeping the log off prevents noisy test output
    @client = ::Elasticsearch::Client.new(log: false)
    # Ensure the client is running before the tests start
    @client.cluster.health
    # TODO: Update this to use constants, perhaps a hash?
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

  def test_segment_elasticsearch_product
    search
    assert_equal NewRelic::Agent::Instrumentation::Elasticsearch::PRODUCT_NAME, @segment.product
  end

  def test_segment_operation
    search
    assert_equal NewRelic::Agent::Instrumentation::Elasticsearch::OPERATION, @segment.operation
  end

  def test_segment_host
    skip('need to figure out how to stub this')
    search
    assert_equal 'host', @segment.host
  end

  def test_segment_port_path_or_id_uses_path_if_present
    search
    assert_equal 'my-index/_search', @segment.port_path_or_id
  end

  def test_segment_port_path_or_id_uses_port_if_path_absent
    skip('need to figure out how to stub this')
    search
    assert_equal 'port', @segment.port_path_or_id
  end

  def test_segment_database_name
    search
    assert_equal 'cluster_name', @segment.database_name
  end

  def test_nosql_statement_recorded_params_obfuscated
    with_config(:'elasticsearch.obfuscate_queries' => true) do
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
    with_config(:'elasticsearch.obfuscate_queries' => false) do
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
    with_config(:'elasticsearch.obfuscate_queries' => true) do
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
    with_config(:'elasticsearch.obfuscate_queries' => false) do
      query = {query: {match: {title: 'test'}}}
      txn = in_transaction do
        @client.search(index: 'my-index', body: query)
      end
      segment = txn.segments[1]
      assert_equal query, segment.nosql_statement
    end
  end

  def test_statement_captured
    with_config(:'elasticsearch.capture_queries' => true) do
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
    with_config(:'elasticsearch.capture_queries' => false) do
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
    transport_error_class = ::Elastic::Transport::Transport::Error
    begin
      in_transaction('elastic') do |elastic_txn|
        txn = elastic_txn
        simulate_transport_error
      end
    rescue StandardError => e
      # NOOP -- allowing span and transaction to notice error
    end

    assert_segment_noticed_error txn, /elastic$/, transport_error_class.name, /Error/i
    assert_transaction_noticed_error txn, transport_error_class.name
  end

  private

  def simulate_transport_error
    @client.stub(:search, raise(::Elastic::Transport::Transport::Error.new)) do
      @client.search(index: 'my-index', q: 'title')
    end
  def port
    if ::Gem::Version.create(Elasticsearch::VERSION) < ::Gem::Version.create("8.0.0")
      9200 # 9200 for elasticsearch 7
    else
      9250 # 9250 for elasticsearch 8
    end
  end

  def test_test
    # only works on 7 rn for some reason
    client = Elasticsearch::Client.new(hosts: "localhost:#{port}")
    puts client.search(q: 'test')
  end
end
