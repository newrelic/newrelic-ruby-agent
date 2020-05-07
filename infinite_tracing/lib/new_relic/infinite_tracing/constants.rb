# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    module Constants
      SUPPORTABILITY_PREFIX = "Supportability/InfiniteTracing/Span"
      
      SPANS_SEEN_METRIC     = "#{SUPPORTABILITY_PREFIX}/Seen"
      SPANS_SENT_METRIC     = "#{SUPPORTABILITY_PREFIX}/Sent"
      QUEUE_DUMPED_METRIC   = "#{SUPPORTABILITY_PREFIX}/AgentQueueDumped"
      RESPONSE_ERROR_METRIC = "#{SUPPORTABILITY_PREFIX}/Response/Error"

      GRPC_ERROR_NAME       = "#{SUPPORTABILITY_PREFIX}/gRPC/%s"
      GRPC_OTHER_ERROR      = GRPC_ERROR_NAME % "Other"
    end
  end
end
