# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

module NewRelic::Agent
  class UtilizationDataTest < Minitest::Test
    def setup
      NewRelic::Agent.drop_buffered_data
    end

    test_cases = load_cross_agent_test("aws")
    test_cases.each do |test_case|
      testname, uri, response, metric, expected = test_case.values_at 'testname', 'uri', 'response', 'metric', 'expected'

      define_method("test_#{testname.gsub(/\W/, "_")}") do

        Net::HTTP.stubs(:get).with(URI(uri)).returns(response)
        utilization_data = NewRelic::Agent::UtilizationData.new
        assert_equal expected, utilization_data.send(method_from_uri(uri))

        if metric
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

    METHOD_LOOKUP = {
      "callCount" => :call_count
    }

    def translate_method_name(method_name)
      METHOD_LOOKUP[method_name]
    end

    def method_from_uri(uri)
      uri.split("/").last.tr("-", "_")
    end
  end
end
