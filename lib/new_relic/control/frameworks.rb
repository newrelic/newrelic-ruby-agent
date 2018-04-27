# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  class Control
    # Contains subclasses of NewRelic::Control that are used when
    # starting the agent within an application. Framework-specific
    # logic should be included here, as documented within the Control
    # abstract parent class
    module Frameworks
    end
  end
end
