# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSqs::Prepend
    include NewRelic::Agent::Instrumentation::AwsSqs

    def send_message(*args)
      send_message_with_new_relic(*args) { super }
    end

    def send_message_batch(*args)
      send_message_batch_with_new_relic(*args) { super }
    end

    def receive_message(*args)
      receive_message_with_new_relic(*args) { super }
    end
  end
end
