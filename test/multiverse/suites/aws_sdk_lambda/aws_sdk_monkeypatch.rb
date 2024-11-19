# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NRMonkeyPatch
  def encode_eventstream_response(rules, data, builder)
    # the original method calls `#inject` on the `data` argument, which will
    # fail if `data` is `nil`, so `||` in an empty hash when `nil`

    super(rules, data || {}, builder)
  end
end

Aws::Stubbing::Protocols::RestJson.prepend(NRMonkeyPatch)
