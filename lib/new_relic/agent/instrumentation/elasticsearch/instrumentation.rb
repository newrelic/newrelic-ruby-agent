# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Elasticsearch
    PRODUCT_NAME = 'Elasticsearch'
    OPERATION = 'query'

    def perform_request_with_tracing(*args)
      # args = method, path, params = {}, body = nil
      # does updating your indicies hit perform_request?
      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: OPERATION,
        host: host,
        port_path_or_id: port,
        database_name: cluster_name
      )
      begin
        # add attributes for all method args?
        # right now, no query data/arguments are preserved
        NewRelic::Agent::Tracer.capture_segment_error(segment) { yield }
      ensure
        segment.finish if segment
      end
    end

    private

    def cluster_name
      # this makes a call to perform_request, so not ideal
      cluster.stats['cluster_name']
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
