# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'data_mapper'

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')
require 'multiverse_helpers'

DataMapper::Logger.new("/dev/null", :debug)
DataMapper.setup(:default, 'sqlite::memory:')
class Post
  include DataMapper::Resource
  property :id,         Serial    # An auto-increment integer key
  property :title,      String    # A varchar type string, for short strings
  property :body,       Text      # A text block, for longer string data.
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

class DataMapperTest < MiniTest::Unit::TestCase
  include MultiverseHelpers

  setup_and_teardown_agent

  def test_basic_metrics
    post = Post.create(:title => "Dummy post", :body => "whatever, man")
    post = Post.get(post.id)
    post.update(:title => 'other title')
    post.destroy
    assert_metrics_recorded(
      'ActiveRecord/Post/save' => { :call_count => 2 },
      'ActiveRecord/Post/get'  => { :call_count => 1 },
      'ActiveRecord/Post/update'  => { :call_count => 1 },
      'ActiveRecord/Post/destroy' => { :call_count => 1 }
    )
  end

  def test_rollup_metrics_for_create
    post = Post.create(:title => 'foo', :body => 'bar')
    post.save
    assert_metrics_recorded(['ActiveRecord/save'])
  end

  def test_rollup_metrics_for_update
    post = Post.create(:title => 'foo', :body => 'bar')
    post.body = 'baz'
    post.save
    assert_metrics_recorded('ActiveRecord/save' => { :call_count => 2 })
  end

  def test_rollup_metrics_for_destroy
    post = Post.create(:title => 'foo', :body => 'bar')
    post.save
    post.destroy
    assert_metrics_recorded(['ActiveRecord/destroy'])
  end

  def test_rollup_metrics_should_include_all_if_in_web_transaction
    in_web_transaction do
      Post.create(:title => 'foo', :body => 'bar').save
    end
    assert_metrics_recorded([
      'ActiveRecord/save',
      'ActiveRecord/all'
    ])
  end

  def test_rollup_metrics_should_omit_all_if_not_in_web_transaction
    in_transaction do
      Post.create(:title => 'foo', :body => 'bar').save
    end
    assert_metrics_recorded(['ActiveRecord/save'])
    assert_metrics_not_recorded(['ActiveRecord/all'])
  end

  # https://support.newrelic.com/tickets/2101
  # https://github.com/newrelic/rpm/pull/42
  # https://github.com/newrelic/rpm/pull/45
  def test_should_not_bomb_out_if_a_query_is_in_an_invalid_encoding
    db = DummyConnection.new
    q = "select ICS95095010000000000083320000BS01030000004100+\xFF00000000000000000"
    q.force_encoding 'UTF-8' if RUBY_VERSION >= '1.9'

    msg = mock
    msg.stubs(:duration).returns(1)
    msg.stubs(:query).returns(q)

    assert_equal false, msg.query.valid_encoding? if RUBY_VERSION >= '1.9'
    db.send(:log, msg)
  end
end
