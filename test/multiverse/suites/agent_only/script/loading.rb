#!/usr/bin/env ruby

# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

ENV['NEW_RELIC_LOG_FILE_PATH'] = 'STDOUT'

require 'newrelic_rpm'

# Force all named items to re-enable
enable_everyone = {}
DependencyDetection.items.each do |item|
  enable_everyone["disable_#{item.name}".to_sym] = false if item.name
end
NewRelic::Agent.config.add_config_for_testing(enable_everyone)

# Run dependency detection again!
DependencyDetection.detect!
