# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Issues:
# Sometimes descriptions have callouts, likely meant for website ie disable_sinatra_auto_middleware

# for some values the default is dynamic and the documentation_default is doesn't exist. 
# - process_host.display_name
# - transaction_tracer.transaction_threshold
# - config_path

# need to remove links from descriptions

# special case?: error_collector.ignore_classes

# <InlinePopover type="userKey" /> . need to replace with just the type text

# add hashtags to all lines 

# wrap text after 80 characters

require_relative '../new_relic/agent/configuration/default_source'

CRITICAL = [:agent_enabled, :app_name, :license_key, :log_level]
SKIP = [:defer_rails_initialization]
DEFAULTS = NewRelic::Agent::Configuration::DEFAULTS

def get_configs
  final_configs = {}

  DEFAULTS.sort.each do |key, value|
    next if CRITICAL.include?(key) || SKIP.include?(key)

    if value[:public] == true
      description = sanitize_description(value[:description])
      default = sanitize_default(value)

      final_configs[key] = {description: description, default: default}
    end
  end

  final_configs
end

def sanitize_default(config_hash)
  default = config_hash[:documentation_default].nil? ? config_hash[:default] : config_hash[:documentation_default]
  default = 'nil' if default.nil?
  default = '""' if default == ''

  default
end

def sanitize_description(description)
  # remove callouts
  description = description.split("\n").reject { |line| line.match?("</?Callout") }.join("\n")
  # remove links
  description = description.gsub(/<a href=".*">(.*)<\/a>/, '\1')
  # remove inline popovers, keep the text inside type
  description = description.gsub(/<InlinePopover type="(.*)" \/>/, '\1')
  # remove html tags
  description = description.gsub(/<\/?[^>]*>/, '')
  # remove leading and trailing whitespace
  description = description.strip
  # wrap text after 80 characters
  description = description.gsub(/(.{1,80})(\s+|\Z)/, "\\1\n")
  # add hashtags to all lines
  description = description.split("\n").map { |line| "  # #{line}" }.join("\n")

  description
  
end

def build_string
  configs = get_configs
  yml_string = ''

  configs.each do |key, value|
    yml_string += "#{value[:description]} \n  # #{key}: #{value[:default]}\n\n"
  end

  yml_string
end

HEADER = <<~HEADER
  #
  # This file configures the New Relic Agent.  New Relic monitors Ruby, Java,
  # .NET, PHP, Python, Node, and Go applications with deep visibility and low
  # overhead.  For more information, visit www.newrelic.com.

  # Generated <%= Time.now.strftime('%B %d, %Y') %><%= ", for version \#{@agent_version}" if @agent_version %>
  #<%= "\\n# \#{generated_for_user}\\n#" if generated_for_user %>
  # For full documentation of agent configuration options, please refer to
  # https://docs.newrelic.com/docs/agents/ruby-agent/installation-configuration/ruby-agent-configuration

  common: &default_settings
    # Required license key associated with your New Relic account.
    license_key: <%= license_key %>

    # Your application name. Renaming here affects where data displays in New
    # Relic. For more details, see https://docs.newrelic.com/docs/apm/new-relic-apm/maintenance/renaming-applications
    app_name: <%= app_name %>

    # To disable the agent regardless of other settings, uncomment the following:
    # agent_enabled: false

    # Logging level for log/newrelic_agent.log; options are error, warn, info, or
    # debug.
    log_level: info

    # All of the following configuration options are optional. Review them, and
    # uncomment or edit them if they appear relevant to your application needs.

HEADER

FOOTER = <<~FOOTER
  # Environment-specific settings are in this section.
  # RAILS_ENV or RACK_ENV (as appropriate) is used to determine the environment.
  # If your application has other named environments, configure them here.
  development:
    <<: *default_settings
    app_name: <%= app_name %> (Development)

  test:
    <<: *default_settings
    # It doesn't make sense to report to New Relic from automated test runs.
    monitor_mode: false

  staging:
    <<: *default_settings
    app_name: <%= app_name %> (Staging)

  production:
    <<: *default_settings

FOOTER

File.write('test_newrelic.yml', HEADER + build_string + FOOTER)
