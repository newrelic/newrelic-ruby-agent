# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module OpenTelemetry
      module MessagingPatch
        PRODUCE = 'Produce/'

        def transaction_name(library, destination_type, destination_name, action = nil)
          return super unless action == :produce

          name = Transaction::MESSAGE_PREFIX + library
          name << NewRelic::SLASH
          name << Transaction::MessageBrokerSegment::TYPES[destination_type]
          name << NewRelic::SLASH
          name << PRODUCE

          case destination_type
          when :queue, :topic, :exchange
            name << Transaction::MessageBrokerSegment::NAMED
            name << destination_name
          when :temporary_queue, :temporary_topic
            name << Transaction::MessageBrokerSegment::TEMP
          end

          name
        end
      end
    end
  end
end
