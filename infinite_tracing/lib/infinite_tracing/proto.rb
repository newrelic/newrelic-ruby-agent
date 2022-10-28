# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'base64'
require 'grpc'
require 'google/protobuf'
require 'zlib'

require_relative 'proto/infinite_tracing_pb'
require_relative 'proto/infinite_tracing_services_pb'

# Mapping gRPC namespaced classes into New Relic's
module NewRelic::Agent::InfiniteTracing
  Span = Com::Newrelic::Trace::V1::Span
  SpanBatch = Com::Newrelic::Trace::V1::SpanBatch
  AttributeValue = Com::Newrelic::Trace::V1::AttributeValue
  RecordStatus = Com::Newrelic::Trace::V1::RecordStatus
end

# Monkeypath IngestService to use custom encode/decode routines
class Com::Newrelic::Trace::V1::IngestService
  self.marshal_class_method = :nr_encode_gzip
  self.unmarshal_class_method = :nr_decode_gzip
end

# Define custom base64/gzip based encode/decode methods
module NrInfiniteTracingCoders
  def nr_decode_gzip(payload)
    Base64.decode64(Zlib.gunzip(self.class.decode(payload)))
  end

  def nr_encode_gzip(payload)
    Base64.encode64(Zlib.gzip(self.class.encode(payload)))
  end
end

# Bring the encode/decode methods into all protobug classes
module Com::Newrelic::Trace::V1
  class Span
    include NrInfiniteTracingCoders
  end

  class SpanBatch
    include NrInfiniteTracingCoders
  end

  class AttributeValue
    include NrInfiniteTracingCoders
  end

  class RecordStatus
    include NrInfiniteTracingCoders
  end
end
