# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'json'
require 'new_relic/base64'
require 'uri'

require_relative 'serverless_handler_event_sources'

module NewRelic
  module Agent
    class ServerlessHandler
      AGENT_ATTRIBUTE_DESTINATIONS = NewRelic::Agent::AttributeFilter::DST_TRANSACTION_TRACER |
        NewRelic::Agent::AttributeFilter::DST_TRANSACTION_EVENTS
      EXECUTION_ENVIRONMENT = "AWS_Lambda_ruby#{RUBY_VERSION.rpartition('.').first}".freeze
      LAMBDA_MARKER = 'NR_LAMBDA_MONITORING'
      LAMBDA_ENVIRONMENT_VARIABLE = 'AWS_LAMBDA_FUNCTION_NAME'
      METHOD_BLOCKLIST = %i[agent_command_results connect get_agent_commands preconnect profile_data
        shutdown].freeze
      NAMED_PIPE = '/tmp/newrelic-telemetry'
      SUPPORTABILITY_METRIC = 'Supportability/AWSLambda/HandlerInvocation'
      FUNCTION_NAME = 'lambda_function'
      PAYLOAD_VERSION = ENV.fetch('NEW_RELIC_SERVERLESS_PAYLOAD_VERSION', 2)
      DIGIT = /\d/
      EVENT_SOURCES = NewRelic::Agent::ServerlessHandlerEventSources.to_hash

      def self.env_var_set?
        ENV.key?(LAMBDA_ENVIRONMENT_VARIABLE)
      end

      def initialize
        @event = nil
        @context = nil
        @payloads = {}
      end

      def invoke_lambda_function_with_new_relic(event:, context:, method_name:, namespace: nil)
        NewRelic::Agent.increment_metric(SUPPORTABILITY_METRIC)

        @event, @context = event, context

        txn_name = function_name
        if ENV['NEW_RELIC_APM_LAMBDA_MODE'] == 'true'
          source = event_source_event_info['name']
          txn_name = "#{source} #{txn_name}" if source
        end

        NewRelic::Agent::Tracer.in_transaction(category: category, name: txn_name) do
          prep_transaction

          process_response(NewRelic::LanguageSupport.constantize(namespace)
            .send(method_name, event: event, context: context))
        end
      ensure
        harvest!
        write_output
        reset!
      end

      def store_payload(method, payload)
        return if METHOD_BLOCKLIST.include?(method)

        @payloads[method] = payload
      end

      def metric_data(stats_hash)
        payload = [nil,
          stats_hash.started_at,
          (stats_hash.harvested_at || Process.clock_gettime(Process::CLOCK_REALTIME)),
          []]
        stats_hash.each do |metric_spec, stats|
          next if stats.is_reset?

          hash = {name: metric_spec.name}
          hash[:scope] = metric_spec.scope unless metric_spec.scope.empty?

          payload.last.push([hash, [
            stats.call_count,
            stats.total_call_time,
            stats.total_exclusive_time,
            stats.min_call_time,
            stats.max_call_time,
            stats.sum_of_squares
          ]])
        end

        return if payload.last.empty?

        store_payload(:metric_data, payload)
      end

      def error_data(errors)
        store_payload(:error_data, [nil, errors.map(&:to_collector_array)])
      end

      private

      def prep_transaction
        process_api_gateway_info
        process_headers
        add_agent_attributes
      end

      def harvest!
        NewRelic::Agent.instance.harvest_and_send_analytic_event_data
        NewRelic::Agent.instance.harvest_and_send_custom_event_data
        NewRelic::Agent.instance.harvest_and_send_data_types
      end

      def metadata
        m = {arn: @context.invoked_function_arn,
             protocol_version: NewRelic::Agent::NewRelicService::PROTOCOL_VERSION,
             function_version: @context.function_version,
             execution_environment: EXECUTION_ENVIRONMENT,
             agent_version: NewRelic::VERSION::STRING}
        if PAYLOAD_VERSION >= 2
          m[:metadata_version] = PAYLOAD_VERSION
          m[:agent_language] = NewRelic::LANGUAGE
        end
        m
      end

      def function_name
        ENV.fetch(LAMBDA_ENVIRONMENT_VARIABLE, FUNCTION_NAME)
      end

      def category
        @category ||=
          @event&.dig('requestContext', 'http', 'method') || @event&.fetch('httpMethod', nil) ? :web : :other
      end

      def write_output
        string = PAYLOAD_VERSION == 1 ? payload_v1 : payload_v2

        return puts string unless use_named_pipe?

        File.write(NAMED_PIPE, string)

        NewRelic::Agent.logger.debug "Wrote serverless payload to #{NAMED_PIPE}\n" \
          "BEGIN PAYLOAD>>>\n#{string}\n<<<END PAYLOAD"
      end

      def payload_v1 # New Relic serverless payload v1
        payload_hash = {'metadata' => metadata, 'data' => @payloads}
        json = NewRelic::Agent.agent.service.marshaller.dump(payload_hash)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.strict_encode64(gzipped)
        array = [PAYLOAD_VERSION, LAMBDA_MARKER, base64_encoded]
        ::JSON.dump(array)
      end

      def payload_v2 # New Relic serverless payload v2
        json = NewRelic::Agent.agent.service.marshaller.dump(@payloads)
        gzipped = NewRelic::Agent::NewRelicService::Encoders::Compressed::Gzip.encode(json)
        base64_encoded = NewRelic::Base64.strict_encode64(gzipped)
        array = [PAYLOAD_VERSION, LAMBDA_MARKER, metadata, base64_encoded]
        ::JSON.dump(array)
      end

      def determine_api_gateway_version
        return unless @event

        version = @event.fetch('version', '')
        if version.start_with?('2.')
          return 2
        elsif version.start_with?('1.')
          return 1
        end

        headers = headers_from_event
        return unless headers

        if @event.dig('requestContext', 'http', 'path') && @event.dig('requestContext', 'http', 'method')
          2
        elsif @event.fetch('path', nil) && @event.fetch('httpMethod', nil)
          1
        end
      end

      def process_api_gateway_info
        api_v = determine_api_gateway_version
        return unless api_v

        info = api_v == 2 ? info_for_api_gateway_v2 : info_for_api_gateway_v1
        info[:query_parameters] = @event.fetch('queryStringParameters', nil)

        @http_method = info[:method]
        @http_uri = http_uri(info)
      end

      def http_uri(info)
        return unless info[:host] && info[:path]

        url_str = "https://#{info[:host]}"
        url_str += ":#{info[:port]}" unless info[:host].match?(':')
        url_str += "#{info[:path]}"

        if info[:query_parameters]
          qp = info[:query_parameters].map { |k, v| "#{k}=#{v}" }.join('&')
          url_str += "?#{qp}"
        end

        URI.parse(url_str)
      rescue StandardError => e
        NewRelic::Agent.logger.error "ServerlessHandler failed to parse the source HTTP URI: #{e}"
      end

      def info_for_api_gateway_v2
        ctx = @event.fetch('requestContext', nil)
        return {} unless ctx

        {method: ctx.dig('http', 'method'),
         path: ctx.dig('http', 'path'),
         host: ctx.fetch('domainName', @event.dig('headers', 'Host')),
         port: @event.dig('headers', 'X-Forwarded-Port') || 443}
      end

      def info_for_api_gateway_v1
        headers = headers_from_event
        {method: @event.fetch('httpMethod', nil),
         path: @event.fetch('path', nil),
         host: headers.fetch('Host', nil),
         port: headers.fetch('X-Forwarded-Port', 443)}
      end

      def process_headers
        return unless ::NewRelic::Agent.config[:'distributed_tracing.enabled']

        headers = headers_from_event
        return unless headers && !headers.empty?

        dt_headers = headers.fetch(NewRelic::NEWRELIC_KEY, nil)
        return unless dt_headers

        ::NewRelic::Agent::DistributedTracing::accept_distributed_trace_headers(dt_headers, 'Other')
      end

      def headers_from_event
        @headers ||= @event&.dig('requestContext', 'http') || @event&.dig('headers')
      end

      def use_named_pipe?
        return @use_named_pipe if defined?(@use_named_pipe)

        @use_named_pipe = File.exist?(NAMED_PIPE) && File.writable?(NAMED_PIPE)
      end

      def add_agent_attributes
        return unless NewRelic::Agent::Tracer.current_transaction

        add_agent_attribute('aws.lambda.coldStart', true) if cold?
        add_agent_attribute('aws.lambda.arn', @context.invoked_function_arn)
        add_agent_attribute('aws.requestId', @context.aws_request_id)

        add_event_source_attributes
        add_http_attributes if api_gateway_event?
      end

      def add_http_attributes
        return unless category == :web

        if @http_uri
          add_agent_attribute('uri.host', @http_uri.host)
          add_agent_attribute('uri.port', @http_uri.port)
          if NewRelic::Agent.instance.attribute_filter.allows_key?('http.url', AttributeFilter::DST_SPAN_EVENTS)
            add_agent_attribute('http.url', @http_uri.to_s)
          end
        end

        if @http_method
          add_agent_attribute('http.method', @http_method)
          add_agent_attribute('http.request.method', @http_method)
        end
      end

      def api_gateway_event?
        return false unless @event

        # '1.0' for API Gateway V1, '2.0' for API Gateway V2
        return true if @event.fetch('version', '').start_with?(DIGIT)

        return false unless headers_from_event

        # API Gateway V1 - look for toplevel 'path' and 'httpMethod' keys if a version is unset
        return true if @event.fetch('path', nil) && @event.fetch('httpMethod', nil)

        # API Gateway V2 - look for 'requestContext/http' inner nested 'path' and 'method' keys if a version is unset
        return true if @event.dig('requestContext', 'http', 'path') && @event.dig('requestContext', 'http', 'method')

        false
      end

      def add_event_source_attributes
        arn = event_source_arn
        add_agent_attribute('aws.lambda.eventSource.arn', arn) if arn

        info = event_source_event_info
        return unless info

        add_agent_attribute('aws.lambda.eventSource.eventType', info['name'])

        info['attributes'].each do |name, elements|
          next if elements.empty?

          size = false
          if elements.last.eql?('#size')
            elements = elements.dup
            elements.pop
            size = true
          end
          value = @event.dig(*elements)
          value = value.size if size
          next unless value

          add_agent_attribute(name, value)
        end
      end

      def event_source_arn
        return unless @event

        # SQS/Kinesis Stream/DynamoDB/CodeCommit/S3/SNS
        return event_source_arn_for_records if @event.fetch('Records', nil)

        # Kinesis Firehose
        ds_arn = @event.fetch('deliveryStreamArn', nil) if @event.fetch('records', nil)
        return ds_arn if ds_arn

        # ELB
        elb_arn = @event.dig('requestContext', 'elb', 'targetGroupArn')
        return elb_arn if elb_arn

        # (other)
        es_arn = @event.dig('resources', 0)
        return es_arn if es_arn

        NewRelic::Agent.logger.debug 'Unable to determine an event source arn'

        nil
      end

      def event_source_event_info
        return unless @event

        # if every required key for a source is found, consider that source
        # to be a match
        EVENT_SOURCES.each_value do |info|
          return info unless info['required_keys'].detect { |r| @event.dig(*r).nil? }
        end

        nil
      end

      def event_source_arn_for_records
        record = @event['Records'].first
        unless record
          NewRelic::Agent.logger.debug "Unable to find any records in the event's 'Records' array"
          return
        end

        arn = record.fetch('eventSourceARN', nil) || # SQS/Kinesis Stream/DynamoDB/CodeCommit
          record.dig('s3', 'bucket', 'arn') || # S3
          record.fetch('EventSubscriptionArn', nil) # SNS

        unless arn
          NewRelic::Agent.logger.debug "Unable to determine an event source arn from the event's 'Records' array"
        end

        arn
      end

      def add_agent_attribute(attribute, value)
        NewRelic::Agent::Tracer.current_transaction.add_agent_attribute(attribute, value, AGENT_ATTRIBUTE_DESTINATIONS)
      end

      def process_response(response)
        return response unless category == :web && response.respond_to?(:fetch)

        http_status = response.fetch(:statusCode, response.fetch('statusCode', nil))
        return unless http_status

        add_agent_attribute('http.statusCode', http_status)

        response
      end

      def cold?
        return @cold if defined?(@cold)

        @cold = false
        true
      end

      def reset!
        @event = nil
        @category = nil
        @context = nil
        @headers = nil
        @http_method = nil
        @http_uri = nil
        @payloads.replace({})
      end
    end
  end
end
