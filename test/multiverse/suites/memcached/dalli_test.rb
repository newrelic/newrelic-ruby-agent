# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "./memcache_test_cases"

if defined?(Dalli)
  class DalliTest < Minitest::Test
    include MemcacheTestCases

    def setup
      @cache = Dalli::Client.new("127.0.0.1:11211", :socket_timeout => 2.0)
    end
  end
end