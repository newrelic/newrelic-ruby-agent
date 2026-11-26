# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'erb'
require 'fileutils'
require_relative '../../new_relic/agent/configuration/default_source'

module Format
  extend self

  TEXT_FILE_PATH = 'ruby-agent-configuration.mdx'
  DOCS_PAGES_DIR = 'config-docs'
  OVERVIEW_SLUG = 'ruby-agent-configuration-overview'
  DOCS_URL_PREFIX = '/docs/apm/agents/ruby-agent/configuration/'

  GENERAL = 'general'
  DISABLING = 'disabling'
  ATTRIBUTES = 'attributes'

  NON_ENV_CONFIGS = %w[
    error_collector.ignore_classes
    error_collector.ignore_messages
    error_collector.expected_classes
    error_collector.expected_messages
  ]

  SECTION_DESCRIPTIONS = {
    GENERAL => 'These settings are available for agent configuration. Some settings depend on your New Relic subscription level.',
    DISABLING => 'Use these settings to toggle instrumentation types during agent startup.',
    ATTRIBUTES => '[Attributes](/docs/features/agent-attributes) are key-value pairs containing information that determines the properties of an event or transaction. These key-value pairs can be viewed within transaction traces in APM, traced errors in APM, transaction events in dashboards, and page views in dashboards. You can customize exactly which attributes will be sent to each of these destinations',
    'transaction_tracer' => 'The [transaction traces](/docs/apm/traces/transaction-traces/transaction-traces) feature collects detailed information from a selection of transactions, including a summary of the calling sequence, a breakdown of time spent, and a list of SQL queries and their query plans (on mysql and postgresql). Available features depend on your New Relic subscription level.',
    'error_collector' => "The agent collects and reports all uncaught exceptions by default. These configuration options allow you to customize the error collection.\n\nFor information on ignored and expected errors, [see this page on Error Analytics in APM](/docs/agents/manage-apm-agents/agent-data/manage-errors-apm-collect-ignore-or-mark-expected/). To set expected errors via the `NewRelic::Agent.notice_error` Ruby method, [consult the Ruby agent API](/docs/agents/ruby-agent/api-guides/sending-handled-errors-new-relic/).",
    'browser_monitoring' => "The <InlinePopover type='browser' /> [page load timing](/docs/browser/new-relic-browser/page-load-timing/page-load-timing-process) feature (sometimes referred to as real user monitoring or RUM) gives you insight into the performance real users are experiencing with your website. This is accomplished by measuring the time it takes for your users' browsers to download and render your web pages by injecting a small amount of JavaScript code into the header and footer of each page.",
    'application_logging' => "The Ruby agent supports [APM logs in context](/docs/apm/new-relic-apm/getting-started/get-started-logs-context). For some tips on configuring logs for the Ruby agent, see [Configure Ruby logs in context](/docs/logs/logs-context/configure-logs-context-ruby).\n\nAvailable logging-related config options include:",
    'ai_monitoring' => "This section includes Ruby agent configurations for setting up AI monitoring.\n\n<Callout variant='important'>You need to enable distributed tracing to capture trace and feedback data. It is turned on by default in Ruby agents 8.0.0 and higher.</Callout>",
    'security' => "[New Relic Interactive Application Security Testing](/docs/iast/introduction/) (IAST) tests your applications for any exploitable vulnerability by replaying the generated HTTP request with vulnerable payloads.\n\n<Callout variant='important'>Run IAST with non-production deployments only to avoid exposing vulnerabilities on your production software. IAST mode requires Ruby agent version 9.12.0 or higher and the [newrelic_security](https://rubygems.org/gems/newrelic_security) gem. Security agent configurations are disabled by default.</Callout>"
  }

  NAME_OVERRIDES = {
    'slow_sql' => 'Slow SQL [#slow-sql]',
    'custom_insights_events' => 'Custom Events [#custom-events]',
    'ai_monitoring' => 'AI Monitoring [#ai-monitoring]',
    'opentelemetry' => 'OpenTelemetry [#opentelemetry]'
  }

  ERRORS_INBOX_SECTION = <<~ERRORS_INBOX
    ## Errors inbox configuration [#errors-inbox-configuration]

    Setting one of the following environment variables will help you identify which versions of your software produced the errors.

    * `NEW_RELIC_METADATA_SERVICE_VERSION` creates `tags.service.version` on event data containing the version of your code that is deployed, in many cases a semantic version such as `1.2.3`, but not always.
    * `NEW_RELIC_METADATA_RELEASE_TAG` creates `tags.releaseTag` on event data containing the release tag (such as `v0.1.209` or `release-209`).
    * `NEW_RELIC_METADATA_COMMIT` creates `tags.commit` on event data containing the commit SHA. The entire SHA can be used or just the first seven characters (e.g., `734713b`).

    [Errors inbox](/docs/errors-inbox/version-tracking/) will automatically track which versions of your software are producing errors.
  ERRORS_INBOX

  SETTINGS_PAGES = [
    {
      slug: 'ruby-agent-configuration-general-settings',
      title: 'Ruby agent general settings',
      meta_description: 'Ruby agent general configuration settings: app name, license key, proxy, and agent behavior.',
      intro: 'Configure the core Ruby agent settings including app name, license key, proxy, logging, and general agent behavior.',
      table_label: 'General settings',
      table_summary: 'Core agent behavior: app name, license key, proxy, logging, and general agent behavior',
      sections: %w[general]
    },
    {
      slug: 'ruby-agent-configuration-transaction-tracer-settings',
      title: 'Ruby agent transaction tracer settings',
      meta_description: 'Ruby agent transaction tracer and slow SQL configuration: trace thresholds, SQL recording, and explain plans.',
      intro: "Configure the Ruby agent's transaction tracer and slow SQL settings to control how traces are collected, what SQL is recorded, and when explain plans are gathered.",
      table_label: 'Transaction tracer settings',
      table_summary: 'Slow transaction capture, SQL recording, and explain plans',
      sections: %w[transaction_tracer slow_sql]
    },
    {
      slug: 'ruby-agent-configuration-error-collector-settings',
      title: 'Ruby agent error collector settings',
      meta_description: 'Ruby agent error collector configuration: ignore errors, expected errors, and error event sampling.',
      intro: "Configure the Ruby agent's error collector to customize how errors are captured, which errors to ignore or treat as expected, and how error events are sampled.",
      table_label: 'Error collector settings',
      table_summary: 'Which errors are captured, ignored, or marked as expected',
      sections: %w[error_collector],
      footer: ERRORS_INBOX_SECTION
    },
    {
      slug: 'ruby-agent-configuration-browser-monitoring-settings',
      title: 'Ruby agent browser monitoring settings',
      meta_description: 'Ruby agent browser monitoring configuration: enable auto-instrumentation.',
      intro: "Configure the Ruby agent's browser monitoring settings to control page load timing injection and Content Security Policy nonce support.",
      table_label: 'Browser monitoring settings',
      table_summary: 'Page load timing injection and Content Security Policy nonce support',
      sections: %w[browser_monitoring]
    },
    {
      slug: 'ruby-agent-configuration-distributed-tracing-settings',
      title: 'Ruby agent distributed tracing settings',
      meta_description: 'Ruby agent distributed tracing configuration: enable distributed tracing, Infinite Tracing, and span events.',
      intro: "Configure the Ruby agent's distributed tracing settings to enable end-to-end request tracking, Infinite Tracing tail-based sampling, and span event collection.",
      table_label: 'Distributed tracing settings',
      table_summary: 'Distributed tracing, Infinite Tracing, and span event collection',
      sections: %w[distributed_tracing infinite_tracing span_events]
    },
    {
      slug: 'ruby-agent-configuration-logs-in-context-settings',
      title: 'Ruby agent logs in context settings',
      meta_description: 'Ruby agent application logging configuration: log forwarding, local log decoration, and log metrics.',
      intro: "Configure the Ruby agent's application logging settings to control log forwarding, local decoration, custom attributes on log events, and log metrics collection.",
      table_label: 'Logs in context settings',
      table_summary: 'Log forwarding, local decoration, custom attributes on log events, and log metrics',
      sections: %w[application_logging]
    },
    {
      slug: 'ruby-agent-configuration-ai-monitoring-settings',
      title: 'Ruby agent AI monitoring settings',
      meta_description: 'Ruby agent AI monitoring configuration: enable AI monitoring and configure LLM event recording.',
      intro: "Configure the Ruby agent's AI monitoring settings to enable LLM instrumentation and control whether input and output content is captured in AI events.",
      table_label: 'AI monitoring settings',
      table_summary: 'LLM instrumentation and input/output content capture',
      sections: %w[ai_monitoring]
    },
    {
      slug: 'ruby-agent-configuration-attributes-settings',
      title: 'Ruby agent attributes settings',
      meta_description: 'Ruby agent attributes configuration: enable/disable attributes and configure include/exclude lists.',
      intro: "Configure the Ruby agent's attributes settings to control which key-value pairs are captured and sent to each destination: transaction traces, error collection, span events, transaction events, and browser monitoring.",
      table_label: 'Attributes settings',
      table_summary: 'Which key-value pairs are captured and sent to each destination',
      sections: %w[attributes]
    },
    {
      slug: 'ruby-agent-configuration-other-settings',
      title: 'Ruby agent other settings',
      meta_description: 'Ruby agent miscellaneous settings: transaction events, audit log, autostart, cloud, code level metrics, custom events, datastore tracer, disabling, Elasticsearch, Heroku, instrumentation, message tracer, security, serverless, Sidekiq, Stripe, utilization, and more.',
      intro: 'Configure miscellaneous Ruby agent settings including transaction events, audit log, autostart behavior, cloud integration, instrumentation controls, security agent, serverless mode, Sidekiq, and utilization detection.',
      table_label: 'Other settings',
      table_summary: 'Transaction events, audit log, autostart, cloud integration, Sidekiq, serverless, and more',
      sections: %w[transaction_events audit_log autostart cloud code_level_metrics custom_attributes custom_insights_events datastore_tracer disabling elasticsearch heroku instrumentation message_tracer mongo opensearch opentelemetry process_host profiling puma rake rules security serverless_mode sidekiq strip_exception_messages stripe thread_profiler utilization],
      fallback: true
    }
  ].freeze

  def write_text_file
    text = erb_template('config.text.erb').result_with_hash(sections: text_file_sections)
    File.write(TEXT_FILE_PATH, clean_up_spaces(text))
  end

  def write_docs_pages
    FileUtils.mkdir_p(DOCS_PAGES_DIR)
    docs_pages.each do |file_name, content|
      path = File.join(DOCS_PAGES_DIR, file_name)
      File.write(path, content)
    end
  end

  def docs_pages(defaults = NewRelic::Agent::Configuration::DEFAULTS)
    settings_by_section = build_config_hash(defaults)
    page_template = erb_template('config_page.html.erb')
    overview = render_page(erb_template('config_overview.html.erb'), pages: SETTINGS_PAGES, url_prefix: DOCS_URL_PREFIX)
    pages = {"#{OVERVIEW_SLUG}.mdx" => overview}
    SETTINGS_PAGES.each do |page|
      sections = page_sections(page, settings_by_section)
      pages["#{page[:slug]}.mdx"] = render_page(page_template, page: page, sections: sections)
    end
    pages
  end

  def build_config_hash(defaults = NewRelic::Agent::Configuration::DEFAULTS)
    settings_by_section = Hash.new { |hash, section| hash[section] = [] }
    defaults.each do |key, value|
      next unless value[:public]

      name = key.to_s
      section = section_key(name)
      settings_by_section[section] << format_setting(name, value)
    end
    settings_by_section
  end

  def unassigned_sections(section_keys)
    assigned = SETTINGS_PAGES.flat_map { |page| page[:sections] }
    (section_keys - assigned).sort
  end

  private

  def text_file_sections
    settings_by_section = build_config_hash
    first_sections = [GENERAL, 'transaction_tracer', 'error_collector', 'browser_monitoring', 'transaction_events', 'application_logging']
    other_sections = (settings_by_section.keys - first_sections).sort
    section_entries(first_sections + other_sections, settings_by_section)
  end

  def page_sections(page, settings_by_section)
    section_names = page[:sections]
    if page[:fallback]
      section_names += unassigned_sections(settings_by_section.keys)
    end
    section_entries(section_names, settings_by_section)
  end

  def section_entries(section_names, settings_by_section)
    names_with_settings = section_names.select { |name| settings_by_section.key?(name) }
    names_with_settings.map do |name|
      [name, format_name(name), SECTION_DESCRIPTIONS[name], settings_by_section[name]]
    end
  end

  def erb_template(filename)
    path = File.join(__dir__, filename)
    ERB.new(File.read(path))
  end

  def render_page(template, values)
    text = template.result_with_hash(values)
    clean_up_spaces(text) + "\n"
  end

  def clean_up_spaces(content)
    content.split("\n").map(&:rstrip).join("\n").gsub('.  ', '. ')
  end

  def format_default_value(spec)
    return spec[:documentation_default] if !spec[:documentation_default].nil?

    if spec[:default].is_a?(Proc)
      '(Dynamic)'
    else
      "#{spec[:default].inspect}"
    end
  end

  def format_description(value)
    if value[:deprecated]
      "<DNT>**DEPRECATED**</DNT> #{value[:description]}"
    else
      value[:description]
    end
  end

  def format_env_var(key)
    return 'None' if NON_ENV_CONFIGS.include?(key)

    "NEW_RELIC_#{key.tr('.', '_').upcase}"
  end

  def format_name(key)
    name = NAME_OVERRIDES[key]
    return name if name

    title = key.split('_')
      .each { |fragment| fragment[0] = fragment[0].upcase }
      .join(' ')
    "#{title} [##{key.tr('_', '-')}]"
  end

  def format_setting(key, value)
    {
      :key => key,
      :type => format_type(value[:type]),
      :description => format_description(value),
      :default => format_default_value(value),
      :env_var => format_env_var(key)
    }
  end

  def format_type(type)
    if type == NewRelic::Agent::Configuration::Boolean
      'Boolean'
    else
      type
    end
  end

  def section_key(name)
    parts = name.split('.')
    if name.start_with?('disable_') # "disable_httpclient"
      DISABLING
    elsif parts[1] == 'attributes' # "transaction_tracer.attributes.enabled"
      ATTRIBUTES
    elsif parts.length >= 2 # "error_collector.enabled"
      parts.first
    else
      GENERAL
    end
  end
end
