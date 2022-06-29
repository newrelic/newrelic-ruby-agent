# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

module NewRelic
  module Agent
    module InfiniteTracing
      class ConfigTest < Minitest::Test
        include NewRelic::TestHelpers::FileSearching
        include NewRelic::TestHelpers::ConfigScanning

        def setup
          @default_keys = ::NewRelic::Agent::Configuration::DEFAULTS.keys
          @default_keys.delete_if do |key_name|
            NewRelic::Agent::Configuration::DEFAULTS[key_name][:external] != :infinite_tracing
          end
        end

        def test_all_infinite_tracing_config_keys_are_used
          scan_and_remove_used_entries @default_keys, non_test_files
          assert_empty @default_keys
        end

        def test_trace_observer_host_normalizes
          hostnames = [
            'example.com',
            'example.com:80',
            'example.com',
            'http://example.com',
            'https://example.com',
            'https://example.com:443'
          ]
          hostnames.each do |hostname|
            with_config(:'infinite_tracing.trace_observer.host' => hostname) do
              assert_equal "example.com", Config.trace_observer_host
            end
          end
        end

        def test_trace_observer_port_from_host_entry
          hostnames = [
            ['example.com', 443],
            ['example.com:80', 80],
            ['example.com', 443],
            ['http://example.com', 443],
            ['https://example.com', 443],
            ['https://example.com:80', 80]
          ]
          hostnames.each do |hostname, port|
            with_config(:'infinite_tracing.trace_observer.host' => hostname) do
              assert_equal port, Config.trace_observer_port, "expected #{port} for port using hostname: #{hostname}"
            end
          end
        end

        def test_trace_observer_port_overridden_by_port_from_host_entry
          hostnames = [
            ['example.com', 443],
            ['example.com:80', 80],
            ['example.com', 443],
            ['http://example.com', 443],
            ['https://example.com', 443],
            ['https://example.com:80', 80]
          ]
          hostnames.each do |hostname, port|
            config = {
              :'infinite_tracing.trace_observer.host' => hostname,
              :'infinite_tracing.trace_observer.port' => 443
            }
            with_config(config) do
              assert_equal port, Config.trace_observer_port, "expected #{port} for port because host overrides: #{hostname}"
            end
          end
        end

        def test_trace_observer_host_and_port
          hostnames = [
            ['example.com', 'example.com:443'],
            ['example.com:80', 'example.com:80'],
            ['example.com:443', 'example.com:443'],
            ['http://example.com', 'example.com:443'],
            ['https://example.com', 'example.com:443'],
            ['https://example.com:80', 'example.com:80']
          ]
          hostnames.each do |hostname, host_and_port|
            config = {
              :'infinite_tracing.trace_observer.host' => hostname
            }
            with_config(config) do
              assert_equal host_and_port,
                Config.trace_observer_host_and_port,
                "expected #{host_and_port.inspect} when host is: #{hostname.inspect}"
            end
          end
        end

        def test_unset_trace_observer_host_raises_error
          NewRelic::Agent.config.remove_config_type :yaml
          error = assert_raises RuntimeError do
            Config.trace_observer_uri
          end
          assert_match(/not configured/, error.message)
        end

        private

        def non_test_files
          all_rb_files.reject { |filename| filename.include? 'test.rb' }
        end
      end
    end
  end
end
