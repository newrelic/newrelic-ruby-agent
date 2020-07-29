# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    module Transformer
      extend self

      def transform span_event
        intrinsics, user_attributes, agent_attributes = span_event
        {
          "trace_id" => intrinsics[NewRelic::Agent::SpanEventPrimitive::TRACE_ID_KEY],
          "intrinsics" => hash_to_attributes(intrinsics),
          "user_attributes" => hash_to_attributes(user_attributes),
          "agent_attributes" => hash_to_attributes(agent_attributes)
        }
      end

      private

      KLASS_TO_ARG = {
        String => :string_value,
        TrueClass => :bool_value,
        FalseClass => :bool_value,
        Integer => :int_value,
        Float => :double_value,
      }
      if RUBY_VERSION < '2.4.0'
        KLASS_TO_ARG[Fixnum] = :int_value
      end
      if defined? BigDecimal
        KLASS_TO_ARG[BigDecimal] = :double_value 
      end
      
      def safe_param_name value
        KLASS_TO_ARG[value.class] || raise("Unhandled class #{value.class.name}")
      end

      def hash_to_attributes values
        values.map do |key, value|
          begin
            [key, AttributeValue.new(safe_param_name(value) => value)]
          rescue => e
            puts e.inspect
            puts [key, value].inspect
            nil
          end
        end.to_h
      end
    end
  end
end