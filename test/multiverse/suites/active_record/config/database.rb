# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'active_record'
require 'erb'
require 'newrelic_rpm'

DependencyDetection.detect!

db_dir = File.expand_path('../../db', __FILE__)
config_dir = File.expand_path(File.dirname(__FILE__))

if defined?(ActiveRecord::VERSION)
  ENV['DATABASE_NAME'] = "multiverse_activerecord_#{ActiveRecord::VERSION::STRING}_#{RUBY_VERSION}_#{RUBY_ENGINE}".gsub(".", "_")
else
  ENV['DATABASE_NAME'] = "multiverse_activerecord_2_x_#{ENV["MULTIVERSE_ENV"]}_#{RUBY_VERSION}_#{RUBY_ENGINE}".gsub(".", "_")
end

config_raw = File.read(File.join(config_dir, 'database.yml'))
config_erb = ERB.new(config_raw).result
config_yml = if YAML.respond_to?(:unsafe_load)
  YAML.unsafe_load(config_erb)
else
  YAML.load(config_erb)
end

# Rails 2.x didn't keep the Rails out of ActiveRecord much...
RAILS_ENV = "test"
RAILS_ROOT = File.join(db_dir, "..")

ActiveRecord::Base.configurations = config_yml
ActiveRecord::Base.establish_connection :test
ActiveRecord::Base.logger = Logger.new(ENV["VERBOSE"] ? STDOUT : StringIO.new)

begin
  load 'active_record/railties/databases.rake'
rescue LoadError, StandardError
  load 'tasks/databases.rake'
end

if defined?(ActiveRecord::Tasks)
  include ActiveRecord::Tasks

  module Seeder
    def self.load_seed
      # Nope
    end
  end

  DatabaseTasks.env = "test"
  DatabaseTasks.db_dir = db_dir
  DatabaseTasks.migrations_paths = File.join(db_dir, 'migrate')
  DatabaseTasks.database_configuration = config_yml
  DatabaseTasks.seed_loader = Seeder
else
  # Hattip to https://github.com/janko-m/sinatra-activerecord/blob/master/lib/sinatra/activerecord/rake/activerecord_3.rb
  module Rails
    extend self

    def root
      Pathname.new(Rake.application.original_dir)
    end

    def env
      ActiveSupport::StringInquirer.new(ENV["RACK_ENV"] || "development")
    end

    def application
      seed_loader = Object.new
      seed_loader.instance_eval do
        def load_seed
          # Nope
        end
      end
      seed_loader
    end
  end

  Rake::Task.define_task("db:environment")
  Rake::Task["db:load_config"].clear if Rake::Task.task_defined? "db:load_config"
  Rake::Task.define_task("db:rails_env")
end
