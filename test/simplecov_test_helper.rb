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
    SimpleCov.enable_for_subprocesses(true) if defined?(SimpleCov)

    # Use external at_exit so we can control when coverage is finalized
    SimpleCov.external_at_exit = true if defined?(SimpleCov)

    # Store the parent process PID to detect forks
    SIMPLECOV_PARENT_PID = Process.pid

    # Register parent process finalization FIRST (runs LAST due to LIFO)
    # This ensures parent processes finalize coverage at the very end
    at_exit do
      next unless defined?(SimpleCov) && SimpleCov.running

      # Only finalize in parent process at the very end
      SimpleCov.result if Process.pid == SIMPLECOV_PARENT_PID
    end

    # Register forked child finalization SECOND (runs FIRST due to LIFO)
    # This ensures forked children finalize before they exit
    at_exit do
      next unless defined?(SimpleCov) && SimpleCov.running

      # Only finalize in forked child processes
      SimpleCov.result if Process.pid != SIMPLECOV_PARENT_PID
    end
  end
rescue LoadError => e
  puts
  puts "SimpleCov requested by Ruby #{RUBY_VERSION} which is >=#{SIMPLECOV_MIN_RUBY_VERSION} "
  puts "but the gem is not available. #{e.class}: #{e.message}"
  puts
end
