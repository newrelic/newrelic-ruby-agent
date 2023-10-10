# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AsyncHttp
    def method_to_instrument_with_new_relic(*args)
      # add instrumentation content here
      yield
    end
  end
end
