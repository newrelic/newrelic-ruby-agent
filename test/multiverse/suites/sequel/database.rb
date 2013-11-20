# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'sequel'

# This file is intended to define the database connection and schema for all of
# the Sequel multiverse tests.
#
# DO NOT require newrelic_rpm here. Some of the tests rely on the timing of
# when New Relic gets pulled in.
if !defined?(DB)
  def jruby?
    defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
  end

  # Use an in-memory SQLite database
  if (jruby?)
    DB = Sequel.connect('jdbc:sqlite::memory:')
  else
    DB = Sequel.sqlite
  end

  # Create tables and model classes for testing
  DB.create_table( :authors ) do
    primary_key :id
    string :name
    string :login
  end
  class Author < Sequel::Model; end

  DB.create_table( :posts ) do
    primary_key :id
    string :title
    string :content
    time :created_at
  end
  class Post < Sequel::Model; end

  DB.create_table( :users ) do
    primary_key :uid
    string :login
    string :firstname
    string :lastname
  end
  class User < Sequel::Model; end

  # Version 4.0 of Sequel moved update_except off to a plugin
  # So we can test that we still instrument it, it's got to be included
  if defined?(Sequel::MAJOR) && Sequel::MAJOR >= 4
    Sequel::Model.plugin :blacklist_security
  end
end
