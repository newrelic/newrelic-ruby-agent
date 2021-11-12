# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module ParameterFiltering
      extend self

      ACTION_DISPATCH_PARAMETER_FILTER = 'action_dispatch.parameter_filter'.freeze

      RAILS_FILTER_CLASS = if defined?(ActiveSupport::ParameterFilter)
                             ActiveSupport::ParameterFilter
                           elsif defined?(ActionDispatch::Http::ParameterFilter)
                             ActionDispatch::Http::ParameterFilter
                           end

      def apply_filters(env, params)
        if filters = env[ACTION_DISPATCH_PARAMETER_FILTER]
          params = filter_using_rails(params, filters)
        end
        filter_rack_file_data(env, params)
      end

      def filter_using_rails(params, filters)
        return params if RAILS_FILTER_CLASS.nil?

        pre_filtered_params = filter_rails_request_parameters(params)
        RAILS_FILTER_CLASS.new(filters).filter(pre_filtered_params)
      end

      def filter_rack_file_data(env, params)
        content_type = env['CONTENT_TYPE']
        multipart = content_type && content_type.start_with?('multipart')

        params.each_with_object({}) do |(k, v), memo|
          memo[k] = if multipart && v.is_a?(Hash) && v[:tempfile]
                      '[FILE]'
                    else
                      v
                    end
        end
      end

      def filter_rails_request_parameters(params)
        result = params.dup
        result.delete('controller')
        result.delete('action')
        result
      end
    end
  end
end
