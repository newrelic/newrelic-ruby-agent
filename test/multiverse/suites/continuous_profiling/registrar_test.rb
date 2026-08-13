# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Exercises Registrar against the real `google-protobuf` gem -- Google::Protobuf::DescriptorPool
# isn't loadable in the main unit suite, hence the multiverse suite.
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

  # Simulates a second gem (e.g. opentelemetry-exporter-otlp) vendoring the same proto file --
  # calling pool.add_serialized_file directly a second time here would raise "duplicate file
  # name"; register_once must see the anchor message already registered and skip re-adding it.
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

  def build_descriptor_data(filename, message_name)
    file = Google::Protobuf::FileDescriptorProto.new(
      name: filename,
      package: 'registrar_test',
      syntax: 'proto3',
      message_type: [Google::Protobuf::DescriptorProto.new(name: message_name)]
    )
    Google::Protobuf::FileDescriptorProto.encode(file)
  end
end
