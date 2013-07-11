# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rubygems'

require 'active_record'
require 'newrelic_rpm'
require 'multiverse/color'
require 'multiverse_helpers'
require 'minitest/unit'

class InstrumentActiveRecordMethods < MiniTest::Unit::TestCase
  extend Multiverse::Color

  include MultiverseHelpers
  setup_and_teardown_agent

  if RUBY_VERSION >= '1.8.7'
    if RUBY_PLATFORM == 'java'
      require 'jdbc/sqlite3'
      @@adapter = 'sqlite3'
    else
      require 'sqlite3'
      @@adapter = 'sqlite3'
    end

    class User < ActiveRecord::Base
      include NewRelic::Agent::MethodTracer
      has_many :aliases

      add_method_tracer :save!
      add_method_tracer :persisted?
    end

    class Alias < ActiveRecord::Base
      include NewRelic::Agent::MethodTracer

      add_method_tracer :save!
      add_method_tracer :persisted?
      add_method_tracer :destroyed?
    end

    def after_setup
      puts "adapter : #{@@adapter}"
      @db_connection = ActiveRecord::Base.establish_connection( :adapter => @@adapter, :database => "testdb.sqlite3")
      ActiveRecord::Migration.class_eval do
        @connection = @db_connection
        create_table :users do |t|
              t.string  :name
        end

        create_table :aliases do |t|
            t.integer :user_id
            t.string :aka
        end
      end
    end

    def after_teardown
      @db_connection = ActiveRecord::Base.establish_connection( :adapter => "sqlite3", :database => "testdb.sqlite3")
      ActiveRecord::Migration.class_eval do
        @connection = @db_connection
        drop_table :users
        drop_table :aliases
      end
    end

    def test_basic_creation
      a_user = User.new :name => "Bob"
      assert a_user.new_record?
      a_user.save!
      assert User.connected?
      assert a_user.persisted?
      assert a_user.id == 1
    end

    def test_alias_collection_query_method
      a_user = User.new :name => "Bob"
      a_user.save!
      a_user = User.find(1)
      assert User.connected?
      assert a_user.id = 1

      an_alias = Alias.new :user_id => a_user.id, :aka => "the Blob"
      assert an_alias.new_record?
      an_alias.save!
      assert an_alias.persisted?
      an_alias.destroy
      assert an_alias.destroyed?
    end

  else
    def test_truth
      assert true # jruby freaks out if there are no tests defined in the test class
    end
    puts yellow('SKIPPED! skipped until ruby 1.8.6 compatibilites ironed out')
  end
end
