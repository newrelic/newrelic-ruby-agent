# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/control/frameworks/sinatra'
module NewRelic
  class Control
    module Frameworks
      # Contains basic control logic for Padrino
      class Padrino < NewRelic::Control::Frameworks::Sinatra
      end
    end
  end
end
