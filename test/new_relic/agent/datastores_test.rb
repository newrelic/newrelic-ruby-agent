# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores'
require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

class NewRelic::Agent::DatastoresTest < Minitest::Test
  class MyFirstDatabase
    THE_OBJECT = Object.new

    def find
      THE_OBJECT
    end

    def save
    end

    def internal
    end

    private :internal

    NewRelic::Agent::Datastores.trace self, :find,     "MyFirstDatabase"
    NewRelic::Agent::Datastores.trace self, :save,     "MyFirstDatabase", "create"
    NewRelic::Agent::Datastores.trace self, :internal, "MyFirstDatabase"
  end

  def setup
    NewRelic::Agent.drop_buffered_data
  end

  def test_still_calls_through
    assert_equal MyFirstDatabase::THE_OBJECT, MyFirstDatabase.new.find
  end

  def test_in_web_transaction
    in_web_transaction("txn") do
      MyFirstDatabase.new.find
    end

    assert_metrics("find", "Web")
  end

  def test_in_other_transaction
    in_background_transaction("txn") do
      MyFirstDatabase.new.find
    end

    assert_metrics("find", "Other")
  end

  def test_outside_transaction
    MyFirstDatabase.new.find
    assert_metrics_recorded([
                            "Datastore/operation/MyFirstDatabase/find",
                            "Datastore/MyFirstDatabase/allOther",
                            "Datastore/MyFirstDatabase/all",
                            "Datastore/allOther",
                            "Datastore/all"])
  end

  def test_separate_operation_name
    in_background_transaction("txn") do
      MyFirstDatabase.new.save
    end

    assert_metrics("create", "Other")
  end

  def test_safe_to_reinstrument
    MyFirstDatabase.class_eval do
      NewRelic::Agent::Datastores.trace self, :find, "MyFirstDatabase", "find"
    end

    assert_equal MyFirstDatabase::THE_OBJECT, MyFirstDatabase.new.find
  end

  def test_method_retains_visbility
    private_methods = MyFirstDatabase.private_instance_methods.map(&:to_sym)
    assert_includes private_methods, :internal
  end

  def test_wrap_doesnt_interfere
    result = NewRelic::Agent::Datastores.wrap("MyFirstDatabase", "op") do
      "yo"
    end

    assert_equal "yo", result
  end

  def test_wrap
    in_background_transaction("txn") do
      NewRelic::Agent::Datastores.wrap("MyFirstDatabase", "op", "coll") do
      end
    end

    assert_statement_metrics("op", "coll", "Other")
  end

  def test_wrap_with_only_operation
    in_background_transaction("txn") do
      NewRelic::Agent::Datastores.wrap("MyFirstDatabase", "op") do
      end
    end

    assert_metrics("op", "Other")
  end

  def test_wrap_with_no_operation
    in_background_transaction("txn") do
      NewRelic::Agent::Datastores.wrap("MyFirstDatabase", nil) do
      end
    end

    refute_metrics_recorded([
                            "Datastore/operation/MyFirstDatabase/",
                            "Datastore/MyFirstDatabase/allOther",
                            "Datastore/MyFirstDatabase/all",
                            "Datastore/allOther",
                            "Datastore/all"])
  end

  def test_wrap_calls_notice
    noticed = nil
    notice = Proc.new do |*args|
      noticed = args
    end

    NewRelic::Agent::Datastores.wrap("MyFirstDatabase", "op", "coll", notice) do
      "yo"
    end

    result, scoped_metric, elapsed = noticed

    assert_equal "yo", result
    assert_equal "Datastore/statement/MyFirstDatabase/coll/op", scoped_metric
    assert_instance_of Float, elapsed
  end

  def test_notice_sql
    query   = "SELECT * FROM SomeThings"
    metric  = "Datastore/statement/MyFirstDatabase/SomeThing/find"
    elapsed = 1.0

    agent = NewRelic::Agent.instance
    agent.transaction_sampler.expects(:notice_sql).with(query, nil, elapsed)
    agent.sql_sampler.expects(:notice_sql).with(query, metric, nil, elapsed)

    NewRelic::Agent::Datastores.notice_sql(query, metric, elapsed)
  end

  def test_notice_statement
    query   = "key"
    elapsed = 1.0

    agent = NewRelic::Agent.instance
    agent.transaction_sampler.expects(:notice_nosql_statement).with(query, elapsed)

    NewRelic::Agent::Datastores.notice_statement(query, elapsed)
  end

  def test_dont_notice_statement_based_on_record_sql_setting
    query   = "key"
    elapsed = 1.0

    agent = NewRelic::Agent.instance
    agent.transaction_sampler.expects(:notice_nosql_statement).never

    with_config(:'transaction_tracer.record_sql' => 'none') do
      NewRelic::Agent::Datastores.notice_statement(query, elapsed)
    end
  end

  def assert_statement_metrics(operation, collection, type)
    assert_metrics_recorded([
                            "Datastore/statement/MyFirstDatabase/#{collection}/#{operation}",
                            ["Datastore/statement/MyFirstDatabase/#{collection}/#{operation}", "txn"],
                            "Datastore/operation/MyFirstDatabase/#{operation}",
                            "Datastore/MyFirstDatabase/all#{type}",
                            "Datastore/MyFirstDatabase/all",
                            "Datastore/all#{type}",
                            "Datastore/all"])
  end

  def assert_metrics(operation, type)
    assert_metrics_recorded([
                            "Datastore/operation/MyFirstDatabase/#{operation}",
                            ["Datastore/operation/MyFirstDatabase/#{operation}", "txn"],
                            "Datastore/MyFirstDatabase/all#{type}",
                            "Datastore/MyFirstDatabase/all",
                            "Datastore/all#{type}",
                            "Datastore/all"])
  end
end
