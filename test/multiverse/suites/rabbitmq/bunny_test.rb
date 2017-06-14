# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class BunnyTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do
    @conn = Bunny.new
    @conn.start

    @chan = @conn.create_channel
    @queue  = @chan.queue("test1")
  end

  def test_something
    assert true
  end
end
