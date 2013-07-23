#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'bundler'

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'multiverse', 'lib', 'multiverse', 'color'))
include Multiverse::Color

env_root = File.join(File.dirname(__FILE__), "..", "environments")

overall_status = 0

tests_to_run = Dir["#{env_root}/*"].select { |d| File.basename(d).start_with?(ARGV[0]) }
tests_to_run.each do |dir|
  Bundler.with_clean_env do
    puts yellow("Running tests for #{dir}... ")
    puts "Bundling... "
    bundling = `cd #{dir} && bundle install`
    puts red(bundling) unless $?.success?

    puts "Starting tests..."
    puts `bundle exec rake`

    overall_status = $?.exitstatus if overall_status == 0 && !($?.success?)
  end
end

exit(overall_status)
