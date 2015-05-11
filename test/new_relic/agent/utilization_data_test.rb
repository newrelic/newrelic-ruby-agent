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
      define_method("test_#{test_case['testname'].gsub(/\W/, "_")}") do

        Net::HTTP.stubs(:get).with(URI(test_case['uri'])).returns(test_case['response'])
        utilization_data = NewRelic::Agent::UtilizationData.new
        assert_equal test_case['expected'], utilization_data.instance_type

        if test_case['metric']
          test_case['metric'].each_pair do |metric_name, incoming_attributes|
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
  end
end
