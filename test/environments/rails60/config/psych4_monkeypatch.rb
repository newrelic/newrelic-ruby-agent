# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# TODO: remove this monkeypatch if a Rails 6.0.x release newer than v6.0.6
#       addresses the issue. Rails added a new
#       `config.active_storage.use_yaml_unsafe_load` option so that Psych v4
#       based Rubies (CRuby 3.1, JRuby 9.4.0.0) can work with the older Rails
#       code. See https://github.com/rails/rails/commit/611990f1a6c137c2d56b1ba06b27e5d2434dcd6a
#       for complete details on the Psych v4 compatibility issue. Unfortunately,
#       the new config option does not appear to help with the use of aliases
#       found with `config/databse.yml`, so this monkeypatch is used.
module Rails
  class Application
    class Configuration < ::Rails::Engine::Configuration
      def database_configuration
        path = paths['config/database'].existent.first
        yaml = Pathname.new(path) if path

        config = if yaml&.exist?
          require 'yaml'
          require 'erb'

          # THIS LINE CHANGED
          # loaded_yaml = YAML.load(ERB.new(yaml.read).result) || {}
          loaded_yaml = YAML.unsafe_load(ERB.new(yaml.read).result) || {}

          shared = loaded_yaml.delete('shared')
          if shared
            loaded_yaml.each do |_k, values|
              values.reverse_merge!(shared)
            end
          end
          Hash.new(shared).merge(loaded_yaml)
        elsif ENV['DATABASE_URL']
          {}
        else
          raise "Could not load database configuration. No such file - #{paths['config/database'].instance_variable_get(:@paths)}"
        end

        config
      rescue Psych::SyntaxError => e
        raise "YAML syntax error occurred while parsing #{paths['config/database'].first}. " \
              'Please note that YAML must be consistently indented using spaces. Tabs are not allowed. ' \
              "Error: #{e.message}"
      rescue => e
        raise e, "Cannot load database configuration:\n#{e.message}", e.backtrace
      end
    end
  end
end
