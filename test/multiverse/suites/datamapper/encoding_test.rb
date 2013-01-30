# https://support.newrelic.com/tickets/2101
# https://github.com/newrelic/rpm/pull/42
# https://github.com/newrelic/rpm/pull/45
require 'test/unit'
require 'new_relic/agent/instrumentation/data_mapper'

class DatabaseAdapter
  # we patch in here
  def log(*args)
  end
  include ::NewRelic::Agent::Instrumentation::DataMapperInstrumentation
end

class EncodingTest < Test::Unit::TestCase
  # datamapper wants a msg object
  MSG = Object.new
  def MSG.query
    # Contains invalid UTF8 Byte
    q = "select ICS95095010000000000083320000BS01030000004100+\xFF00000000000000000"
    if RUBY_VERSION >= '1.9'
      # Force the query to an invalid encoding
      q.force_encoding 'UTF-8'
    end
    q
  end
  def MSG.duration; 1.0; end

  def test_should_not_bomb_out_if_a_query_is_in_an_invalid_encoding
    if RUBY_VERSION >= '1.9'
      assert_equal false, MSG.query.valid_encoding?
    end
    db = DatabaseAdapter.new
    db.send(:log, MSG)
  end
end

