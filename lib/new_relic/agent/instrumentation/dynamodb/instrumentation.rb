# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Dynamodb
    PRODUCT = 'dynamodb'
    DEFAULT_HOST = 'dynamodb.amazonaws.com'

    def build_request_with_new_relic(*args)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      NewRelic::Agent.record_instrumentation_invocation(PRODUCT)

      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT,
        operation: args[0].to_s,
        host: config&.endpoint&.host || DEFAULT_HOST,
        port_path_or_id: config&.endpoint&.port
      )

      arn = get_arn(args[1])
      segment.add_agent_attribute('', arn) if arn

      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment&.finish
      end
    end

    def get_arn(params)
      table_name = params[:table_name]

      # table_name will be most common, but if that doesn't work
      # there are a couple of other keys in the params that can include either an arn or the table name
      if table_name.nil?
        param_arn = params[:backup_arn] ||
          params[:resource_arn] ||
          params[:export_arn] ||
          params[:import_arn] ||
          params[:table_arn] ||
          params[:source_table_arn]

        return param_arn if param_arn

        table_name = params[:global_table_name] ||
          params[:target_table_name] ||
          params[:table_creation_parameters]&.[](:table_name)
      end

      return unless table_name

      NewRelic::Agent::Aws.create_arn(PRODUCT, "table/#{table_name}", config)
    end
  end
end
