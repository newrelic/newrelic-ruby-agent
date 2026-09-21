# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Google::Protobuf::DescriptorPool isn't loadable in the unit suite, hence this suite.
require 'google/protobuf/descriptor_pb'
require 'new_relic/agent/continuous_profiling/proto/registrar'

class RegistrarTest < Minitest::Test
  def test_register_once_registers_a_new_file
    pool = Google::Protobuf::DescriptorPool.new
    descriptor_data = build_descriptor_data('registrar_test_one.proto', 'MessageOne')

    NewRelic::Agent::ContinuousProfiling::Proto::Registrar.register_once(
      pool, descriptor_data, 'registrar_test.MessageOne'
    )

    refute_nil pool.lookup('registrar_test.MessageOne')
  end

  def test_register_once_is_a_no_op_when_the_anchor_message_is_already_registered
    pool = Google::Protobuf::DescriptorPool.new
    descriptor_data = build_descriptor_data('registrar_test_two.proto', 'MessageTwo')
    NewRelic::Agent::ContinuousProfiling::Proto::Registrar.register_once(
      pool, descriptor_data, 'registrar_test.MessageTwo'
    )

    NewRelic::Agent::ContinuousProfiling::Proto::Registrar.register_once(
      pool, descriptor_data, 'registrar_test.MessageTwo'
    )

    refute_nil pool.lookup('registrar_test.MessageTwo')
  end

  # The lookup is slowed deliberately to force the overlap an unserialized lookup-then-add loses.
  def test_register_once_serializes_the_lookup_and_the_add
    added = []
    slow_pool = Object.new
    slow_pool.define_singleton_method(:lookup) do |_name|
      sleep(0.05)
      added.first
    end
    slow_pool.define_singleton_method(:add_serialized_file) { |data| added << data }

    threads = Array.new(2) do
      Thread.new do
        NewRelic::Agent::ContinuousProfiling::Proto::Registrar.register_once(
          slow_pool, 'descriptor-data', 'registrar_test.MessageThree'
        )
      end
    end
    threads.each { |thread| thread.join(5) }

    assert_equal ['descriptor-data'], added
  end

  def test_incompatible_messages_is_empty_for_the_vendored_schema
    require 'new_relic/agent/continuous_profiling/profile_encoder'

    assert_empty NewRelic::Agent::ContinuousProfiling::Proto::Registrar.incompatible_messages
  end

  # Only the v1development messages: the common and resource protos the encoder also builds are
  # from stable packages, which is what the instability comment on REQUIRED_FIELDS is about.
  def test_required_fields_covers_every_v1development_message_the_encoder_builds
    require 'new_relic/agent/continuous_profiling/profile_encoder'
    packages = {
      'PROFILES' => 'opentelemetry.proto.profiles.v1development',
      'COLLECTOR' => 'opentelemetry.proto.collector.profiles.v1development'
    }
    encoder_source = File.read(
      NewRelic::Agent::ContinuousProfiling::ProfileEncoder.instance_method(:encode).source_location.first
    )
    built = encoder_source.scan(/OTEL_(PROFILES|COLLECTOR)::(\w+)\.new/).map do |namespace, message|
      "#{packages[namespace]}.#{message}"
    end

    assert_empty(
      built.uniq - NewRelic::Agent::ContinuousProfiling::Proto::Registrar::REQUIRED_FIELDS.keys,
      'ProfileEncoder builds messages that Registrar::REQUIRED_FIELDS does not check'
    )
  end

  def test_incompatible_messages_reports_a_message_that_is_not_registered
    incompatible = NewRelic::Agent::ContinuousProfiling::Proto::Registrar.incompatible_messages(
      Google::Protobuf::DescriptorPool.new
    )

    assert_equal(
      NewRelic::Agent::ContinuousProfiling::Proto::Registrar::REQUIRED_FIELDS.length,
      incompatible.length
    )
    assert(incompatible.all? { |reason| reason.end_with?('is not registered') })
  end

  def test_incompatible_messages_reports_the_fields_a_foreign_revision_is_missing
    pool = Google::Protobuf::DescriptorPool.new
    pool.add_serialized_file(
      build_descriptor_data('stale_stack.proto', 'Stack', package: 'opentelemetry.proto.profiles.v1development')
    )

    incompatible = NewRelic::Agent::ContinuousProfiling::Proto::Registrar.incompatible_messages(pool)

    assert_includes incompatible,
      'opentelemetry.proto.profiles.v1development.Stack is missing location_indices'
  end

  def build_descriptor_data(filename, message_name, package: 'registrar_test')
    file = Google::Protobuf::FileDescriptorProto.new(
      name: filename,
      package: package,
      syntax: 'proto3',
      message_type: [Google::Protobuf::DescriptorProto.new(name: message_name)]
    )
    Google::Protobuf::FileDescriptorProto.encode(file)
  end
end
