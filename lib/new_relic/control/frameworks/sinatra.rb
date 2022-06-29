# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/control/frameworks/ruby'
module NewRelic
  class Control
    module Frameworks
      # Contains basic control logic for Sinatra
      class Sinatra < NewRelic::Control::Frameworks::Ruby
        protected

        def install_shim
          super
          ::Sinatra::Base.class_eval { include NewRelic::Agent::Instrumentation::ControllerInstrumentation::Shim }
        end
      end
    end
  end
end
