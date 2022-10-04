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
      # add a config option to collect paramters or not
      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: OPERATION,
        host: host,
        port_path_or_id: path || port,
        database_name: cluster_name # do we need to get this every time, or will it stay the same?
      )
      begin
        obfuscated_params = NewRelic::Agent::Datastores::NosqlObfuscator.obfuscate_statement(params)
        obfuscated_body = NewRelic::Agent::Datastores::NosqlObfuscator.obfuscate_statement(body)
        response = nil

        NewRelic::Agent::Tracer.capture_segment_error(segment) { response = yield }

        response
      ensure
        add_attributes(segment, params: obfuscated_params, body: obfuscated_body, method: method)
        segment.finish if segment
      end
    end

    private

    def add_attributes(segment, attributes_hash)
      return unless segment

      attributes_hash.each do |attr, value|
        segment.add_agent_attribute(attr, value)
      end
      segment.record_agent_attributes = true
    end

    def cluster_name
      NewRelic::Agent.disable_all_tracing { cluster.stats['cluster_name'] }
    end

    def hosts
      (transport.hosts.first || NewRelic::EMPTY_HASH)
    end

    def host
      hosts[:host]
    end

    def port
      hosts[:port]
    end
  end
end
