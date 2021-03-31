# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Memcache
    module Chain 
      extend Helper

      def self.instrument! target_class
        instrument_methods target_class, client_methods
      end
    end

    # module ChainCAS 

    #   extend self

    #   METHODS = [:get_cas, :set_cas, :replace_cas, :delete_cas]

    #   def instrument_methods(client_class, requested_methods = METHODS)
    #     supported_methods_for(client_class, requested_methods).each do |method_name|

    #       visibility = NewRelic::Helper.instance_method_visibility client_class, method_name
    #       method_name_without = :"#{method_name}_without_newrelic_trace"

    #       client_class.class_eval do
    #         include NewRelic::Agent::Instrumentation::MemCache::Tracer

    #         alias_method method_name_without, method_name

    #         define_method method_name do |*args, &block|
    #           with_newrelic_tracing(method_name, *args) { send method_name_without, *args, &block }
    #         end

    #         send visibility, method_name
    #         send visibility, method_name_without
    #       end
    #     end
    #   end

    #   def instrument! target_class
    #     instrument_methods target_class, METHODS
    #   end
    # end
  end
end
