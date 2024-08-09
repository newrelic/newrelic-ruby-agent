# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module OpenSearch
    PRODUCT_NAME = 'OpenSearch'
    OPERATION = 'perform_request'
    OPERATION_PATTERN = %r{/lib/opensearch/api/(?!.+#{OPERATION})}
    INSTANCE_METHOD_PATTERN = /:in (?:`|')(?:.+#)?([^']+)'\z/
    INSTRUMENTATION_NAME = NewRelic::Agent.base_name(name)

    def perform_request_with_tracing(_method, _path, params = {}, body = nil, _headers = nil, _opts = {}, &_block)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: nr_operation || OPERATION,
        host: nr_hosts[:host],
        port_path_or_id: nr_hosts[:port],
        database_name: nr_cluster_name
      )
      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        if segment
          segment.notice_nosql_statement(nr_reported_query(body || params))
          segment.finish
        end
      end
    end

    private

    # See Elasticsearch instrumentation for explanation on Ruby 3.4 changes to match instance method
    def nr_operation
      location = caller_locations.detect { |loc| loc.to_s.match?(OPERATION_PATTERN) }
      return unless location && location.to_s =~ INSTANCE_METHOD_PATTERN

      Regexp.last_match(1)
    end

    def nr_reported_query(query)
      return unless NewRelic::Agent.config[:'opensearch.capture_queries']
      return query unless NewRelic::Agent.config[:'opensearch.obfuscate_queries']

      NewRelic::Agent::Datastores::NosqlObfuscator.obfuscate_statement(query)
    end

    def nr_cluster_name
      return @nr_cluster_name if defined?(@nr_cluster_name)
      return if nr_hosts.empty?

      NewRelic::Agent.disable_all_tracing do
        @nr_cluster_name ||= perform_request('GET', '/').body['cluster_name']
      end
    rescue StandardError => e
      NewRelic::Agent.logger.error('Failed to get cluster name for OpenSearch', e)
      nil
    end

    def nr_hosts
      @nr_hosts ||= (transport.hosts.first || NewRelic::EMPTY_HASH)
    end
  end
end
