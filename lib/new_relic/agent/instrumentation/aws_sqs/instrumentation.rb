# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSqs

    def send_message_with_new_relic(*args)
      # add instrumentation content here
      yield
    end

    def send_message_batch_with_new_relic(*args)
      # add instrumentation content here
      yield
    end

    def receive_message_with_new_relic(*args)
      # add instrumentation content here
      yield
    end
  end
end
