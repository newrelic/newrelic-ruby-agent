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
    private_methods = MyFirstDatabase.private_instance_methods.map(&:to_sym), :internal
    assert_includes private_methods, :internal
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
