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
        Net::HTTP.stubs(:get).with(URI(uri)).returns(attrs['response'])
      end
    end

    def assert_valid_responses(uris)
      aws_info = AWSInfo.new
      aws_info.load_remote_data

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

    # def test_nothing_is_loaded_when_initialized
    #   aws_info = AWSInfo.new
    #   refute aws_info.loaded?, "Expected loaded? to be false"
    #   assert_nil aws_info.instance_type
    #   assert_nil aws_info.instance_id
    #   assert_nil aws_info.availability_zone
    # end

    # def test_attributes_are_populated_when_all_requests_succeed
    #   Net::HTTP.stubs(:get).with(URI('http://169.254.169.254/2008-02-01/meta-data/instance-type')).returns('test.type')
    #   Net::HTTP.stubs(:get).with(URI('http://169.254.169.254/2008-02-01/meta-data/instance-id')).returns('test.id')
    #   Net::HTTP.stubs(:get).with(URI('http://169.254.169.254/2008-02-01/meta-data/placement/availability-zone')).returns('us-west-2b')

    #   aws_info = AWSInfo.new
    #   aws_info.load_remote_data

    #   assert aws_info.loaded?, "Expected loaded? to be true"
    #   assert_equal "test.type", aws_info.instance_type
    #   assert_equal "test.id", aws_info.instance_id
    #   assert_equal "us-west-2b", aws_info.availability_zone
    # end

    # def test_no_attributes_are_populated_if_a_request_times_out
    #   Net::HTTP.stubs(:get).with(URI('http://169.254.169.254/2008-02-01/meta-data/instance-type')).returns('test.type')
    #   Net::HTTP.stubs(:get).with(URI('http://169.254.169.254/2008-02-01/meta-data/instance-id')).returns('test.id')
    #   Net::HTTP.stubs(:get).with(URI('http://169.254.169.254/2008-02-01/meta-data/placement/availability-zone')).raises(Timeout::Error)

    #   aws_info = AWSInfo.new
    #   aws_info.load_remote_data

    #   refute aws_info.loaded?, "Expected loaded? to be false"
    #   assert_nil aws_info.instance_type
    #   assert_nil aws_info.instance_id
    #   assert_nil aws_info.availability_zone
    # end
  end
end