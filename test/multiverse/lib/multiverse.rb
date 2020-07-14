# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'fileutils'

module Multiverse

  # <ruby_agent>/test/multiverse
  #
  ROOT = File.expand_path '../..', __FILE__

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

end

require 'multiverse/bundler_patch'
require 'multiverse/color'
require 'multiverse/output_collector'
require 'multiverse/runner'
require 'multiverse/envfile'
require 'multiverse/suite'
