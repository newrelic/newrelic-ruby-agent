# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    # This module contains helper methods related to decorating log messages
    module LocalLogDecorator
      extend self

      def decorate(message)
        return message if !decorating_enabled? || message.nil?

        metadata = NewRelic::Agent.linking_metadata

        if message.is_a?(Hash)
          message.merge!(metadata) unless message.frozen?
          return
        end

        formatted_metadata = " NR-LINKING|#{metadata[ENTITY_GUID_KEY]}|#{metadata[HOSTNAME_KEY]}|" \
                             "#{metadata[TRACE_ID_KEY]}|#{metadata[SPAN_ID_KEY]}|" \
                             "#{escape_entity_name(metadata[ENTITY_NAME_KEY])}|"

        message.partition("\n").insert(1, formatted_metadata).join
      end

      private

      def decorating_enabled?
        NewRelic::Agent.config[:'application_logging.enabled'] &&
          (NewRelic::Agent::Instrumentation::Logger.enabled? ||
            NewRelic::Agent::Instrumentation::LogStasher.enabled?) &&
          NewRelic::Agent.config[:'application_logging.local_decorating.enabled']
      end

      def escape_entity_name(entity_name)
        return unless entity_name

        # TODO: OLD RUBIES 3.3
        # URI version 1.0 marked URI::RFC3986_PARSER.escape as obsolete,
        # which URI::DEFAULT_PARSER is an alias for.
        # URI version 1.0+ will ship with Ruby 3.4
        # Once we drop support for Rubies below 3.4, we can use the
        # URI::RFC2396 parser exclusively.
        if NewRelic::Helper.version_satisfied?(URI::VERSION, '>=', '1.0')
          URI::RFC2396_PARSER.escape(entity_name)
        else
          URI::DEFAULT_PARSER.escape(entity_name)
        end
      end
    end
  end
end
