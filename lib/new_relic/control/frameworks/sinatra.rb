# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


require 'new_relic/control/frameworks/ruby'
module NewRelic
  class Control
    module Frameworks
      # Contains basic control logic for Sinatra
      class Sinatra < NewRelic::Control::Frameworks::Ruby

        def env
          @env ||= ENV['NEW_RELIC_ENV'] || ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
        end

        def init_config(options={})
          super
        end

      end
    end
  end
end
