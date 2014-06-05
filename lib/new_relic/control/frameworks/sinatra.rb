# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/control/frameworks/ruby'
module NewRelic
  class Control
    module Frameworks
      # Contains basic control logic for Sinatra
      class Sinatra < NewRelic::Control::Frameworks::Ruby
        def root
          if defined?(::Sinatra::Base)
            ::Sinatra::Base.settings.root
          end
        end
      end
    end
  end
end
