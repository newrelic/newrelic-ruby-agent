# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'simplecov' if RUBY_VERSION >= '2.7.0'

module SimpleCovHelper
  def self.command_name suite_name
    SimpleCov.command_name suite_name if RUBY_VERSION >= '2.7.0'
  end
end
