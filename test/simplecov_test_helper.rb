# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# The minimum version of Ruby required (by New Relic) to run SimpleCov
# NOTE: At the time that SimpleCov was introduced to this code base, it
# required Ruby >= 2.5.0 and Ruby 2.6.0 was marked for EOL
SIMPLECOV_MIN_RUBY_VERSION = '2.7.0'

begin
  if RUBY_VERSION >= SIMPLECOV_MIN_RUBY_VERSION && ENV['VERBOSE_TEST_OUTPUT']
    require 'simplecov'

    # Enable subprocess tracking IMMEDIATELY after loading SimpleCov
    # This must happen before SimpleCov.start is called
    SimpleCov.enable_for_subprocesses true if defined?(SimpleCov)

    # Use external at_exit so multiverse tests can control when coverage is saved
    # This prevents SimpleCov's automatic at_exit from stopping coverage too early
    SimpleCov.external_at_exit = true if defined?(SimpleCov)
  end
rescue LoadError => e
  puts
  puts "SimpleCov requested by Ruby #{RUBY_VERSION} which is >=#{SIMPLECOV_MIN_RUBY_VERSION} "
  puts "but the gem is not available. #{e.class}: #{e.message}"
  puts
end
