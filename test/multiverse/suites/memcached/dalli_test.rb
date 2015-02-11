# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(Dalli)
  class DalliTest < Minitest::Test
    include MemcacheTestCases

    def setup
      @cache = Dalli::Client.new("localhost:11211")
    end
  end
end