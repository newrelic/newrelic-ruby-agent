# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class ChannelTest < Minitest::Test
        def local_config
          {
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => 'localhost:80'
          }
        end

        def remote_config
          {
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => 'https://example.com'
          }
        end

        def test_channel_is_secure_for_remote_host
          Config.stubs(:test_framework?).returns(false)

          with_config(remote_config) do
            channel = Channel.new
            credentials = channel.send(:credentials)

            assert_equal 'example.com:443', channel.send(:host_and_port)
            assert_kind_of GRPC::Core::ChannelCredentials, credentials
          end
        ensure
          Config.unstub(:test_framework?)
        end

        def test_channel_is_really_secure_for_remote_host
          Config.stubs(:test_framework?).returns(false)
          # HTTP instead of HTTPS...
          insecure_remote_config = remote_config.merge({
            :'infinite_tracing.trace_observer.host' => 'http://example.com'
          })

          with_config(insecure_remote_config) do
            channel = Channel.new
            credentials = channel.send(:credentials)

            assert_equal 'example.com:443', channel.send(:host_and_port)
            assert_kind_of GRPC::Core::ChannelCredentials, credentials
          end
        ensure
          Config.unstub(:test_framework?)
        end

        def test_channel_args_are_empty_if_compression_is_disabled
          reset_compression_level

          with_config(remote_config.merge('infinite_tracing.compression_level': :none)) do
            assert_equal NewRelic::EMPTY_HASH, Channel.new.channel_args
          end
        end

        def test_channel_args_includes_compression_settings_if_compression_is_enabled
          reset_compression_level

          level = :low
          expected_result = {'grpc.default_compression_level' => 1,
                             'grpc.default_compression_algorithm' => 2,
                             'grpc.compression_enabled_algorithms_bitset' => 7}

          with_config(remote_config.merge('infinite_tracing.compression_level': level)) do
            assert_equal expected_result, Channel.new.channel_args
          end
        end

        def test_settings_apply_minimal_stack_when_compression_is_disabled
          reset_compression_level

          with_config(remote_config.merge('infinite_tracing.compression_level': :none)) do
            assert_equal Channel::SETTINGS_COMPRESSION_DISABLED, Channel.new.settings
          end
        end

        def test_settings_do_not_apply_minimal_stack_when_compression_is_enabled
          reset_compression_level
          expected = Channel::SETTINGS_BASE.merge({'grpc.default_compression_level' => 3,
                                                   'grpc.default_compression_algorithm' => 2,
                                                   'grpc.compression_enabled_algorithms_bitset' => 7})

          assert_equal expected, Channel.new.settings
        end
      end
    end
  end
end
