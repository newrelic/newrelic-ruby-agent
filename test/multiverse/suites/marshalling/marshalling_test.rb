# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

# These tests are intended to exercise the basic marshalling functionality of
# the agent in it's different permutations (Ruby and JSON)
class MarshallingTest < Minitest::Test

  include MultiverseHelpers
  include MarshallingTestCases

  setup_and_teardown_agent

end
