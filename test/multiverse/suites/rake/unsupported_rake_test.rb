# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path(File.join(__FILE__, '..', 'rake_test_helper'))

if !::NewRelic::Agent::Instrumentation::Rake.should_install?
  class UnsupportedRakeTest < Minitest::Test
    include MultiverseHelpers
    include RakeTestHelper

    setup_and_teardown_agent

    def test_we_hear_nothing
      run_rake
      refute_any_rake_metrics
    end
  end
end
