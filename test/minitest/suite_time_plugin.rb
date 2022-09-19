# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'suite_time_reporter'

module Minitest
  def self.plugin_suite_time_init(options)
    Minitest.reporter << SuiteTimeReporter.new if RUBY_VERSION >= '2.4.0'
  end

  def self.plugin_suite_time_options(opts, options)
    # ...
  end
end
