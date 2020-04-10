# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'grpc'
require 'google/protobuf'

require_relative 'proto/infinite_tracing_pb'
require_relative 'proto/infinite_tracing_services_pb'