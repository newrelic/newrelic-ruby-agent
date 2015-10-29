# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'delayed_job'
begin
  require 'active_record'
rescue LoadError
  # Let it fail, might be working with another library
end

# Deprecated on some versions, required on others. Hurray!
Delayed::Worker.guess_backend

if Delayed::Worker.backend.to_s == "Delayed::Backend::ActiveRecord::Job"
  $db_connection = ActiveRecord::Base.establish_connection(:adapter  => "sqlite3",
                                                           :database => ":memory:")

  begin
    require 'generators/delayed_job/templates/migration'
  rescue MissingSourceFile
    # Back on DJ v2 the generators aren't in the lib folder so we have to do some
    # sneaky stuff to get them loaded. Still better than dup'ing them, though.
    dj_dir = ($:).grep(/delayed_job-/).first
    require "#{dj_dir}/../generators/delayed_job/templates/migration"
  end

  class CreateDelayedJobs
    @connection = $db_connection
  end

  class CreatePelicans < ActiveRecord::Migration
    @connection = $db_connection
    def self.up
      create_table :pelicans do |t|
        t.string :name
      end
    end
  end

  CreateDelayedJobs.up
  CreatePelicans.up
end
