# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

# This is the problematic thing that overrides our JSON marshalling
require 'yajl/json_gem'

class YajlTest < Minitest::Test

  include MultiverseHelpers
  include MarshallingTestCases

  setup_and_teardown_agent do
    Yajl::Encoder.expects(:encode).never
  end
end
