# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class PredictableController < ApplicationController

  def custom_event
    # For this test, we're using the HTTP.rb instrumentation
    # as a variable: sometimes it will pull from NR,
    # sometimes it will pull from OTel
    endpoint_name = 'http://www.tiobe.com/tiobe-index/'
    HTTP.get(endpoint_name)
    # We don't have an equivalent for
    # endpoints_name = 'Custom Event'
    # ::NewRelic::Agent.record_custom_event("PredictableEvent", attr1: "value1", 'attr2': 1, 'attr3': 0.2, 'attr4': true)
    render :index, locals: {endpoint_name: endpoint_name}
  end
end
