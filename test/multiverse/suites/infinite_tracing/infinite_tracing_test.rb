# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

INFINITE_TRACING_TEST_PATH = File.expand_path('../../../../infinite_tracing/test')
$LOAD_PATH.unshift INFINITE_TRACING_TEST_PATH

require 'test_helper'

if NewRelic::Agent::InfiniteTracing::Config.should_load?

  class InfiniteTracingTest < Minitest::Test

    def self.load_test_files pattern
      Dir.glob(File.join(INFINITE_TRACING_TEST_PATH, pattern)).each{ |fn| require fn }
    end

    load_test_files '*_test.rb'
    load_test_files '**/*_test.rb'

    def test_ok
      true
    end
  end

else
  puts "Skipping tests in #{__FILE__} because Infinite Tracing is not configured to load"
end