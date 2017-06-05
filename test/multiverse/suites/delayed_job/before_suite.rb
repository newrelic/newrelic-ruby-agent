# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'delayed_job'

migration_version = nil

begin
  require 'active_record'

  # Get the version of the ActiveRecord migration class (see below)

  if ActiveRecord::VERSION::STRING >= '5.0.0'
    migration_version = "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
  end

rescue LoadError
  # Let it fail, might be working with another library
end

# Deprecated on some versions, required on others. Hurray!
Delayed::Worker.guess_backend

if Delayed::Worker.backend.to_s == "Delayed::Backend::ActiveRecord::Job"
  $db_connection = ActiveRecord::Base.establish_connection(:adapter  => "sqlite3",
                                                           :database => ":memory:")


  # Evaluate the delayed_job_active_record ERB template for database migration
  # This handles the case where ActiveRecord versions greater than or equal to 5.0
  # have versioned migration classes (e.g. ActiveRecord::Migration[5.0]) and those
  # less than 5.0 do not.

  dj_gem_spec = Bundler.rubygems.loaded_specs("delayed_job_active_record") ||
                Bundler.rubygems.loaded_specs("delayed_job")

  dj_gem_path = dj_gem_spec.full_gem_path

  b = binding
  content = File.read("#{dj_gem_path}/lib/generators/delayed_job/templates/migration.rb")
  renderer = ERB.new(content)
  eval(renderer.result(b))

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
