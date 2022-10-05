# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

DataMapper::Logger.new("/dev/null", :debug)
DataMapper.setup(:default, 'sqlite::memory:')
class Post
  include DataMapper::Resource
  property :id, Serial # An auto-increment integer key
  property :title, String # A varchar type string, for short strings
  property :body, Text # A text block, for longer string data.
end
DataMapper.auto_migrate!
DataMapper.finalize

class DummyConnection
  module DummyLogging
    def log(*args); end
  end

  include DummyLogging
  include NewRelic::Agent::Instrumentation::DataMapperInstrumentation
end

class DataMapperTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_create
    # DM 1.0 generates a create method on inclusion of a module that internally
    # calls the instance #save method, so that's all we see on that version.
    expected_metric = DataMapper::VERSION < "1.1" ? :save : :create
    assert_basic_metrics(expected_metric) do
      in_transaction do
        Post.create(:title => "Dummy post", :body => "whatever, man")
      end
    end
  end

  def test_create!
    assert_basic_metrics(:create) do
      in_transaction do
        Post.create!(:title => "Dummy post", :body => "whatever, man")
      end
    end
  end

  def test_get
    assert_against_record(:get) do |post|
      in_transaction do
        Post.get(post.id)
      end
    end
  end

  def test_get!
    assert_against_record(:get) do |post|
      in_transaction do
        Post.get!(post.id)
      end
    end
  end

  def test_first
    assert_against_record(:first) do
      in_transaction do
        Post.first
      end
    end
  end

  def test_all
    assert_against_record(:all) do
      in_transaction do
        Post.all
      end
    end
  end

  def test_last
    assert_against_record(:last) do
      in_transaction do
        Post.last
      end
    end
  end

  def test_bulk_update
    assert_against_record(:update) do
      in_transaction do
        Post.update(:title => 'other title')
      end
    end
  end

  def test_bulk_update!
    assert_against_record(:update) do
      in_transaction do
        Post.update!(:title => 'other title')
      end
    end
  end

  def test_instance_update
    assert_against_record(:update) do |post|
      in_transaction do
        post.update(:title => 'other title')
      end
    end
  end

  def test_bulk_update!
    assert_against_record(:update) do |post|
      in_transaction do
        post.update!(:title => 'other title')
      end
    end
  end

  def test_bulk_destroy
    assert_against_record(:destroy) do
      in_transaction do
        Post.destroy
      end
    end
  end

  def test_bulk_destroy!
    assert_against_record(:destroy) do
      in_transaction do
        Post.destroy!
      end
    end
  end

  def test_instance_destroy
    assert_against_record(:destroy) do |post|
      in_transaction do
        post.destroy
      end
    end
  end

  def test_instance_destroy!
    assert_against_record(:destroy) do |post|
      in_transaction do
        post.destroy!
      end
    end
  end

  def test_save
    assert_against_record(:save) do |post|
      in_transaction do
        post.save
      end
    end
  end

  def test_save!
    assert_against_record(:save) do |post|
      in_transaction do
        post.save!
      end
    end
  end

  def test_aggregate
    assert_against_record(:aggregate) do
      in_transaction do
        Post.aggregate(:title, :all.count)
      end
    end
  end

  def test_find
    assert_against_record(:find) do
      in_transaction do
        Post.find(1)
      end
    end
  end

  def test_find_by_sql
    assert_against_record(:find_by_sql) do
      in_transaction do
        Post.find_by_sql('select * from posts')
      end
    end
  end

  def test_in_web_transaction
    in_web_transaction("dm4evr") do
      Post.all
    end

    assert_metrics_recorded([
      'Datastore/all',
      'Datastore/allWeb',
      'Datastore/DataMapper/all',
      'Datastore/DataMapper/allWeb',
      'Datastore/operation/DataMapper/all',
      'Datastore/statement/DataMapper/Post/all',
      ['Datastore/statement/DataMapper/Post/all', 'dm4evr']
    ])
  end

  def test_collection_get
    assert_against_record(:get) do
      in_transaction do
        Post.all.get(1)
      end
    end
  end

  def test_collection_first
    assert_against_record(:first) do
      in_transaction do
        Post.all.first
      end
    end
  end

  def test_collection_last
    assert_against_record(:last) do
      in_transaction do
        Post.all.last
      end
    end
  end

  def test_collection_all
    assert_against_record(:all) do
      in_transaction do
        Post.all.all # sic
      end
    end

    assert_metrics_recorded(
      'Datastore/statement/DataMapper/Post/all' => {:call_count => 2}
    )
  end

  def test_collection_lazy_load
    assert_against_record(:lazy_load) do
      in_transaction do
        Post.all.send(:lazy_load)
      end
    end
  end

  def test_collection_create
    assert_against_record(:create) do
      in_transaction do
        Post.all.create(:title => "The Title", :body => "Body")
      end
    end
  end

  def test_collection_create!
    assert_against_record(:create) do
      in_transaction do
        Post.all.create!(:title => "The Title", :body => "Body")
      end
    end
  end

  def test_collection_update
    assert_against_record(:update) do
      in_transaction do
        Post.all.update(:title => "Another")
      end
    end
  end

  def test_collection_update!
    assert_against_record(:update) do
      in_transaction do
        Post.all.update!(:title => "Another")
      end
    end
  end

  def test_collection_destroy
    assert_against_record(:destroy) do
      in_transaction do
        Post.all.destroy
      end
    end
  end

  def test_collection_destroy!
    assert_against_record(:destroy) do
      in_transaction do
        Post.all.destroy!
      end
    end
  end

  def test_collection_aggregate
    assert_against_record(:aggregate) do
      in_transaction do
        Post.all.aggregate(:title, :all.count)
      end
    end
  end

  def test_notices_sql
    in_web_transaction do
      Post.get(42)
    end

    sql_node = find_last_transaction_node(last_transaction_trace)
    refute_nil sql_node.obfuscated_sql
  end

  def test_direct_select_on_adapter
    in_web_transaction('dm4evr') do
      DataMapper.repository.adapter.select('select * from posts limit 1')
    end

    assert_metrics_recorded([
      'Datastore/all',
      'Datastore/allWeb',
      'Datastore/DataMapper/all',
      'Datastore/DataMapper/allWeb',
      'Datastore/operation/DataMapper/select',
      ['Datastore/operation/DataMapper/select', 'dm4evr']
    ])
  end

  def test_direct_execute_on_adapter
    in_transaction('background') do
      DataMapper.repository.adapter.execute('update posts set title=title')
    end

    assert_metrics_recorded([
      'Datastore/all',
      'Datastore/allOther',
      'Datastore/DataMapper/all',
      'Datastore/DataMapper/allOther',
      'Datastore/operation/DataMapper/execute',
      ['Datastore/operation/DataMapper/execute', 'background']
    ])
  end

  def test_datamapper_transaction_commit
    in_transaction do
      Post.transaction do |t|
        Post.destroy!
      end
    end

    assert_metrics_recorded([
      'Datastore/all',
      'Datastore/allOther',
      'Datastore/DataMapper/all',
      'Datastore/DataMapper/allOther',
      'Datastore/operation/DataMapper/commit'
    ])
  end

  # https://support.newrelic.com/tickets/2101
  # https://github.com/newrelic/newrelic-ruby-agent/pull/42
  # https://github.com/newrelic/newrelic-ruby-agent/pull/45
  def test_should_not_bomb_out_if_a_query_is_in_an_invalid_encoding
    db = DummyConnection.new
    q = String.new("select ICS95095010000000000083320000BS01030000004100+\xFF00000000000000000")
    q.force_encoding('UTF-8')

    msg = mock
    msg.stubs(:duration).returns(1)
    msg.stubs(:query).returns(q)

    refute msg.query.valid_encoding?
    db.send(:log, msg)
  end

  def test_obfuscate_query_in_sqlerror
    invalid_query = "select * from users where password='Slurms McKenzie' limit 1"
    with_config(:'slow_sql.record_sql' => 'obfuscated') do
      begin
        in_transaction do
          DataMapper.repository.adapter.select(invalid_query)
        end
      rescue => e
        NewRelic::Agent.notice_error(e)
      end
    end

    refute_includes last_traced_error.message, invalid_query
  end

  def test_error_noticing_on_segments
    invalid_query = "select * from users where password='Slurms McKenzie' limit 1"
    txn = nil

    begin
      in_transaction do |test_txn|
        txn = test_txn
        DataMapper.repository.adapter.select(invalid_query)
      end
    rescue => e
      # No-op for error noticing
    end

    assert_segment_noticed_error txn, /DataMapper\/select/i, "DataObjects::SyntaxError", /no such table: users/i
  end

  def test_splice_user_password_from_sqlerror
    begin
      in_transaction do
        DataMapper.repository.adapter.select("select * from users")
      end
    rescue => e
      NewRelic::Agent.notice_error(e)
    end

    refute_includes last_traced_error.message, '&password=',
      "error message expected not to contain '&password=' but did: #{last_traced_error && last_traced_error.message}"
  end

  def assert_against_record(operation)
    post = Post.create!(:title => "Dummy post", :body => "whatever, man")

    # Want to ignore our default record's creation for these tests
    NewRelic::Agent.drop_buffered_data

    assert_basic_metrics(operation) do
      yield(post)
    end
  end

  def assert_basic_metrics(operation)
    yield
    assert_metrics_recorded([
      "Datastore/all",
      "Datastore/allOther",
      "Datastore/operation/DataMapper/#{operation}",
      "Datastore/statement/DataMapper/Post/#{operation}"
    ])
  end
end
