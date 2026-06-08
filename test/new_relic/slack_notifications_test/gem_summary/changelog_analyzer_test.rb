# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# HTTParty is only installed by the slack_notifications_tests CI job, not bundled with
# the main test suite. This check ensures these tests run in that job but are skipped
# when the test file is picked up by the glob pattern during regular test runs.
begin
  require 'httparty'
rescue LoadError
  nil
end

if defined?(HTTParty)
  # TODO: MAJOR VERSION - Remove this version constraint when we update the
  # minitest version in the gemspec
  gem 'minitest', '5.3.3'
  require 'minitest/autorun'
  require_relative '../../../../.github/workflows/scripts/slack_notifications/gem_summary/changelog_analyzer'

  class ChangelogAnalyzerTests < Minitest::Test
    def successful_response(body)
      response = Minitest::Mock.new
      response.expect(:success?, true)
      response.expect(:body, body)
      response
    end

    def failed_response
      response = Minitest::Mock.new
      response.expect(:success?, false)
      response
    end

    def test_fetch_changelog_returns_nil_for_unmapped_gem
      assert_nil GemSummary::ChangelogAnalyzer.fetch_changelog('totally-fake-gem-name-12345')
    end

    def test_fetch_changelog_releases_type
      body = JSON.dump('tag_name' => 'v7.1.0', 'body' => 'Release notes go here.')

      HTTParty.stub(:get, successful_response(body)) do
        # `rails` has type: releases in gem_changelogs.yml
        result = GemSummary::ChangelogAnalyzer.fetch_changelog('rails')

        assert_includes result, 'Release v7.1.0:'
        assert_includes result, 'Release notes go here.'
      end
    end

    def test_fetch_changelog_blob_type_extracts_latest_version_section
      changelog = <<~MD
        # Changelog

        ## 5.4.1
        - bug fix
        - another fix

        ## 5.4.0
        - prior feature
      MD

      HTTParty.stub(:get, successful_response(changelog)) do
        # `redis` has type: blob in gem_changelogs.yml
        result = GemSummary::ChangelogAnalyzer.fetch_changelog('redis')

        assert_includes result, '5.4.1'
        assert_includes result, 'bug fix'
        refute_includes result, 'prior feature'
      end
    end

    def test_fetch_changelog_truncates_at_max_length
      big_changelog = "## 1.0.0\n" + ('x' * (GemSummary::ChangelogAnalyzer::MAX_LENGTH + 100))

      HTTParty.stub(:get, successful_response(big_changelog)) do
        result = GemSummary::ChangelogAnalyzer.fetch_changelog('redis')

        assert result.end_with?('[truncated]'), 'expected truncation marker'
        assert result.length <= GemSummary::ChangelogAnalyzer::MAX_LENGTH + 20
      end
    end

    def test_fetch_changelog_returns_nil_on_http_failure
      HTTParty.stub(:get, failed_response) do
        assert_nil GemSummary::ChangelogAnalyzer.fetch_changelog('redis')
      end
    end
  end
end
