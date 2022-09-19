# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelicRunnable
  def run(reporter, options = {})
    reporter.reporters.each do |reporter|
      reporter.before_test(self) if defined?(reporter.before_test)
    end
    super
  end
end

Minitest::Runnable.singleton_class.send(:prepend, NewRelicRunnable)
