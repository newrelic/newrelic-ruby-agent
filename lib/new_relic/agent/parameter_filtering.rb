# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module ParameterFiltering
      extend self


      def apply_filters(env, params)
        params = filter_using_active_dispatch(env, params)
        params = filter_using_rails(params)
        params = filter_rack_file_data(env, params)
        params
      end

      def filter_using_active_dispatch(env, params)
        return params if rails_parameter_filter.nil? || !env.key?("action_dispatch.parameter_filter")
        
        filters = env["action_dispatch.parameter_filter"]
        rails_parameter_filter.new(filters).filter(params)
      end

      def filter_using_rails(params)
        return params if rails_parameter_filter.nil?

        munged_params = filter_rails_request_parameters(params)
        filters = Rails.application.config.filter_parameters
        rails_parameter_filter.new(filters).filter(munged_params)
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

      def rails_parameter_filter
        if defined?(ActiveSupport::ParameterFilter)
          ActiveSupport::ParameterFilter
        elsif defined?(ActionDispatch::Http::ParameterFilter)
          ActionDispatch::Http::ParameterFilter
        end
      end
    end
  end
end
