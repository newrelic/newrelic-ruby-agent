# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/new_relic_service/marshaller'

module NewRelic
  module Agent
    class NewRelicService
      # Marshal collector protocol with JSON when available
      class JsonMarshaller < Marshaller
        def initialize
          ::NewRelic::Agent.logger.debug "Using JSON marshaller (#{NewRelic::JSONWrapper.backend_name})"
          unless self.class.is_supported?
            ::NewRelic::Agent.logger.warn "The JSON marshaller in use (#{NewRelic::JSONWrapper.backend_name}) is not recommended. Ensure the 'json' gem is available in your application for better performance."
          end
        end

        def dump(ruby, opts={})
          prepared = prepare(ruby, opts)
          NewRelic::JSONWrapper.dump(prepared,
            :normalize => Agent.config[:normalize_json_string_encodings])
        end

        def load(data)
          return_value(NewRelic::JSONWrapper.load(data)) if data && data != ''
        rescue => e
          ::NewRelic::Agent.logger.debug "#{e.class.name} : #{e.message} encountered loading collector response: #{data}"
          raise
        end

        def default_encoder
          Encoders::Base64CompressedJSON
        end

        def format
          'json'
        end

        def self.is_supported?
          NewRelic::JSONWrapper.usable_for_collector_serialization?
        end

        def self.human_readable?
          true # for some definitions of 'human'
        end
      end
    end
  end
end
