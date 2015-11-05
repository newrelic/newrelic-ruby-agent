# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require 'new_relic/agent/aws_info'

module NewRelic::Agent
  class AWSInfoTest < Minitest::Test

    def setup
      NewRelic::Agent.drop_buffered_data
    end

    test_cases = load_cross_agent_test("aws")
    test_cases.each do |test_case|
      testname, uris, expected_vendors_hash, expected_metrics = test_case.values_at 'testname', 'uris', 'expected_vendors_hash', 'expected_metrics'

      define_method("test_#{testname.gsub(/\W/, "_")}") do
        stub_responses(uris)
        assert_valid_vendors_hash(expected_vendors_hash)
        assert_metrics_recorded(expected_metrics) if expected_metrics
      end
    end

    def test_assert_logging_with_invalid_data
      Net::HTTP.stubs(:get).returns("j" * 1000)

      NewRelic::Agent.logger.stubs(:debug)
      NewRelic::Agent.logger.expects(:debug).with(anything)

      AWSInfo.new
    end

    def method_from_uri(uri)
      uri.split("/").last.tr("-", "_")
    end

    def stub_responses(uris)
      uris.each_pair do |uri, attrs|
        if attrs['timeout']
          Net::HTTP.stubs(:get).with(URI(uri)).raises(Timeout::Error)
        else
          Net::HTTP.stubs(:get).with(URI(uri)).returns(attrs['response'])
        end
      end
    end

    def assert_valid_vendors_hash(expected_vendors_hash)
      aws_info = AWSInfo.new

      if expected_vendors_hash.nil?
        refute aws_info.loaded?
      else
        actual = HashExtensions.stringify_keys_in_object(aws_info.to_collector_hash)
        assert_equal expected_vendors_hash["aws"], actual
      end
    end
  end
end
