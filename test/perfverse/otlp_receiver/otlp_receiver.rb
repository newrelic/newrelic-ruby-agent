#!/usr/bin/env ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Standalone local stand-in for the (not-yet-decided) real OTLP profiles destination, used by
# perfverse so performance runs never send real data externally. Runs as its own sidecar
# container (see Dockerfile in this directory) rather than inside the app container being
# measured, so docker_monitor's CPU/memory numbers for the app stay uncontaminated by this
# process. Listens over HTTPS with a self-signed cert (see test/perfverse/bin/generate-otlp-cert.sh),
# decodes each POST as a gzip'd ExportProfilesServiceRequest, and logs a summary.

require 'webrick'
require 'webrick/https'
require 'zlib'
require 'google/protobuf'

PROTO_DIR = File.join(__dir__, 'proto')

require File.join(PROTO_DIR, 'registrar')
require File.join(PROTO_DIR, 'opentelemetry/proto/common/v1/common_pb')
require File.join(PROTO_DIR, 'opentelemetry/proto/resource/v1/resource_pb')
require File.join(PROTO_DIR, 'opentelemetry/proto/profiles/v1development/profiles_pb')
require File.join(PROTO_DIR, 'opentelemetry/proto/collector/profiles/v1development/profiles_service_pb')

$stdout.sync = true

PORT = Integer(ENV.fetch('OTLP_RECEIVER_PORT', 4318))
CERT_PATH = File.join(__dir__, 'otlp_localhost.crt')
KEY_PATH = File.join(__dir__, 'otlp_localhost.key')

class ProfilesServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_POST(request, response)
    body = Zlib.gunzip(request.body)
    export_request = Opentelemetry::Proto::Collector::Profiles::V1development::ExportProfilesServiceRequest.decode(body)

    resource_profiles = export_request.resource_profiles
    sample_count = resource_profiles.sum { |rp| rp.scope_profiles.sum { |sp| sp.profiles.sum { |p| p.samples.size } } }

    puts "[#{Time.now}] Received export: #{resource_profiles.size} resource profile(s), " \
      "#{sample_count} sample(s) total, api-key=#{request['api-key'] ? 'present' : 'MISSING'}, " \
      "#{body.bytesize} bytes decoded (#{request.body.bytesize} gzipped)"

    response.status = 200
    response['Content-Type'] = 'application/x-protobuf'
    response.body = Opentelemetry::Proto::Collector::Profiles::V1development::ExportProfilesServiceResponse.new.to_proto
  rescue => e
    puts "[#{Time.now}] Failed to decode request: #{e.class}: #{e.message}"
    response.status = 400
  end
end

server = WEBrick::HTTPServer.new(
  Port: PORT,
  SSLEnable: true,
  SSLCertificate: OpenSSL::X509::Certificate.new(File.read(CERT_PATH)),
  SSLPrivateKey: OpenSSL::PKey::RSA.new(File.read(KEY_PATH))
)
server.mount('/v1/profiles', ProfilesServlet)

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }
puts "OTLP profiles receiver listening on https://0.0.0.0:#{PORT}/v1/profiles"
server.start
