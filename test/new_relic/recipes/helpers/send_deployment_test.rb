# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require_relative '../../../../lib/new_relic/recipes/helpers/send_deployment'

module Newrelic
  class SendDeploymentTest < MiniTest::Test
    class Tester
      include SendDeployment

      NR_CHANGELOG = 'Rubáiyát of Omar Khayyám'
      LOOKUP_CHANGELOG = 'Billborough'

      def fetch(_key); end

      def lookup_changelog
        LOOKUP_CHANGELOG
      end
    end

    def tester
      @tester ||= Tester.new
    end

    def test_fetch_changelog_initial_fetch_succeeds_and_using_scm_then_use_fetched_value
      tester.stub :has_scm?, true do
        tester.stub :fetch, Tester::NR_CHANGELOG, [:nr_changelog] do
          assert_equal Tester::NR_CHANGELOG, tester.send(:fetch_changelog)
        end
      end
    end

    def test_fetch_changelog_initial_fetch_succeeds_and_not_using_scm_then_use_fetched_value
      tester.stub :has_scm?, false do
        tester.stub :fetch, Tester::NR_CHANGELOG, [:nr_changelog] do
          assert_equal Tester::NR_CHANGELOG, tester.send(:fetch_changelog)
        end
      end
    end

    def test_fetch_changelog_initial_fetch_fails_and_using_scm_then_perform_lookup
      tester.stub :has_scm?, true do
        tester.stub :fetch, nil, [:nr_changelog] do
          assert_equal Tester::LOOKUP_CHANGELOG, tester.send(:fetch_changelog)
        end
      end
    end

    def test_fetch_changelog_initial_fetch_fails_and_not_using_scm_then_return_nil
      tester.stub :has_scm?, false do
        tester.stub :fetch, nil, [:nr_changelog] do
          assert_nil tester.send(:fetch_changelog)
        end
      end
    end
  end
end
