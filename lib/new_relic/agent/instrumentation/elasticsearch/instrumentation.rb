# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Elasticsearch
    PRODUCT_NAME = 'Elasticsearch'
    OPERATION = 'query'

    def perform_request_with_tracing(method, path, params = {}, body = nil, headers = nil)
      return yield unless NewRelic::Agent::Tracer.tracing_enabled?

      # args = method, path, params = {}, body = nil
      # does updating your indicies hit perform_request?
      segment = NewRelic::Agent::Tracer.start_datastore_segment(
        product: PRODUCT_NAME,
        operation: OPERATION, # this should be in the params.. params ex: {:q=>"genesis"}
        host: host,
        port_path_or_id: path || port,
        database_name: cluster_name # do we need to get this every time, or will it stay the same
      )
      begin
        # add attributes for all method args?
        # right now, no query data/arguments are preserved

        response = nil
        NewRelic::Agent::Tracer.capture_segment_error(segment) { response = yield }
        # binding.irb

        response
      ensure
        segment.finish if segment
      end
    end

    private

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
