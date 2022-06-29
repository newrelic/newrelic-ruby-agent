# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'sequel'

# This file is intended to define the database connection and schema for all of
# the Sequel multiverse tests.
#
# DO NOT require newrelic_rpm here. Some of the tests rely on the timing of
# when New Relic gets pulled in.
if !defined?(DB)

  def create_tables(db)
    db.create_table(:authors) do
      primary_key :id
      string :name
      string :login
    end

    db.create_table(:posts) do
      primary_key :id
      string :title
      string :content
      time :created_at
    end

    db.create_table(:users) do
      primary_key :uid
      string :login
      string :firstname
      string :lastname
    end
  end

  # Use an in-memory SQLite database
  if RUBY_ENGINE == 'jruby'
    DB = Sequel.connect('jdbc:sqlite::memory:')
  else
    DB = Sequel.sqlite
  end

  create_tables(DB)

  class Author < Sequel::Model; end

  class Post < Sequel::Model; end

  class User < Sequel::Model; end

  # Version 4.0 of Sequel moved update_except off to a plugin
  # So we can test that we still instrument it, it's got to be included
  if defined?(Sequel::MAJOR) && Sequel::MAJOR >= 4
    Sequel::Model.plugin :blacklist_security
  end

  # Version 5.0 of Sequel moved update_all and update_only to a plugin
  # So we can test that we still instrument those methods, it needs to
  # be included
  if defined?(Sequel::MAJOR) && Sequel::MAJOR >= 5
    Sequel::Model.plugin :whitelist_security
  end

  Post.strict_param_setting = false
end
