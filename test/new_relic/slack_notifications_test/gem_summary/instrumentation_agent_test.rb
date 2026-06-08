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
  require_relative '../../../../.github/workflows/scripts/slack_notifications/gem_summary/instrumentation_agent'

  class InstrumentationAgentTests < Minitest::Test
    def stub_pipeline(code: 'CODE', changelog: 'CHANGELOG', response: 'summary', captured: nil)
      client = Object.new
      client.define_singleton_method(:send_message) do |prompt|
        captured << prompt if captured
        response
      end

      GemSummary::ClaudeClient.stub(:new, client) do
        GemSummary::GemInstrumentationMapper.stub(:instrumentation_summary, code) do
          GemSummary::ChangelogAnalyzer.stub(:fetch_changelog, changelog) do
            yield
          end
        end
      end
    end

    def test_analyze_returns_nil_when_gem_not_instrumented
      stub_pipeline(code: nil) do
        assert_nil GemSummary::InstrumentationAgent.analyze('some-gem', '1.0.0')
      end
    end

    def test_analyze_returns_nil_when_changelog_unavailable
      stub_pipeline(changelog: nil) do
        assert_nil GemSummary::InstrumentationAgent.analyze('some-gem', '1.0.0')
      end
    end

    def test_analyze_sends_formatted_prompt_to_claude
      captured = []
      stub_pipeline(code: 'WRAPPED CODE', changelog: 'CHANGELOG BODY', captured: captured) do
        assert_equal 'summary', GemSummary::InstrumentationAgent.analyze('redis', '5.4.1')
      end

      prompt = captured.first
      assert_includes prompt, 'redis'
      assert_includes prompt, '5.4.1'
      assert_includes prompt, 'WRAPPED CODE'
      assert_includes prompt, 'CHANGELOG BODY'
    end

    def test_analyze_returns_nil_when_claude_fails
      stub_pipeline(response: nil) do
        assert_nil GemSummary::InstrumentationAgent.analyze('redis', '5.4.1')
      end
    end
  end
end
