# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'test_time_reporter'

module Minitest
  def self.plugin_test_time_init(options)
    # TODO: Get Minitest pride working again
    Minitest.reporter << TestTimeReporter.new
  end

  def self.plugin_test_time_options(opts, options)
    # ...
  end
end
