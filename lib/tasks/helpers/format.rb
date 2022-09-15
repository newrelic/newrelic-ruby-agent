# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Format
  def output(format)
    config_hash = build_config_hash
    sections = flatten_config_hash(config_hash)

    puts build_erb(format).result(binding).split("\n").map(&:rstrip).join("\n").gsub('.  ', '. ')
    sections # silences unused warning to return this
  end

  def build_config_hash
    sections = Hash.new { |hash, key| hash[key] = [] }
    NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
      next unless value[:public]

      section_key = GENERAL
      key = key.to_s
      components = key.split(".")

      if key.match(/^disable_/) # "disable_httpclient"
        section_key = DISABLING
      elsif components.length >= 2 && !(components[1] == "attributes") # "analytics_events.enabled"
        section_key = components.first
      elsif components[1] == "attributes" # "transaction_tracer.attributes.enabled"
        section_key = ATTRIBUTES
      end

      sections[section_key] << {
        :key => key,
        :type => format_type(value[:type]),
        :description => format_description(value),
        :default => format_default_value(value),
        :env_var => format_env_var(key)
      }
    end
    sections
  end

  def flatten_config_hash(config_hash)
    sections = []
    sections << pluck(GENERAL, config_hash)
    sections << pluck("transaction_tracer", config_hash)
    sections << pluck("error_collector", config_hash)
    sections << pluck("browser_monitoring", config_hash)
    sections << pluck("analytics_events", config_hash)
    sections << pluck("transaction_events", config_hash)
    sections << pluck("application_logging", config_hash)
    sections.concat(config_hash.to_a.sort_by { |a| a.first })

    add_data_to_sections(sections)

    sections
  end

  def add_data_to_sections(sections)
    sections.each do |section|
      section_key = section[0]
      section.insert(1, format_name(section_key))
      section.insert(2, SECTION_DESCRIPTIONS[section_key])
    end
  end

  def format_name(key)
    name = NAME_OVERRIDES[key]
    return name if name

    key.split("_")
      .each { |fragment| fragment[0] = fragment[0].upcase }
      .join(" ")
  end

  def format_type(type)
    if type == NewRelic::Agent::Configuration::Boolean
      "Boolean"
    else
      type
    end
  end

  def format_description(value)
    description = ''
    description += "<b>DEPRECATED</b> " if value[:deprecated]
    description += value[:description]
    description
  end

  def format_default_value(spec)
    return spec[:documentation_default] if !spec[:documentation_default].nil?
    if spec[:default].is_a?(Proc)
      '(Dynamic)'
    else
      "#{spec[:default].inspect}"
    end
  end

  def format_env_var(key)
    return "None" if NON_ENV_CONFIGS.include?(key)
    "NEW_RELIC_#{key.gsub(".", "_").upcase}"
  end

  def pluck(key, config_hash)
    value = config_hash.delete(key)
    [key, value]
  end

  def build_erb(format)
    require 'erb'
    path = File.join(File.dirname(__FILE__), "config.#{format}.erb")
    template = File.read(File.expand_path(path))
    ERB.new(template)
  end
end
