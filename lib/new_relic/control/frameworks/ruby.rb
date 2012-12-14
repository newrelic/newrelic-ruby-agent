module NewRelic
  class Control
    module Frameworks
      # A control used when no framework is detected - the default.
      class Ruby < NewRelic::Control

        def env
          @env ||= ENV['RUBY_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
        end

        def root
          @root ||= ENV['APP_ROOT'] || '.'
        end

        def init_config(options={})
        end

      end
    end
  end
end
