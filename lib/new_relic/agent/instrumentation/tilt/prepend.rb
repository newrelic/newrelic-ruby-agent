# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module Tilt::Prepend
    include NewRelic::Agent::Instrumentation::Tilt
  end
end
