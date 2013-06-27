#!/usr/bin/env ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

env_root = File.join(File.dirname(__FILE__), "..", "environments")

tests_to_run = Dir["#{env_root}/*"].select { |d| File.basename(d).start_with?(ARGV[0]) }

tests_to_run.each do |dir|
  puts `cd #{dir} && bundle install && bundle exec rake`
end
