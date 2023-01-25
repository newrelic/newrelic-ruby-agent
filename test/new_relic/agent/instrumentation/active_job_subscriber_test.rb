# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../test_helper'
require 'new_relic/agent/instrumentation/active_job_subscriber'

if defined?(ActiveJob) &&
    ActiveJob.respond_to?(:gem_version) &&
    ActiveJob.gem_version >= Gem::Version.new('6.0.0')
  require_relative 'rails/active_job_subscriber'
else
  puts "Skipping tests in #{__FILE__} because ActiveJob is unavailable or < 6.0"
end
