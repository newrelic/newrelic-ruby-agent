# https://support.newrelic.com/tickets/2101
# https://github.com/newrelic/rpm/pull/42
# https://github.com/newrelic/rpm/pull/45
require 'new_relic/agent/instrumentation/active_record'

class DatabaseAdapter
  # we patch in here
  def log(*args)
  end
  include ::NewRelic::Agent::Instrumentation::ActiveRecord
end

class EncodingTest < Test::Unit::TestCase

  def test_should_not_bomb_out_if_a_query_is_in_an_invalid_encoding
    # Contains invalid UTF8 Byte
    query = "select ICS95095010000000000083320000BS01030000004100+\xFF00000000000000000"
    if RUBY_VERSION >= '1.9'
      # Force the query to an invalid encoding
      query.force_encoding 'UTF-8'
      assert_equal false, query.valid_encoding?
    end
    db = DatabaseAdapter.new
    db.send(:log, query)
  end
end
