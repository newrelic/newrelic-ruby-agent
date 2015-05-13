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
      testname, uris, metric = test_case.values_at 'testname', 'uris', 'metric'

      define_method("test_#{testname.gsub(/\W/, "_")}") do

        stub_responses(uris)
        assert_valid_responses(uris)
        assert_valid_metrics(metric) if metric
      end
    end

    METHOD_LOOKUP = {
      "callCount" => :call_count
    }

    def translate_method_name(method_name)
      METHOD_LOOKUP[method_name]
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

    def assert_valid_responses(uris)
      aws_info = AWSInfo.new

      uris.each_pair.each do |uri, attrs|
        result = aws_info.send(method_from_uri(uri))
        assert_equal attrs['expected'], result
      end
    end

    def assert_valid_metrics(metric)
      metric.each_pair do |metric_name, incoming_attributes|
        expected_attributes = incoming_attributes.inject({}) do |memo, (k,v)|
          memo[translate_method_name(k)] = v
          memo
        end

        assert_metrics_recorded(metric_name => expected_attributes)
      end
    end
  end
end