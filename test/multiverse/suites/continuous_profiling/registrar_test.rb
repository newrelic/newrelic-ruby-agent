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
