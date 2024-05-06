# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Dynamodb::Chain
    def self.instrument!
      ::Dynamodb.class_eval do
        include NewRelic::Agent::Instrumentation::Dynamodb

        %w[create_table
          delete_item
          delete_table
          get_item
          put_item
          query
          scan
          update_item].each do |method_name|
          alias_method("#{method_name}_without_new_relic".to_sym, method_name.to_sym)

          define_method(method_name) do |*args|
            instrument_method_with_new_relic(method_name, *args) { send("#{method_name}_without_new_relic".to_sym, *args) }
          end
        end

        alias_method(:build_request_without_new_relic, :build_request)

        def build_request(*args)
          build_request_with_new_relic(*args) { build_request_without_new_relic(*args) }
        end
      end
    end
  end
end
