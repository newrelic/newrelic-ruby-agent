# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path('../../../test_helper', __FILE__)
require 'net/http'

module NewRelic
  module Agent
    class CollectorResponseCodeTest < Minitest::Test
      def setup
        @agent = NewRelic::Agent::Agent.new
        @errors = ["e1", "e2"]
      end

      def stub_service response
        conn = stub("http_connection", request: response)
        @agent.service.stubs(:http_connection).returns(conn)
      end

      def self.check_discards *response_codes
        response_codes.each do |response_code|
          define_method "test_#{response_code}_discards" do
            klass = Net::HTTPResponse::CODE_TO_OBJ[response_code.to_s]

            stub_service klass.new('1.1', response_code, 'Trash it')

            @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
            assert_empty @agent.error_collector.error_trace_aggregator.instance_variable_get(:@errors)

            @agent.send :harvest_and_send_errors
          end
        end
      end

      def self.check_merges *response_codes
        response_codes.each do |response_code|
          define_method "test_#{response_code}_merges" do
            klass = Net::HTTPResponse::CODE_TO_OBJ[response_code.to_s]

            stub_service klass.new('1.1', response_code, 'Keep it')

            @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
            @agent.error_collector.error_trace_aggregator.expects(:merge!).with(@errors)

            @agent.send :harvest_and_send_errors
          end
        end
      end

      def self.check_restarts *response_codes
        response_codes.each do |response_code|
          define_method "test_#{response_code}_restarts" do
            klass = Net::HTTPResponse::CODE_TO_OBJ[response_code.to_s]

            stub_service klass.new('1.1', response_code, 'Try again')

            # The error-handling code in agent.rb calls `retry`; rather
            # than testing it directly, we'll just assert that our service
            # call raises the right exception.
            #
            assert_raises(NewRelic::Agent::ForceRestartException) do
              @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
              @agent.send :harvest_and_send_errors
            end
          end
        end
      end

      def self.check_disconnects *response_codes
        response_codes.each do |response_code|
          define_method "test_#{response_code}_disconnects" do
            klass = Net::HTTPResponse::CODE_TO_OBJ[response_code.to_s]

            stub_service klass.new('1.1', klass, 'Go away')

            @agent.error_collector.error_trace_aggregator.expects(:harvest!).returns(@errors)
            @agent.expects(:disconnect)

            @agent.send(:catch_errors) do
              @agent.send :harvest_and_send_errors
            end
          end
        end
      end

      check_discards 400, 403, 404, 405, 407, 411, 413, 414, 415, 417, 431, 406  # 406 is unexpected

      check_merges 408, 429, 500, 503

      check_restarts 401, 409

      check_disconnects 410
    end
  end
end
