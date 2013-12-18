#!/usr/bin/env ruby

ENV["NEW_RELIC_LOG_FILE_PATH"] = "STDOUT"

require 'newrelic_rpm'

# Force all named items to re-enable
enable_everyone = {}
DependencyDetection.items.each do |item|
  if item.name
    enable_everyone["disable_#{item.name}".to_sym] = false
  end
end
NewRelic::Agent.config.apply_config(enable_everyone)

# Run dependency detection again!
DependencyDetection.detect!
