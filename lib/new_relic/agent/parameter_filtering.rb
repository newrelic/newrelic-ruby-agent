# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module ParameterFiltering
      extend self

      def apply_filters(env, params)
        params = filter_using_rails(env, params)
        params = filter_rack_file_data(env, params)
        params
      end

      def filter_using_rails(env, params)
        return params unless defined?(ActionDispatch::Http::ParameterFilter) && env.key?("action_dispatch.parameter_filter")
        filters = env["action_dispatch.parameter_filter"]
        ActionDispatch::Http::ParameterFilter.new(filters).filter(params)
      end

      def filter_rack_file_data(env, params)
        content_type = env["CONTENT_TYPE"]
        multipart = content_type && content_type.start_with?("multipart")

        params.inject({}) do |memo, (k,v)|
          if multipart && v.is_a?(Hash) && v[:tempfile]
            memo[k] = "[FILE]"
          else
            memo[k] = v
          end
          memo
        end
      end

      def filter_rails_request_parameters(params)
        result = params.dup
        result.delete("controller")
        result.delete("action")
        result
      end
    end
  end
end
