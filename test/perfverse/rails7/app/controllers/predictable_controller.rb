# frozen_string_literal: true

class PredictableController < ApplicationController

  def custom_event
    endpoint_name = 'Custom Event'
    ::NewRelic::Agent.record_custom_event("PredictableEvent", attr1: "value1", 'attr2': 1, 'attr3': 0.2, 'attr4': true)
    render :index, locals: {endpoint_name: endpoint_name}
  end
end
