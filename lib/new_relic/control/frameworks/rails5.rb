# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/control/frameworks/rails4'
require 'new_relic/rack/error_collector'
module NewRelic
  class Control
    module Frameworks
      class Rails5 < NewRelic::Control::Frameworks::Rails4
      end
    end
  end
end
