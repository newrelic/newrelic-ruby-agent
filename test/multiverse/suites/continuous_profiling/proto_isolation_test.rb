# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Google::Protobuf::DescriptorPool isn't loadable in the unit suite, hence this suite.
require 'google/protobuf/descriptor_pb'
require 'new_relic/agent/continuous_profiling/profile_encoder'

# The vendored protos are rewritten into a New Relic package so they claim neither the
# opentelemetry.* descriptor symbols nor the opentelemetry/... descriptor file names. Both are
# process-wide: an opentelemetry-* gem registering a file name the agent already claimed raises
# "duplicate file name" and fails to load.
class ProtoIsolationTest < Minitest::Test
  PROTO = NewRelic::Agent::ContinuousProfiling::Proto
  PACKAGE = 'new_relic.agent.continuous_profiling.proto'

  UPSTREAM_SYMBOLS = %w[
    opentelemetry.proto.common.v1.AnyValue
    opentelemetry.proto.common.v1.KeyValue
    opentelemetry.proto.resource.v1.Resource
    opentelemetry.proto.profiles.v1development.ProfilesDictionary
    opentelemetry.proto.collector.profiles.v1development.ExportProfilesServiceRequest
  ].freeze

  UPSTREAM_FILES = %w[
    opentelemetry/proto/common/v1/common.proto
    opentelemetry/proto/resource/v1/resource.proto
    opentelemetry/proto/profiles/v1development/profiles.proto
    opentelemetry/proto/collector/profiles/v1development/profiles_service.proto
  ].freeze

  def generated
    Google::Protobuf::DescriptorPool.generated_pool
  end

  def test_the_vendored_schema_registers_under_the_new_relic_package
    %w[AnyValue KeyValue Resource ProfilesDictionary ExportProfilesServiceRequest].each do |message|
      refute_nil generated.lookup("#{PACKAGE}.#{message}"), "#{message} is not registered under #{PACKAGE}"
    end
  end

  def test_the_agent_claims_no_opentelemetry_descriptor_symbols
    UPSTREAM_SYMBOLS.each do |name|
      assert_nil generated.lookup(name),
        "the agent registered #{name}, which an opentelemetry-* gem expects to own"
    end
  end

  def test_the_agent_defines_no_global_opentelemetry_constant
    refute defined?(::Opentelemetry),
      'the agent defined a global Opentelemetry constant, which the opentelemetry-* gems also assign'

    assert_operator PROTO::AnyValue.name, :start_with?, 'NewRelic::Agent::ContinuousProfiling::Proto::'
  end

  # The regression this rename exists to prevent.
  def test_another_gem_can_still_register_the_upstream_proto_files
    UPSTREAM_FILES.each do |filename|
      generated.add_serialized_file(foreign_descriptor_data(filename, 'opentelemetry.proto.vendored'))
    rescue Google::Protobuf::TypeError => e
      flunk("the agent claimed #{filename} in the process-wide pool, so a gem vendoring the same " \
            "OpenTelemetry proto can no longer load it: #{e.message}")
    end
  end

  # Renaming the package must not move anything on the wire. Encodes the same values against a
  # minimal hand-built copy of upstream's schema -- upstream package, upstream file name, upstream
  # field numbers -- and requires the bytes to match ours exactly.
  def test_encoded_bytes_are_identical_to_the_upstream_schema
    upstream = upstream_pool
    u_request = upstream.lookup('opentelemetry.proto.collector.profiles.v1development.ExportProfilesServiceRequest').msgclass
    u_rp = upstream.lookup('opentelemetry.proto.profiles.v1development.ResourceProfiles').msgclass
    u_resource = upstream.lookup('opentelemetry.proto.resource.v1.Resource').msgclass
    u_kv = upstream.lookup('opentelemetry.proto.common.v1.KeyValue').msgclass
    u_any = upstream.lookup('opentelemetry.proto.common.v1.AnyValue').msgclass

    theirs = u_request.new(resource_profiles: [u_rp.new(resource: u_resource.new(attributes: [
      u_kv.new(key: 'service.name', value: u_any.new(string_value: 'wire-check')),
      u_kv.new(key: 'entity.guid', value: u_any.new(string_value: 'GUID-123'))
    ]))])

    ours = PROTO::ExportProfilesServiceRequest.new(resource_profiles: [PROTO::ResourceProfiles.new(
      resource: PROTO::Resource.new(attributes: [
        PROTO::KeyValue.new(key: 'service.name', value: PROTO::AnyValue.new(string_value: 'wire-check')),
        PROTO::KeyValue.new(key: 'entity.guid', value: PROTO::AnyValue.new(string_value: 'GUID-123'))
      ])
    )])

    assert_equal u_request.encode(theirs),
      PROTO::ExportProfilesServiceRequest.encode(ours),
      'the renamed package changed the encoded bytes, so exported profiles would no longer match OTLP'
  end

  # Stands in for another gem's copy of the same proto file: same file name, different contents.
  # Only the file name and symbol names matter to the pool.
  def foreign_descriptor_data(filename, package)
    Google::Protobuf::FileDescriptorProto.encode(
      Google::Protobuf::FileDescriptorProto.new(
        name: filename,
        package: package,
        syntax: 'proto3',
        message_type: [Google::Protobuf::DescriptorProto.new(name: "M#{filename.hash.abs}")]
      )
    )
  end

  # Upstream's field numbering for just the chain the wire test encodes.
  def upstream_pool
    field = lambda do |name, number, type, type_name: nil, repeated: false|
      Google::Protobuf::FieldDescriptorProto.new(
        name: name, number: number, type: type, type_name: type_name,
        label: repeated ? :LABEL_REPEATED : :LABEL_OPTIONAL
      )
    end

    common = Google::Protobuf::FileDescriptorProto.new(
      name: 'upstream/common.proto', package: 'opentelemetry.proto.common.v1', syntax: 'proto3',
      message_type: [
        Google::Protobuf::DescriptorProto.new(name: 'AnyValue',
          field: [field.call('string_value', 1, :TYPE_STRING)]),
        Google::Protobuf::DescriptorProto.new(name: 'KeyValue', field: [
          field.call('key', 1, :TYPE_STRING),
          field.call('value', 2, :TYPE_MESSAGE, type_name: '.opentelemetry.proto.common.v1.AnyValue')
        ])
      ]
    )
    resource = Google::Protobuf::FileDescriptorProto.new(
      name: 'upstream/resource.proto', package: 'opentelemetry.proto.resource.v1', syntax: 'proto3',
      dependency: ['upstream/common.proto'],
      message_type: [Google::Protobuf::DescriptorProto.new(name: 'Resource', field: [
        field.call('attributes', 1, :TYPE_MESSAGE, type_name: '.opentelemetry.proto.common.v1.KeyValue', repeated: true)
      ])]
    )
    profiles = Google::Protobuf::FileDescriptorProto.new(
      name: 'upstream/profiles.proto', package: 'opentelemetry.proto.profiles.v1development', syntax: 'proto3',
      dependency: ['upstream/resource.proto'],
      message_type: [Google::Protobuf::DescriptorProto.new(name: 'ResourceProfiles', field: [
        field.call('resource', 1, :TYPE_MESSAGE, type_name: '.opentelemetry.proto.resource.v1.Resource')
      ])]
    )
    service = Google::Protobuf::FileDescriptorProto.new(
      name: 'upstream/profiles_service.proto', package: 'opentelemetry.proto.collector.profiles.v1development',
      syntax: 'proto3', dependency: ['upstream/profiles.proto'],
      message_type: [Google::Protobuf::DescriptorProto.new(name: 'ExportProfilesServiceRequest', field: [
        field.call('resource_profiles', 1, :TYPE_MESSAGE,
          type_name: '.opentelemetry.proto.profiles.v1development.ResourceProfiles', repeated: true)
      ])]
    )

    Google::Protobuf::DescriptorPool.new.tap do |pool|
      [common, resource, profiles, service].each do |file|
        pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file))
      end
    end
  end
end
