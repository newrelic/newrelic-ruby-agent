# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.join(File.dirname(__FILE__), '..', '..', '..', 'new_relic', 'marshalling_test_cases')

# This is intended as a sanity check for our serialization to JSON via the
# json gem across various Ruby versions.
class JsonTest < Minitest::Test

  include MultiverseHelpers
  include MarshallingTestCases

  setup_and_teardown_agent

end
