# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true
require_relative '../../datastores/nosql_obfuscator'

module NewRelic::Agent::Instrumentation
  module Elasticsearch
    PRODUCT_NAME = 'Elasticsearch'
    OPERATION = 'query'

    def perform_request_with_tracing(method, path, params = {}, body = nil, headers = nil)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?
      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: OPERATION,
        host: nr_hosts[:host],
        port_path_or_id: path,
        database_name: nr_cluster_name
      )
      begin
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment.notice_nosql_statement(nr_reported_query(body || params))
        segment.finish if segment
      end
    end

    private

    def nr_reported_query(query)
      return unless NewRelic::Agent.config[:'elasticsearch.capture_queries']
      return query unless NewRelic::Agent.config[:'elasticsearch.obfuscate_queries']

      NewRelic::Agent::Datastores::NosqlObfuscator.obfuscate_statement(query)
    end

    def nr_cluster_name
      return @nr_cluster_name if @nr_cluster_name
      return NewRelic::EMPTY_STRING if nr_hosts.empty?

      NewRelic::Agent.disable_all_tracing do
        url = "#{nr_hosts[:protocol]}://#{nr_hosts[:host]}:#{nr_hosts[:port]}"
        response = JSON.parse(Net::HTTP.get(URI(url)))
        @nr_cluster_name ||= response["cluster_name"]
      end
    rescue => e
      NewRelic::Agent.logger.error("Failed to get cluster name for elasticsearch", e)
      NewRelic::EMPTY_STRING
    end

    def nr_hosts
      @nr_hosts ||= (transport.hosts.first || NewRelic::EMPTY_HASH)
    end
  end
end
