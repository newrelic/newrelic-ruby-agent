# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  class Control
    module Frameworks
      # A control used when no framework is detected - the default.
      class Ruby < NewRelic::Control
        def env
          @env ||= ENV['NEW_RELIC_ENV'] || ENV['RUBY_ENV'] || ENV['LOTUS_ENV']
                   ENV['RAILS_ENV']     || ENV['RACK_ENV'] || 'development'
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
