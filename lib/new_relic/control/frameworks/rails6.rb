# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/control/frameworks/rails4'

module NewRelic
  class Control
    module Frameworks
      class Rails6 < NewRelic::Control::Frameworks::Rails4
      end
    end
  end
end
