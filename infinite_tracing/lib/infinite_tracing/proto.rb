# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require 'grpc'
require 'google/protobuf'

require_relative 'proto/infinite_tracing_pb'
require_relative 'proto/infinite_tracing_services_pb'

# Mapping gRPC namespaced classes into New Relic's
module NewRelic::Agent::InfiniteTracing
  Span = Com::Newrelic::Trace::V1::Span
  SpanBatch = Com::Newrelic::Trace::V1::SpanBatch
  AttributeValue = Com::Newrelic::Trace::V1::AttributeValue
  RecordStatus = Com::Newrelic::Trace::V1::RecordStatus
end
