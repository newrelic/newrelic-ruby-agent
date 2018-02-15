# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))

module NewRelic::Agent
  class CollectorHostname < Minitest::Test

    test_cases = load_cross_agent_test("collector_hostname")

    test_cases.each do |test_case|
      define_method("test_#{test_case['name']}".tr(" ", "_")) do
        refute_equal test_case['hostname'], 'just kidding'
      end

    end

  end
end
