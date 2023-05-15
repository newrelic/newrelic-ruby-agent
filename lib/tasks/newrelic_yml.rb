# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# create a template file for newrelic.yml
# read in the default_source.rb file
  # items are in a the DEFAULTS hash
# parse the default_source.rb file for the config options
# write the config options to the template file
# write the template file to newrelic.yml

require 'new_relic/agent/configuration/default_source'

CRITICAL = [:agent_enabled, :app_name, :license_key, :log_level]
DEFAULTS = NewRelic::Agent::Configuration::DEFAULTS
final_array = []

DEFAULTS.sort.each do |key, value|
  if value[:public] == true
    puts value[:description]
    puts "#{key}: #{value[:default]}]}"
  end
end

# puts 'public' if DEFAULTS.key[55][:public] == true

# NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
