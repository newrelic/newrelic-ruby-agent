# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

require File.expand_path('../../../test_helper', __FILE__)

module NewRelic
  module Agent
    module InfiniteTracing
      class ChannelTest < Minitest::Test

        def local_config 
          { 
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => "localhost:80"
          }
        end

        def remote_config 
          { 
            :'distributed_tracing.enabled' => true,
            :'span_events.enabled' => true,
            :'infinite_tracing.trace_observer.host' => "https://example.com"
          }
        end

        def test_channel_is_insecure_for_local_host
          with_config local_config do
            channel = Channel.new
            credentials = channel.send(:credentials)
    
            assert_equal "localhost:80", channel.send(:host_and_port)
            assert_equal :this_channel_is_insecure, credentials
          end
        end

        def test_channel_is_secure_for_remote_host
          Config.stubs(:test_framework?).returns(false)

          with_config remote_config do
            channel = Channel.new
            credentials = channel.send(:credentials)
    
            assert_equal "example.com:443", channel.send(:host_and_port)
            assert_kind_of GRPC::Core::ChannelCredentials, credentials
          end

        ensure
          Config.unstub(:test_framework?)
        end

        def test_channel_is_really_secure_for_remote_host
          Config.stubs(:test_framework?).returns(false)
          # HTTP instead of HTTPS...
          insecure_remote_config = remote_config.merge({
            :'infinite_tracing.trace_observer.host' => "http://example.com"
          })

          with_config insecure_remote_config do
            channel = Channel.new
            credentials = channel.send(:credentials)
    
            assert_equal "example.com:443", channel.send(:host_and_port)
            assert_kind_of GRPC::Core::ChannelCredentials, credentials
          end

        ensure
          Config.unstub(:test_framework?)
        end

      end
    end
  end
end
