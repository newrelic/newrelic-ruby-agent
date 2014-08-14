namespace :newrelic do
  namespace :config do
    desc "Describe available New Relic configuration settings."

    GENERAL   = "general"
    DISABLING = "disabling"

    SECTION_DESCRIPTIONS = {
      GENERAL              => 'These settings are available for agent configuration. Some settings depend on your New Relic subscription level.',
      DISABLING            => 'Use these settings to toggle instrumentation types during agent startup.',
      "transaction_tracer" => 'The <a href="/docs/apm/traces/transaction-traces/transaction-traces">transaction traces</a> feature collects detailed information from a selection of transactions, including a summary of the calling sequence, a breakdown of time spent, and a list of SQL queries and their query plans (on mysql and postgresql). Available features depend on your New Relic subscription level.',
      "error_collector"    => 'The agent collects and reports all uncaught exceptions by default. These configuration options allow you to customize the error collection.',
      "browser_monitoring" => 'New Relic Browser\'s <a href="/docs/browser/new-relic-browser/page-load-timing/page-load-timing-process">page load timing</a> feature (sometimes referred to as real user monitoring or RUM) gives you insight into the performance real users are experiencing with your website. This is accomplished by measuring the time it takes for your users\' browsers to download and render your web pages by injecting a small amount of JavaScript code into the header and footer of each page.',
      "analytics_events"   => '<a href="/docs/insights/new-relic-insights/understanding-insights/new-relic-insights">New Relic Insights</a> is a software analytics resource to gather and visualize data about your software and what it says about your business. With it you can quickly and easily create real-time dashboards to get immediate answers about end-user experiences, clickstreams, mobile activities, and server transactions.'
    }

    NAME_OVERRIDES = {
      "slow_sql"     => "Slow SQL",
      "xray_session" => "X-Ray Session"
    }

    def output(format)
      config_hash = build_config_hash
      sections = flatten_config_hash(config_hash)

      puts build_erb(format).result(binding)
    end

    def build_config_hash
      sections = Hash.new {|hash, key| hash[key] = []}
      NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
        next unless value[:public]

        section_key = GENERAL
        section = key.to_s.match(/(.*)\.(.*)/)

        if section
          section_key = section[1]
          key = section[2]
        elsif key.to_s.match(/^disable_/)
          section_key = DISABLING
          key = key.to_s
        end

        sections[section_key] << {
          :key         => format_key(section_key, key),
          :type        => format_type(value[:type]),
          :description => format_description(value),
          :default     => format_default_value(value)
        }
      end
      sections
    end

    def flatten_config_hash(config_hash)
      sections = []
      sections << pluck(GENERAL, config_hash)
      sections << pluck("transaction_tracer", config_hash)
      sections << pluck("error_collector",    config_hash)
      sections << pluck("browser_monitoring", config_hash)
      sections << pluck("analytics_events",   config_hash)
      sections.concat(config_hash.to_a.sort_by { |a| a.first})

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

    def format_key(section_key, key)
      if section_key == GENERAL || section_key == DISABLING
        key.to_s
      else
        "#{section_key}.#{key}"
      end
    end

    def format_name(key)
      name = NAME_OVERRIDES[key]
      return name if name

      key.split("_").
          each { |fragment| fragment[0] = fragment[0].upcase }.
          join(" ")
    end

    def format_type(type)
      if type == NewRelic::Agent::Configuration::Boolean
        "Boolean"
      else
        type
      end
    end

    def format_description(value)
      description = value[:description]
      description = "<b>DEPRECATED</b> #{description}" if value[:deprecated]
      description
    end

    def format_default_value(spec)
      if spec[:default].is_a?(Proc)
        '(Dynamic)'
      else
        spec[:default].inspect
      end
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

    task :docs, [:format] => [] do |t, args|
      require File.expand_path(File.join(File.dirname(__FILE__), "..", "new_relic", "agent", "configuration", "default_source.rb"))
      format = args[:format] || "text"
      output(format)
    end
  end
end
