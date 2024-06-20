# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module AwsSqs::Chain
    def self.instrument!
      ::Aws::SQS::Client.class_eval do
        include NewRelic::Agent::Instrumentation::AwsSqs

        alias_method(:send_message_without_new_relic, :send_message)

        def send_message(*args)
          send_message_with_new_relic(*args) do
            send_message_without_new_relic(*args)
          end
        end

        alias_method(:send_message_batch_without_new_relic, :send_message_batch)

        def send_message_batch(*args)
          send_message_batch_with_new_relic(*args) do
            send_message_batch_without_new_relic(*args)
          end
        end

        alias_method(:receive_message_without_new_relic, :receive_message)

        def receive_message(*args)
          receive_message_with_new_relic(*args) do
            receive_message_without_new_relic(*args)
          end
        end
      end
    end
  end
end
