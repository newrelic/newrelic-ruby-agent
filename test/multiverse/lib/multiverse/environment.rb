# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'fileutils'
module Multiverse
  ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
  $: << File.expand_path(File.join(ROOT, 'lib'))

  # Include from our unit testing path to share fake_collector
  $: << File.expand_path(File.join(ROOT, '..', 'new_relic'))

  SUITES_DIRECTORY = ENV['SUITES_DIRECTORY'] || File.join(ROOT, '/suites')
  require 'multiverse/color'
  require 'multiverse/output_collector'
  require 'multiverse/runner'
  require 'multiverse/envfile'
  require 'multiverse/suite'
end
