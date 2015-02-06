# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'rubygems'

require 'active_record'
require 'active_support/multibyte'

require 'multiverse/color'

require File.expand_path(File.join(__FILE__, "..", "app", "models", "models"))

class InstrumentActiveRecordMethods < Minitest::Test
  extend Multiverse::Color

  include MultiverseHelpers
  setup_and_teardown_agent

  def test_basic_creation
    a_user = User.new :name => "Bob"
    assert a_user.new_record?
    a_user.save!

    assert User.connected?
    assert a_user.persisted? if a_user.respond_to?(:persisted?)
  end

  def test_alias_collection_query_method
    a_user = User.new :name => "Bob"
    a_user.save!

    a_user = User.first
    assert User.connected?

    an_alias = Alias.new :user_id => a_user.id, :aka => "the Blob"
    assert an_alias.new_record?
    an_alias.save!
    assert an_alias.persisted? if a_user.respond_to?(:persisted?)
    an_alias.destroy
    assert an_alias.destroyed? if a_user.respond_to?(:destroyed?)
  end
end
