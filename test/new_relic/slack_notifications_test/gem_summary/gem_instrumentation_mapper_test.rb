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
  require_relative '../../../../.github/workflows/scripts/slack_notifications/gem_summary/gem_instrumentation_mapper'

  class GemInstrumentationMapperTests < Minitest::Test
    def test_summary_returns_nil_for_unmapped_gem
      assert_nil GemSummary::GemInstrumentationMapper.instrumentation_summary('totally-fake-gem-name-12345')
    end

    def test_summary_string_entry_loads_instrumentation_and_prepend
      # `redis: redis` is a string entry — looks up redis/instrumentation.rb and redis/prepend.rb.
      result = GemSummary::GemInstrumentationMapper.instrumentation_summary('redis')

      refute_nil result
      assert_includes result, '# === redis/instrumentation.rb ==='
      assert_includes result, '# === redis/prepend.rb ==='
    end

    def test_summary_array_entry_loads_listed_files
      # `mongo` has an explicit array of files in gem_instrumentation.yml.
      result = GemSummary::GemInstrumentationMapper.instrumentation_summary('mongo')

      refute_nil result
      assert_includes result, '# === mongo.rb ==='
      assert_includes result, '# === mongodb_command_subscriber.rb ==='
    end

    def test_summary_returns_nil_when_no_files_exist
      capture_io do
        File.stub(:exist?, false) do
          assert_nil GemSummary::GemInstrumentationMapper.instrumentation_summary('redis')
        end
      end
    end

    def test_summary_warns_when_referenced_file_is_missing
      # Stub `redis/prepend.rb` missing but `redis/instrumentation.rb` present.
      stubbed_exist = ->(path) { !path.end_with?('redis/prepend.rb') }
      out, _err = capture_io do
        File.stub(:exist?, stubbed_exist) do
          GemSummary::GemInstrumentationMapper.instrumentation_summary('redis')
        end
      end

      assert_includes out, 'instrumentation file not found'
      assert_includes out, 'redis/prepend.rb'
    end
  end
end
