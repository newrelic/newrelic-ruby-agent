# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../simplecov_test_helper'
require 'fileutils'

module Multiverse
  # <ruby_agent>/test/multiverse
  #
  ROOT = File.expand_path('../..', __FILE__)

  # append <ruby_agent>/test/multiverse/lib to the load path
  #
  $: << File.expand_path('lib', ROOT)

  # append <ruby_agent>/test/new_relic to the load path
  # ... to share fake_collector
  #
  $: << File.expand_path('../new_relic', ROOT)

  # suites dir from env var, default to <ruby_agent>/test/multiverse/suites
  #
  SUITES_DIRECTORY = ENV['SUITES_DIRECTORY'] || File.expand_path('suites', ROOT)

  # This path is from the perspective of the files within the multiverse dir.
  # It is used to hold test timing information between suite runs so that the
  # slowest tests can be evaluated across suites
  TEST_TIME_REPORT_PATH = File.join(File.expand_path('../../..', __FILE__), 'minitest/minitest_time_report')
end

require 'multiverse/bundler_patch'
require 'multiverse/color'
require 'multiverse/output_collector'
require 'multiverse/runner'
require 'multiverse/envfile'
require 'multiverse/suite'
require 'multiverse/gem_manifest'
