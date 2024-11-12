# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'forwardable'
require_relative '../../constants'

module NewRelic
  module Agent
    module Configuration
      # Helper since default Procs are evaluated in the context of this module
      def self.value_of(key)
        proc do
          NewRelic::Agent.config[key]
        end
      end

      def self.instrumentation_value_from_boolean(key)
        proc do
          NewRelic::Agent.config[key] ? 'auto' : 'disabled'
        end
      end

      # Marks the config option as deprecated in the documentation once generated.
      # Does not appear in logs.
      def self.deprecated_description(new_setting, description)
        link_ref = new_setting.to_s.tr('.', '-')
        %{Please see: [#{new_setting}](##{link_ref}). \n\n#{description}}
      end

      class Boolean
        def self.===(o)
          TrueClass === o or FalseClass === o
        end
      end

      class DefaultSource
        BOOLEAN_MAP = {
          'true' => true,
          'yes' => true,
          'on' => true,
          'false' => false,
          'no' => false,
          'off' => false
        }.freeze

        attr_reader :defaults

        extend Forwardable
        def_delegators :@defaults, :has_key?, :each, :merge, :delete, :keys, :[], :to_hash

        def initialize
          @defaults = default_values
        end

        def default_values
          result = {}
          ::NewRelic::Agent::Configuration::DEFAULTS.each do |key, value|
            result[key] = value[:default]
          end
          result
        end

        def self.default_settings(key)
          ::NewRelic::Agent::Configuration::DEFAULTS[key]
        end

        def self.value_from_defaults(key, subkey)
          default_settings(key)&.send(:[], subkey)
        end

        def self.allowlist_for(key)
          value_from_defaults(key, :allowlist)
        end

        def self.boolean_for(key, value)
          string_value = (value.respond_to?(:call) ? value.call : value).to_s

          BOOLEAN_MAP.fetch(string_value, nil)
        end

        def self.default_for(key)
          value_from_defaults(key, :default)
        end

        def self.transform_for(key)
          value_from_defaults(key, :transform)
        end

        def self.config_search_paths
          proc {
            yaml = 'newrelic.yml'
            config_yaml = File.join('config', yaml)
            erb = 'newrelic.yml.erb'
            config_erb = File.join('config', erb)

            paths = [config_yaml, yaml, config_erb, erb]

            if NewRelic::Control.instance.root
              paths << File.join(NewRelic::Control.instance.root, config_yaml)
              paths << File.join(NewRelic::Control.instance.root, yaml)
              paths << File.join(NewRelic::Control.instance.root, config_erb)
              paths << File.join(NewRelic::Control.instance.root, erb)
            end

            if ENV['HOME']
              paths << File.join(ENV['HOME'], '.newrelic', yaml)
              paths << File.join(ENV['HOME'], yaml)
              paths << File.join(ENV['HOME'], '.newrelic', erb)
              paths << File.join(ENV['HOME'], erb)
            end

            # If we're packaged for warbler, we can tell from GEM_HOME
            # the following line needs else branch coverage
            if ENV['GEM_HOME'] && ENV['GEM_HOME'].end_with?('.jar!') # rubocop:disable Style/SafeNavigation
              app_name = File.basename(ENV['GEM_HOME'], '.jar!')
              paths << File.join(ENV['GEM_HOME'], app_name, config_yaml)
              paths << File.join(ENV['GEM_HOME'], app_name, config_erb)
            end

            paths
          }
        end

        def self.config_path
          proc {
            found_path = NewRelic::Agent.config[:config_search_paths].detect do |file|
              File.expand_path(file) if File.exist?(file)
            end
            found_path || NewRelic::EMPTY_STR
          }
        end

        def self.framework
          proc {
            case
            when defined?(::NewRelic::TEST) then :test
            when defined?(::Rails::VERSION)
              case Rails::VERSION::MAJOR
              when 3
                :rails3
              when 4..7
                :rails_notifications
              else
                ::NewRelic::Agent.logger.warn("Detected untested Rails version #{Rails::VERSION::STRING}")
                :rails_notifications
              end
            when defined?(::Padrino) && defined?(::Padrino::PathRouter::Router) then :padrino
            when defined?(::Sinatra) && defined?(::Sinatra::Base) then :sinatra
            when defined?(::Roda) then :roda
            when defined?(::Grape) then :grape
            when defined?(::NewRelic::IA) then :external
            else :ruby
            end
          }
        end

        def self.agent_enabled
          proc {
            NewRelic::Agent.config[:enabled] &&
              (NewRelic::Agent.config[:test_mode] || NewRelic::Agent.config[:monitor_mode]) &&
              NewRelic::Agent::Autostart.agent_should_start?
          }
        end

        DEFAULT_LOG_DIR = 'log/'.freeze

        def self.audit_log_path
          proc {
            log_file_path = NewRelic::Agent.config[:log_file_path]
            wants_stdout = (log_file_path.casecmp(NewRelic::STANDARD_OUT) == 0)
            audit_log_dir = wants_stdout ? DEFAULT_LOG_DIR : log_file_path

            File.join(audit_log_dir, 'newrelic_audit.log')
          }
        end

        def self.app_name
          proc { NewRelic::Control.instance.env }
        end

        def self.dispatcher
          proc { NewRelic::Control.instance.local_env.discovered_dispatcher }
        end

        def self.thread_profiler_enabled
          proc { NewRelic::Agent::Threading::BacktraceService.is_supported? }
        end

        def self.transaction_tracer_transaction_threshold
          proc { NewRelic::Agent.config[:apdex_t] * 4 }
        end

        def self.profiling_available
          proc {
            begin
              require 'ruby-prof'
              true
            rescue LoadError
              false
            end
          }
        end

        def self.host
          proc do
            regex = /\A(?<identifier>.+?)x/
            if matches = regex.match(String(NewRelic::Agent.config[:license_key]))
              "collector.#{matches['identifier']}.nr-data.net"
            else
              'collector.newrelic.com'
            end
          end
        end

        def self.api_host
          # only used for deployment task
          proc do
            api_version = if NewRelic::Agent.config[:api_key].nil? || NewRelic::Agent.config[:api_key].empty?
              'rpm'
            else
              'api'
            end
            api_region = 'eu.' if String(NewRelic::Agent.config[:license_key]).start_with?('eu')

            "#{api_version}.#{api_region}newrelic.com"
          end
        end

        def self.convert_to_regexp_list(raw_value)
          value_list = convert_to_list(raw_value)
          value_list.map do |value|
            /#{value}/
          end
        end

        def self.convert_to_list(value)
          case value
          when String
            value.split(/\s*,\s*/)
          when Array
            value
          else
            raise ArgumentError.new("Config value '#{value}' couldn't be turned into a list.")
          end
        end

        def self.convert_to_hash(value)
          return value if value.is_a?(Hash)

          if value.is_a?(String)
            return value.split(',').each_with_object({}) do |item, hash|
              key, value = item.split('=')
              hash[key] = value
            end
          end

          raise ArgumentError.new(
            "Config value '#{value}' of " \
            "class #{value.class} couldn't be turned into a Hash."
          )
        end

        SEMICOLON = ';'.freeze
        def self.convert_to_list_on_semicolon(value)
          case value
          when Array then value
          when String then value.split(SEMICOLON)
          else NewRelic::EMPTY_ARRAY
          end
        end

        def self.convert_to_constant_list(raw_value)
          return NewRelic::EMPTY_ARRAY if raw_value.nil? || raw_value.empty?

          constants = convert_to_list(raw_value).map! do |class_name|
            const = ::NewRelic::LanguageSupport.constantize(class_name)
            NewRelic::Agent.logger.warn("Ignoring invalid constant '#{class_name}' in #{raw_value}") unless const
            const
          end
          constants.compact!
          constants
        end

        def self.enforce_fallback(allowed_values: nil, fallback: nil)
          proc do |configured_value|
            if allowed_values.any? { |v| v =~ /#{configured_value}/i }
              configured_value
            else
              fallback
            end
          end
        end
      end

      AUTOSTART_DENYLISTED_RAKE_TASKS = [
        'about',
        'assets:clean',
        'assets:clobber',
        'assets:environment',
        'assets:precompile',
        'assets:precompile:all',
        'db:create',
        'db:drop',
        'db:fixtures:load',
        'db:migrate',
        'db:migrate:status',
        'db:rollback',
        'db:schema:cache:clear',
        'db:schema:cache:dump',
        'db:schema:dump',
        'db:schema:load',
        'db:seed',
        'db:setup',
        'db:structure:dump',
        'db:version',
        'doc:app',
        'log:clear',
        'middleware',
        'notes',
        'notes:custom',
        'rails:template',
        'rails:update',
        'routes',
        'secret',
        'spec',
        'spec:features',
        'spec:requests',
        'spec:controllers',
        'spec:helpers',
        'spec:models',
        'spec:views',
        'spec:routing',
        'spec:rcov',
        'stats',
        'test',
        'test:all',
        'test:all:db',
        'test:recent',
        'test:single',
        'test:uncommitted',
        'time:zones:all',
        'tmp:clear',
        'tmp:create',
        'webpacker:compile'
      ].join(',').freeze

      # rubocop:disable Metrics/CollectionLiteralLength
      DEFAULTS = {
        # Critical
        :agent_enabled => {
          :default => DefaultSource.agent_enabled,
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, allows the Ruby agent to run.'
        },
        :app_name => {
          :default => DefaultSource.app_name,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list_on_semicolon),
          :description => 'Specify the [application name](/docs/apm/new-relic-apm/installation-configuration/name-your-application) used to aggregate data in the New Relic UI. To report data to [multiple apps at the same time](/docs/apm/new-relic-apm/installation-configuration/using-multiple-names-app), specify a list of names separated by a semicolon `;`. For example, `MyApp` or `MyStagingApp;Instance1`.'
        },
        :license_key => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :exclude_from_reported_settings => true,
          :description => 'Your New Relic <InlinePopover type="licenseKey" />.'
        },
        :log_level => {
          :default => 'info',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Sets the level of detail of log messages. Possible log levels, in increasing verbosity, are: `error`, `warn`, `info` or `debug`.'
        },
        # General
        :active_support_custom_events_names => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :description => <<~DESCRIPTION
            An array of ActiveSupport custom event names to subscribe to and instrument. For example,
              - one.custom.event
              - another.event
              - a.third.event
          DESCRIPTION
        },
        :'ai_monitoring.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `false`, all LLM instrumentation (OpenAI only for now) will be disabled and no metrics, events, or spans will be sent. AI Monitoring is automatically disabled if `high_security` mode is enabled.'
        },
        :'ai_monitoring.record_content.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => <<~DESCRIPTION
            If `false`, LLM instrumentation (OpenAI only for now) will not capture input and output content on specific LLM events.

              The excluded attributes include:
                * `content` from LlmChatCompletionMessage events
                * `input` from LlmEmbedding events

              This is an optional security setting to prevent recording sensitive data sent to and received from your LLMs.
          DESCRIPTION
        },
        # this is only set via server side config
        :apdex_t => {
          :default => 0.5,
          :public => false,
          :type => Float,
          :allowed_from_server => true,
          :description => 'For agent versions 3.5.0 or higher, [set your Apdex T via the New Relic UI](/docs/apm/new-relic-apm/apdex/changing-your-apdex-settings).'
        },
        :api_key => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :exclude_from_reported_settings => true,
          :description => 'Your New Relic <InlinePopover type="userKey" />. Required when using the New Relic REST API v2 to record deployments using the `newrelic deployments` command.'
        },
        :backport_fast_active_record_connection_lookup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Backports the faster ActiveRecord connection lookup introduced in Rails 6, which improves agent performance when instrumenting ActiveRecord. Note that this setting may not be compatible with other gems that patch ActiveRecord.'
        },
        :ca_bundle_path => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => "Manual override for the path to your local CA bundle. This CA bundle will be used to validate the SSL certificate presented by New Relic's data collection service."
        },
        :capture_memcache_keys => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable the capture of memcache keys from transaction traces.'
        },
        :capture_params => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => <<~DESCRIPTION
            When `true`, the agent captures HTTP request parameters and attaches them to transaction traces, traced errors, and [`TransactionError` events](/attribute-dictionary?attribute_name=&events_tids%5B%5D=8241).

                <Callout variant="caution">
                  When using the `capture_params` setting, the Ruby agent will not attempt to filter secret information. `Recommendation:` To filter secret information from request parameters, use the [`attributes.include` setting](/docs/agents/ruby-agent/attributes/enable-disable-attributes-ruby) instead. For more information, see the <a href="/docs/agents/ruby-agent/attributes/ruby-attribute-examples#ex_req_params">Ruby attribute examples</a>.
                </Callout>
          DESCRIPTION
        },
        :'clear_transaction_state_after_fork' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent will clear `Tracer::State` in `Agent.drop_buffered_data`.'
        },
        :'cloud.aws.account_id' => {
          :default => nil,
          :public => true,
          :type => String,
          :allow_nil => true,
          :allowed_from_server => false,
          :description => 'The AWS account ID for the AWS account associated with this app'
        },
        :config_path => {
          :default => DefaultSource.config_path,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => <<~DESC
            Path to `newrelic.yml`. If undefined, the agent checks the following directories (in order):
                * `config/newrelic.yml`
                * `newrelic.yml`
                * `$HOME/.newrelic/newrelic.yml`
                * `$HOME/newrelic.yml`
          DESC
        },
        :'exclude_newrelic_header' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Allows newrelic distributed tracing headers to be suppressed on outbound requests.'
        },
        :force_install_exit_handler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => <<~DESC
            The exit handler that sends all cached data to the collector before shutting down is forcibly installed. \
            This is true even when it detects scenarios where it generally should not be. The known use case for this \
            option is when Sinatra runs as an embedded service within another framework. The agent detects the Sinatra \
            app and skips the `at_exit` handler as a result. Sinatra classically runs the entire application in an \
            `at_exit` block and would otherwise misbehave if the agent's `at_exit` handler was also installed in those \
            circumstances. Note: `send_data_on_exit` should also be set to `true` in tandem with this setting.
          DESC
        },
        :high_security => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables [high security mode](/docs/accounts-partnerships/accounts/security/high-security). Ensure you understand the implications of high security mode before enabling this setting.'
        },
        :labels => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'A dictionary of [label names](/docs/data-analysis/user-interface-functions/labels-categories-organize-your-apps-servers) and values that will be applied to the data sent from this agent. May also be expressed as a semicolon-delimited `;` string of colon-separated `:` pairs. For example, `Server:One;Data Center:Primary`.'
        },
        :log_file_name => {
          :default => 'newrelic_agent.log',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a name for the log file.'
        },
        :log_file_path => {
          :default => DefaultSource::DEFAULT_LOG_DIR,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a path to the agent log file, excluding the filename.'
        },
        :marshaller => {
          :default => 'json',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specifies a marshaller for transmitting data to the New Relic [collector](/docs/apm/new-relic-apm/getting-started/glossary#collector). Currently `json` is the only valid value for this setting.'
        },
        :monitor_mode => {
          :default => value_of(:enabled),
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When `true`, the agent transmits data about your app to the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector).'
        },
        :prepend_active_record_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, uses `Module#prepend` rather than `alias_method` for ActiveRecord instrumentation.'
        },
        :proxy_host => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a host for communicating with the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector) via a proxy server.'
        },
        :proxy_pass => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :exclude_from_reported_settings => true,
          :description => 'Defines a password for communicating with the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector) via a proxy server.'
        },
        :proxy_port => {
          :default => 8080,
          :allow_nil => true,
          :public => true,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'Defines a port for communicating with the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector) via a proxy server.'
        },
        :proxy_user => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :exclude_from_reported_settings => true,
          :description => 'Defines a user for communicating with the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector) via a proxy server.'
        },
        :security_policies_token => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Applies Language Agent Security Policy settings.'
        },
        :send_data_on_exit => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables the exit handler that sends data to the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector) before shutting down.'
        },
        :sync_startup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When set to `true`, forces a synchronous connection to the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector) during application startup. For very short-lived processes, this helps ensure the New Relic agent has time to report.'
        },
        :thread_local_tracer_state => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, tracer state storage is thread-local, otherwise, fiber-local'
        },
        :timeout => {
          :default => 2 * 60, # 2 minutes
          :public => true,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'Defines the maximum number of seconds the agent should spend attempting to connect to the collector.'
        },
        # Transaction tracer
        :'transaction_tracer.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, enables collection of [transaction traces](/docs/apm/traces/transaction-traces/transaction-traces).'
        },
        :'transaction_tracer.explain_enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, enables the collection of explain plans in transaction traces. This setting will also apply to explain plans in slow SQL traces if [`slow_sql.explain_enabled`](#slow_sql-explain_enabled) is not set separately.'
        },
        :'transaction_tracer.explain_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Threshold (in seconds) above which the agent will collect explain plans. Relevant only when [`explain_enabled`](#transaction_tracer.explain_enabled) is true.'
        },
        :'transaction_tracer.limit_segments' => {
          :default => 4000,
          :public => true,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Maximum number of transaction trace nodes to record in a single transaction trace.'
        },
        :'transaction_tracer.record_redis_arguments' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent records Redis command arguments in transaction traces.'
        },
        :'transaction_tracer.record_sql' => {
          :default => 'obfuscated',
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :description => 'Obfuscation level for SQL queries reported in transaction trace nodes.

  By default, this is set to `obfuscated`, which strips out the numeric and string literals.

  - If you do not want the agent to capture query information, set this to `none`.
  - If you want the agent to capture all query information in its original form, set this to `raw`.
  - When you enable [high security mode](/docs/agents/manage-apm-agents/configuration/high-security-mode), this is automatically set to `obfuscated`.'
        },

        :'transaction_tracer.stack_trace_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Specify a threshold in seconds. The agent includes stack traces in transaction trace nodes when the stack trace duration exceeds this threshold.'
        },
        :'transaction_tracer.transaction_threshold' => {
          :default => DefaultSource.transaction_tracer_transaction_threshold,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Specify a threshold in seconds. Transactions with a duration longer than this threshold are eligible for transaction traces. Specify a float value or the string `apdex_f`.'
        },
        # Error collector
        :'error_collector.ignore_classes' => {
          :default => ['ActionController::RoutingError', 'Sinatra::NotFound'],
          :public => true,
          :type => Array,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => <<~DESCRIPTION
            A list of error classes that the agent should ignore.

              <Callout variant="caution">
                This option can't be set via environment variable.
              </Callout>
          DESCRIPTION
        },
        :'error_collector.capture_events' => {
          :default => value_of(:'error_collector.enabled'),
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => 'If `true`, the agent collects [`TransactionError` events](/docs/insights/new-relic-insights/decorating-events/error-event-default-attributes-insights).'
        },
        :'error_collector.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent captures traced errors and error count metrics.'
        },
        :'error_collector.expected_classes' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => <<~DESCRIPTION
            A list of error classes that the agent should treat as expected.

              <Callout variant="caution">
                This option can't be set via environment variable.
              </Callout>
          DESCRIPTION
        },
        :'error_collector.expected_messages' => {
          :default => {},
          :public => true,
          :type => Hash,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => <<~DESCRIPTION
            A map of error classes to a list of messages. When an error of one of the classes specified here occurs, if its error message contains one of the strings corresponding to it here, that error will be treated as expected.

              <Callout variant="caution">
                This option can't be set via environment variable.
              </Callout>
          DESCRIPTION
        },
        :'error_collector.expected_status_codes' => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => 'A comma separated list of status codes, possibly including ranges. Errors associated with these status codes, where applicable, will be treated as expected.'
        },

        :'error_collector.ignore_messages' => {
          :default => {},
          :public => true,
          :type => Hash,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => <<~DESCRIPTION
            A map of error classes to a list of messages. When an error of one of the classes specified here occurs, if its error message contains one of the strings corresponding to it here, that error will be ignored.

              <Callout variant="caution">
                This option can't be set via environment variable.
              </Callout>
          DESCRIPTION
        },
        :'error_collector.ignore_status_codes' => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :dynamic_name => true,
          :description => 'A comma separated list of status codes, possibly including ranges. Errors associated with these status codes, where applicable, will be ignored.'
        },
        :'error_collector.max_backtrace_frames' => {
          :default => 50,
          :public => true,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'Defines the maximum number of frames in an error backtrace. Backtraces over this amount are truncated in the middle, preserving the beginning and the end of the stack trace.'
        },
        :'error_collector.max_event_samples_stored' => {
          :default => 100,
          :public => true,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Defines the maximum number of [`TransactionError` events](/docs/insights/new-relic-insights/decorating-events/error-event-default-attributes-insights) reported per harvest cycle.'
        },
        # Browser monitoring
        :'browser_monitoring.auto_instrument' => {
          :default => value_of(:'rum.enabled'),
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, enables [auto-injection](/docs/browser/new-relic-browser/installation-configuration/adding-apps-new-relic-browser#select-apm-app) of the JavaScript header for page load timing (sometimes referred to as real user monitoring or RUM).'
        },
        # CSP nonce
        :'browser_monitoring.content_security_policy_nonce' => {
          :default => value_of(:'rum.enabled'),
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables auto-injection of [Content Security Policy Nonce](https://content-security-policy.com/nonce/) in browser monitoring scripts. For now, auto-injection only works with Rails 5.2+.'
        },
        # Transaction events
        :'transaction_events.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, enables transaction event sampling.'
        },
        :'transaction_events.max_samples_stored' => {
          :default => 1200,
          :public => true,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Defines the maximum number of transaction events reported from a single harvest.'
        },
        # Application logging
        :'application_logging.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables log decoration and the collection of log events and metrics.'
        },
        :'application_logging.forwarding.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures log records emitted by your application.'
        },
        :'application_logging.forwarding.log_level' => {
          :default => 'debug',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :allowlist => %w[debug info warn error fatal unknown DEBUG INFO WARN ERROR FATAL UNKNOWN],
          :description => <<~DESCRIPTION
            Sets the minimum level a log event must have to be forwarded to New Relic.

            This is based on the integer values of Ruby's `Logger::Severity` constants: https://github.com/ruby/ruby/blob/master/lib/logger/severity.rb

            The intention is to forward logs with the level given to the configuration, as well as any logs with a higher level of severity.

            For example, setting this value to "debug" will forward all log events to New Relic. Setting this value to "error" will only forward log events with the levels "error", "fatal", and "unknown".

            Valid values (ordered lowest to highest):
              * "debug"
              * "info"
              * "warn"
              * "error"
              * "fatal"
              * "unknown"
          DESCRIPTION
        },
        :'application_logging.forwarding.custom_attributes' => {
          :default => {},
          :public => true,
          :type => Hash,
          :transform => DefaultSource.method(:convert_to_hash),
          :allowed_from_server => false,
          :description => 'A hash with key/value pairs to add as custom attributes to all log events forwarded to New Relic. If sending using an environment variable, the value must be formatted like: "key1=value1,key2=value2"'
        },
        :'application_logging.forwarding.max_samples_stored' => {
          :default => 10000,
          :public => true,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Defines the maximum number of log records to buffer in memory at a time.',
          :dynamic_name => true
        },
        :'application_logging.local_decorating.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent decorates logs with metadata to link to entities, hosts, traces, and spans.'
        },
        :'application_logging.metrics.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent captures metrics related to logging for your application.'
        },
        # Attributes
        :'allow_all_headers' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables capture of all HTTP request headers for all destinations.'
        },
        :'attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables capture of attributes for all destinations.'
        },
        :'attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from all destinations. Allows `*` as wildcard at end.'
        },
        :'attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in all destinations. Allows `*` as wildcard at end.'
        },
        :'browser_monitoring.attributes.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures attributes from browser monitoring.'
        },
        :'browser_monitoring.attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from browser monitoring. Allows `*` as wildcard at end.'
        },
        :'browser_monitoring.attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in browser monitoring. Allows `*` as wildcard at end.'
        },
        :'error_collector.attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures attributes from error collection.'
        },
        :'error_collector.attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from error collection. Allows `*` as wildcard at end.'
        },
        :'error_collector.attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in error collection. Allows `*` as wildcard at end.'
        },
        :'span_events.attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures attributes on span events.'
        },
        :'span_events.attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from span events. Allows `*` as wildcard at end.'
        },
        :'span_events.attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include on span events. Allows `*` as wildcard at end.'
        },
        :'transaction_events.attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures attributes from transaction events.'
        },
        :'transaction_events.attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from transaction events. Allows `*` as wildcard at end.'
        },
        :'transaction_events.attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in transaction events. Allows `*` as wildcard at end.'
        },
        :'transaction_segments.attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures attributes on transaction segments.'
        },
        :'transaction_segments.attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from transaction segments. Allows `*` as wildcard at end.'
        },
        :'transaction_segments.attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include on transaction segments. Allows `*` as wildcard at end.'
        },
        :'transaction_tracer.attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent captures attributes from transaction traces.'
        },
        :'transaction_tracer.attributes.exclude' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from transaction traces. Allows `*` as wildcard at end.'
        },
        :'transaction_tracer.attributes.include' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in transaction traces. Allows `*` as wildcard at end.'
        },
        # Audit log
        :'audit_log.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables an audit log which logs communications with the New Relic [collector](/docs/using-new-relic/welcome-new-relic/get-started/glossary/#collector).'
        },
        :'audit_log.endpoints' => {
          :default => ['.*'],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_regexp_list),
          :description => 'List of allowed endpoints to include in audit log.'
        },
        :'audit_log.path' => {
          :default => DefaultSource.audit_log_path,
          :documentation_default => 'log/newrelic_audit.log',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specifies a path to the audit log file (including the filename).'
        },
        # Autostart
        :'autostart.denylisted_constants' => {
          :default => %w[Rails::Command::ConsoleCommand
            Rails::Command::CredentialsCommand
            Rails::Command::Db::System::ChangeCommand
            Rails::Command::DbConsoleCommand
            Rails::Command::DestroyCommand
            Rails::Command::DevCommand
            Rails::Command::EncryptedCommand
            Rails::Command::GenerateCommand
            Rails::Command::InitializersCommand
            Rails::Command::NotesCommand
            Rails::Command::RoutesCommand
            Rails::Command::RunnerCommand
            Rails::Command::SecretsCommand
            Rails::Console
            Rails::DBConsole].join(','),
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specify a list of constants that should prevent the agent from starting automatically. Separate individual constants with a comma `,`. For example, `"Rails::Console,UninstrumentedBackgroundJob"`.'
        },
        :'autostart.denylisted_executables' => {
          :default => 'irb,rspec',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a comma-delimited list of executables that the agent should not instrument. For example, `"rake,my_ruby_script.rb"`.'
        },
        :'autostart.denylisted_rake_tasks' => {
          :default => AUTOSTART_DENYLISTED_RAKE_TASKS,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a comma-delimited list of Rake tasks that the agent should not instrument. For example, `"assets:precompile,db:migrate"`.'
        },
        # Code level metrics
        :'code_level_metrics.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => "If `true`, the agent will report source code level metrics for traced methods.\nSee: " \
                          'https://docs.newrelic.com/docs/apm/agents/ruby-agent/features/ruby-codestream-integration/'
        },
        # Cross application tracer
        :"cross_application_tracer.enabled" => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :deprecated => true,
          :description => deprecated_description(
            :'distributed_tracing.enabled',
            'If `true`, enables [cross-application tracing](/docs/agents/ruby-agent/features/cross-application-tracing-ruby/) when `distributed_tracing.enabled` is set to `false`.'
          )
        },
        # Custom attributes
        :'custom_attributes.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `false`, custom attributes will not be sent on events.'
        },
        :automatic_custom_instrumentation_method_list => {
          :default => NewRelic::EMPTY_ARRAY,
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => proc { |arr| NewRelic::Agent.add_automatic_method_tracers(arr) },
          :description => <<~DESCRIPTION
            An array of `CLASS#METHOD` (for instance methods) and/or `CLASS.METHOD` (for class methods) strings representing Ruby methods that the agent can automatically add custom instrumentation to. This doesn't require any modifications of the source code that defines the methods.

            Use fully qualified class names (using the `::` delimiter) that include any module or class namespacing.

            Here is some Ruby source code that defines a `render_png` instance method for an `Image` class and a `notify` class method for a `User` class, both within a `MyCompany` module namespace:

            ```ruby
            module MyCompany
              class Image
                def render_png
                  # code to render a PNG
                end
              end

              class User
                def self.notify
                  # code to notify users
                end
              end
            end
            ```

            Given that source code, the `newrelic.yml` config file might request instrumentation for both of these methods like so:

            ```yml
            automatic_custom_instrumentation_method_list:
              - MyCompany::Image#render_png
              - MyCompany::User.notify
            ```

            That configuration example uses YAML array syntax to specify both methods. Alternatively, you can use a comma-delimited string:

            ```yml
            automatic_custom_instrumentation_method_list: 'MyCompany::Image#render_png, MyCompany::User.notify'
            ```

            Whitespace around the comma(s) in the list is optional. When configuring the agent with a list of methods via the `NEW_RELIC_AUTOMATIC_CUSTOM_INSTRUMENTATION_METHOD_LIST` environment variable, use this comma-delimited string format:

            ```sh
            export NEW_RELIC_AUTOMATIC_CUSTOM_INSTRUMENTATION_METHOD_LIST='MyCompany::Image#render_png, MyCompany::User.notify'
            ```
          DESCRIPTION
        },
        # Custom events
        :'custom_insights_events.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent captures [custom events](/docs/insights/new-relic-insights/adding-querying-data/inserting-custom-events-new-relic-apm-agents).'
        },
        :'custom_insights_events.max_samples_stored' => {
          :default => 3000,
          :public => true,
          :type => Integer,
          :allowed_from_server => true,
          :dynamic_name => true,
          # Keep the extra two-space indent before the second bullet to appease translation tool
          :description => <<~DESC
            * Specify a maximum number of custom events to buffer in memory at a time.
              * When configuring the agent for [AI monitoring](/docs/ai-monitoring/intro-to-ai-monitoring), \
            set to max value `100000`. This ensures the agent captures the maximum amount of LLM events.
          DESC
        },
        # Datastore tracer
        :'datastore_tracer.database_name_reporting.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `false`, the agent will not add `database_name` parameter to transaction or slow sql traces.'
        },
        :'datastore_tracer.instance_reporting.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `false`, the agent will not report datastore instance metrics, nor add `host` or `port_path_or_id` parameters to transaction or slow SQL traces.'
        },
        # Disabling
        :disable_action_cable_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Action Cable instrumentation.'
        },
        # TODO: by subscribing to process_middleware.action_dispatch events,
        #       we duplicate the efforts already performed by non-notifications
        #       based instrumentation. In future, we ought to determine the
        #       extent of the overlap and duplication and end up with only this
        #       notifications based approach existing and the monkey patching
        #       approach removed entirely. NOTE that we will likely not want to
        #       do so until we are okay with dropping support for Rails < v6,
        #       given that these events are available only for v6+.
        :disable_action_dispatch => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Action Dispatch instrumentation.'
        },
        :disable_action_controller => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Action Controller instrumentation.'
        },
        :disable_action_mailbox => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Action Mailbox instrumentation.'
        },
        :disable_action_mailer => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Action Mailer instrumentation.'
        },
        :disable_activejob => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Active Job instrumentation.'
        },
        :disable_active_storage => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Active Storage instrumentation.'
        },
        :disable_active_support => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Active Support instrumentation.'
        },
        :disable_active_record_instrumentation => {
          :default => value_of(:skip_ar_instrumentation),
          :documentation_default => false,
          :public => true,
          :type => Boolean,
          :aliases => %i[disable_activerecord_instrumentation],
          :allowed_from_server => false,
          :description => 'If `true`, disables Active Record instrumentation.'
        },
        :disable_active_record_notifications => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :aliases => %i[disable_activerecord_notifications],
          :allowed_from_server => false,
          :description => 'If `true`, disables instrumentation for Active Record 4+'
        },
        :disable_cpu_sampler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'If `true`, the agent won\'t sample the CPU usage of the host process.'
        },
        :disable_delayed_job_sampler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'If `true`, the agent won\'t measure the depth of Delayed Job queues.'
        },
        :disable_gc_profiler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables the use of `GC::Profiler` to measure time spent in garbage collection'
        },
        :disable_memory_sampler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'If `true`, the agent won\'t sample the memory usage of the host process.'
        },
        :disable_middleware_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => <<~DESCRIPTION
            If `true`, the agent won't wrap third-party middlewares in instrumentation (regardless of whether they are installed via `Rack::Builder` or Rails).

              <Callout variant="important">
                When middleware instrumentation is disabled, if an application is using middleware that could alter the response code, the HTTP status code reported on the transaction may not reflect the altered value.
              </Callout>
          DESCRIPTION
        },
        :disable_samplers => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables the collection of sampler metrics. Sampler metrics are metrics that are not event-based (such as CPU time or memory usage).'
        },
        :disable_sequel_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables [Sequel instrumentation](/docs/agents/ruby-agent/frameworks/sequel-instrumentation).'
        },
        :disable_sidekiq => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables [Sidekiq instrumentation](/docs/agents/ruby-agent/background-jobs/sidekiq-instrumentation).'
        },
        :disable_roda_auto_middleware => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables agent middleware for Roda. This middleware is responsible for advanced feature support such as [page load timing](/docs/browser/new-relic-browser/getting-started/new-relic-browser) and [error collection](/docs/apm/applications-menu/events/view-apm-error-analytics).'
        },
        :disable_sinatra_auto_middleware => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => <<~DESCRIPTION
            If `true`, disables agent middleware for Sinatra. This middleware is responsible for advanced feature support such as [cross application tracing](/docs/apm/transactions/cross-application-traces/cross-application-tracing), [page load timing](/docs/browser/new-relic-browser/getting-started/new-relic-browser), and [error collection](/docs/apm/applications-menu/events/view-apm-error-analytics).

                <Callout variant="important">
                  Cross application tracing is deprecated in favor of [distributed tracing](/docs/apm/distributed-tracing/getting-started/introduction-distributed-tracing). Distributed tracing is on by default for Ruby agent versions 8.0.0 and above. Middlewares are not required to support distributed tracing.

                  To continue using cross application tracing, update the following options in your `newrelic.yml` configuration file:

                  ```yaml
                  # newrelic.yml

                    cross_application_tracer:
                      enabled: true
                    distributed_tracing:
                      enabled: false
                  ```
                </Callout>
          DESCRIPTION
        },
        :disable_view_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables view instrumentation.'
        },
        :disable_vm_sampler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'If `true`, the agent won\'t [sample performance measurements from the Ruby VM](/docs/agents/ruby-agent/features/ruby-vm-measurements).'
        },
        # Distributed tracing
        :'distributed_tracing.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Distributed tracing lets you see the path that a request takes through your distributed system. Enabling distributed tracing changes the behavior of some New Relic features, so carefully consult the [transition guide](/docs/transition-guide-distributed-tracing) before you enable this feature.'
        },
        # Elasticsearch
        :'elasticsearch.capture_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent captures Elasticsearch queries in transaction traces.'
        },
        :'elasticsearch.obfuscate_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent obfuscates Elasticsearch queries in transaction traces.'
        },
        # Heroku
        :'heroku.use_dyno_names' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent uses Heroku dyno names as the hostname.'
        },
        :'heroku.dyno_name_prefixes_to_shorten' => {
          :default => %w[scheduler run],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Ordinarily the agent reports dyno names with a trailing dot and process ID (for example, `worker.3`). You can remove this trailing data by specifying the prefixes you want to report without trailing data (for example, `worker`).'
        },
        # Infinite tracing
        :'infinite_tracing.trace_observer.host' => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :external => :infinite_tracing,
          :description => 'Configures the hostname for the trace observer Host. ' \
            'When configured, enables tail-based sampling by sending all recorded spans ' \
            'to a trace observer for further sampling decisions, irrespective of any usual ' \
            'agent sampling decision.'
        },
        :'infinite_tracing.trace_observer.port' => {
          :default => 443,
          :public => true,
          :type => Integer,
          :allowed_from_server => false,
          :external => :infinite_tracing,
          :description => 'Configures the TCP/IP port for the trace observer Host'
        },
        # Instrumentation
        :'instrumentation.active_support_broadcast_logger' => {
          :default => instrumentation_value_from_boolean(:'application_logging.enabled'),
          :documentation_default => 'auto',
          :dynamic_name => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of `ActiveSupport::BroadcastLogger` at start up. May be one of: `auto`, `prepend`, `chain`, `disabled`. Used in Rails versions >= 7.1.'
        },
        :'instrumentation.active_support_logger' => {
          :default => instrumentation_value_from_boolean(:'application_logging.enabled'),
          :documentation_default => 'auto',
          :dynamic_name => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of `ActiveSupport::Logger` at start up. May be one of: `auto`, `prepend`, `chain`, `disabled`. Used in Rails versions below 7.1.'
        },
        :'instrumentation.async_http' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Async::HTTP at start up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.bunny' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of bunny at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.aws_sdk_lambda' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the aws_sdk_lambda library at start-up. May be one of `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.ruby_kafka' => {
          :default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the ruby-kafka library at start-up. May be one of `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.opensearch' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the opensearch-ruby library at start-up. May be one of `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.rdkafka' => {
          :default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the rdkafka library at start-up. May be one of `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.aws_sqs' => {
          :default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the aws-sdk-sqs library at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.dynamodb' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the aws-sdk-dynamodb library at start-up. May be one of `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.fiber' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the Fiber class at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.concurrent_ruby' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the concurrent-ruby library at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.curb' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Curb at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.delayed_job' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Delayed Job at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.elasticsearch' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the elasticsearch library at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.ethon' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of ethon at start up. May be one of `auto`, `prepend`, `chain`, `disabled`'
        },
        :'instrumentation.excon' => {
          :default => 'enabled',
          :documentation_default => 'enabled',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Excon at start-up. May be one of: `enabled`, `disabled`.'
        },
        :'instrumentation.grape' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Grape at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.grpc_client' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of gRPC clients at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.grpc.host_denylist' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_regexp_list),
          :description => %Q(Specifies a list of hostname patterns separated by commas that will match gRPC hostnames that traffic is to be ignored by New Relic for. New Relic's gRPC client instrumentation will ignore traffic streamed to a host matching any of these patterns, and New Relic's gRPC server instrumentation will ignore traffic for a server running on a host whose hostname matches any of these patterns. By default, no traffic is ignored when gRPC instrumentation is itself enabled. For example, `"private.com$,exception.*"`)
        },
        :'instrumentation.grpc_server' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of gRPC servers at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.httpclient' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of HTTPClient at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.httprb' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of http.rb gem at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.httpx' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of httpx at start up. May be one of `auto`, `prepend`, `chain`, `disabled`'
        },
        :'instrumentation.logger' => {
          :default => instrumentation_value_from_boolean(:'application_logging.enabled'),
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Ruby standard library Logger at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.logstasher' => {
          :default => instrumentation_value_from_boolean(:'application_logging.enabled'),
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the LogStasher library at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.memcache' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of dalli gem for Memcache at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.memcached' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of memcached gem for Memcache at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.memcache_client' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of memcache-client gem for Memcache at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.mongo' => {
          :default => 'enabled',
          :documentation_default => 'enabled',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Mongo at start-up. May be one of: `enabled`, `disabled`.'
        },
        :'instrumentation.net_http' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of `Net::HTTP` at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.ruby_openai' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the ruby-openai gem at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`. Defaults to `disabled` in high security mode.'
        },
        :'instrumentation.puma_rack' => {
          :default => value_of(:'instrumentation.rack'),
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of `Puma::Rack`. When enabled, the agent hooks into the ' \
                           '`to_app` method in `Puma::Rack::Builder` to find gems to instrument during ' \
                           'application startup. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.puma_rack_urlmap' => {
          :default => value_of(:'instrumentation.rack_urlmap'),
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of `Puma::Rack::URLMap` at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.rack' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Rack. When enabled, the agent hooks into the ' \
                           '`to_app` method in `Rack::Builder` to find gems to instrument during ' \
                           'application startup. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.rack_urlmap' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of `Rack::URLMap` at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.rake' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of rake at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.redis' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Redis at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.resque' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of resque at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.roda' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Roda at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.sinatra' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Sinatra at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.stripe' => {
          :default => 'enabled',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Stripe at startup. May be one of: `enabled`, `disabled`.'
        },
        :'instrumentation.view_component' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of ViewComponent at startup. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'stripe.user_data.include' => {
          default: NewRelic::EMPTY_ARRAY,
          public: true,
          type: Array,
          dynamic_name: true,
          allowed_from_server: false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => <<~DESCRIPTION
            An array of strings to specify which keys inside a Stripe event's `user_data` hash should be reported
            to New Relic. Each string in this array will be turned into a regular expression via `Regexp.new` to
            permit advanced matching. Setting the value to `["."]` will report all `user_data`.
          DESCRIPTION
        },
        :'stripe.user_data.exclude' => {
          default: NewRelic::EMPTY_ARRAY,
          public: true,
          type: Array,
          dynamic_name: true,
          allowed_from_server: false,
          :transform => DefaultSource.method(:convert_to_list),
          :description => <<~DESCRIPTION
            An array of strings to specify which keys and/or values inside a Stripe event's `user_data` hash should
            not be reported to New Relic. Each string in this array will be turned into a regular expression via
            `Regexp.new` to permit advanced matching. For each hash pair, if either the key or value is matched the
            pair will not be reported. By default, no `user_data` is reported, so this option should only be used if
            the `stripe.user_data.include` option is being used.
          DESCRIPTION
        },
        :'instrumentation.thread' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the Thread class at start-up to allow the agent to correctly nest spans inside of an asynchronous transaction. This does not enable the agent to automatically trace all threads created (see `instrumentation.thread.tracing`). May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.thread.tracing' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the Thread class at start-up to automatically add tracing to all Threads created in the application.'
        },
        :'thread_ids_enabled' => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If enabled, will append the current Thread and Fiber object ids onto the segment names of segments created in Threads and concurrent-ruby'
        },
        :'instrumentation.tilt' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of the Tilt template rendering library at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        :'instrumentation.typhoeus' => {
          :default => 'auto',
          :documentation_default => 'auto',
          :public => true,
          :type => String,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'Controls auto-instrumentation of Typhoeus at start-up. May be one of: `auto`, `prepend`, `chain`, `disabled`.'
        },
        # Message tracer
        :'message_tracer.segment_parameters.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent will collect metadata about messages and attach them as segment parameters.'
        },
        # Mongo
        :'mongo.capture_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent captures Mongo queries in transaction traces.'
        },
        :'mongo.obfuscate_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent obfuscates Mongo queries in transaction traces.'
        },
        # OpenSearch
        :'opensearch.capture_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent captures OpenSearch queries in transaction traces.'
        },
        :'opensearch.obfuscate_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent obfuscates OpenSearch queries in transaction traces.'
        },
        # Process host
        :'process_host.display_name' => {
          :default => proc { NewRelic::Agent::Hostname.get },
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specify a custom host name for [display in the New Relic UI](/docs/apm/new-relic-apm/maintenance/add-rename-remove-hosts#display_name).'
        },
        # Rails
        :'defer_rails_initialization' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :external => true, # this config is used directly from the ENV variables
          :allowed_from_server => false,
          :description => <<-DESCRIPTION
            If `true`, when the agent is in an application using Ruby on Rails, it will start after `config/initializers` run.

            <Callout variant="caution">
              This option may only be set by environment variable.
            </Callout>
          DESCRIPTION
        },
        # Rake
        :'rake.tasks' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_regexp_list),
          :description => 'Specify an Array of Rake tasks to automatically instrument. ' \
          'This configuration option converts the Array to a RegEx list. If you\'d like ' \
          'to allow all tasks by default, use `rake.tasks: [.+]`. No rake tasks will be ' \
          'instrumented unless they\'re added to this list. For more information, ' \
          'visit the [New Relic Rake Instrumentation docs](/docs/apm/agents/ruby-agent/background-jobs/rake-instrumentation).'
        },
        :'rake.connect_timeout' => {
          :default => 10,
          :public => true,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'Timeout for waiting on connect to complete before a rake task'
        },
        # Rules
        :'rules.ignore_url_regexes' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => true,
          :transform => DefaultSource.method(:convert_to_regexp_list),
          :description => 'Define transactions you want the agent to ignore, by specifying a list of patterns matching the URI you want to ignore. For more detail, see [the docs on ignoring specific transactions](/docs/agents/ruby-agent/api-guides/ignoring-specific-transactions/#config-ignoring).'
        },
        # Serverless
        :'serverless_mode.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :transform => proc { |bool| NewRelic::Agent::ServerlessHandler.env_var_set? || bool },
          :description => 'If `true`, the agent will operate in a streamlined mode suitable for use with short-lived ' \
                          'serverless functions. NOTE: Only AWS Lambda functions are supported currently and this ' \
                          "option is not intended for use without [New Relic's Ruby Lambda layer](https://docs.newrelic.com/docs/serverless-function-monitoring/aws-lambda-monitoring/get-started/monitoring-aws-lambda-serverless-monitoring/) offering."
        },
        # Sidekiq
        :'sidekiq.args.include' => {
          default: NewRelic::EMPTY_ARRAY,
          public: true,
          type: Array,
          dynamic_name: true,
          allowed_from_server: false,
          description: <<~SIDEKIQ_ARGS_INCLUDE.chomp.tr("\n", ' ')
            An array of strings that will collectively serve as an allowlist for filtering which Sidekiq
            job arguments get reported to New Relic. To capture any Sidekiq arguments,
            'job.sidekiq.args.*' must be added to the separate `:'attributes.include'` configuration option. Each
            string in this array will be turned into a regular expression via `Regexp.new` to permit advanced
            matching. For job argument hashes, if either a key or value matches the pair will be included. All
            matching job argument array elements and job argument scalars will be included.
          SIDEKIQ_ARGS_INCLUDE
        },
        :'sidekiq.args.exclude' => {
          default: NewRelic::EMPTY_ARRAY,
          public: true,
          type: Array,
          dynamic_name: true,
          allowed_from_server: false,
          description: <<~SIDEKIQ_ARGS_EXCLUDE.chomp.tr("\n", ' ')
            An array of strings that will collectively serve as a denylist for filtering which Sidekiq
            job arguments get reported to New Relic. To capture any Sidekiq arguments,
            'job.sidekiq.args.*' must be added to the separate `:'attributes.include'` configuration option. Each string
            in this array will be turned into a regular expression via `Regexp.new` to permit advanced matching.
            For job argument hashes, if either a key or value matches the pair will be excluded. All matching job
            argument array elements and job argument scalars will be excluded.
          SIDEKIQ_ARGS_EXCLUDE
        },
        # Slow SQL
        :'slow_sql.enabled' => {
          :default => value_of(:'transaction_tracer.enabled'),
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent collects [slow SQL queries](/docs/apm/applications-menu/monitoring/viewing-slow-query-details).'
        },
        :'slow_sql.explain_threshold' => {
          :default => value_of(:'transaction_tracer.explain_threshold'),
          :documentation_default => 0.5,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Specify a threshold in seconds. The agent collects [slow SQL queries](/docs/apm/applications-menu/monitoring/viewing-slow-query-details) and explain plans that exceed this threshold.'
        },
        :'slow_sql.explain_enabled' => {
          :default => value_of(:'transaction_tracer.explain_enabled'),
          :documentation_default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, the agent collects explain plans in slow SQL queries. If this setting is omitted, the [`transaction_tracer.explain_enabled`](#transaction_tracer-explain_enabled) setting will be applied as the default setting for explain plans in slow SQL as well.'
        },
        :'slow_sql.record_sql' => {
          :default => value_of(:'transaction_tracer.record_sql'),
          :documentation_default => 'obfuscated',
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :description => 'Defines an obfuscation level for slow SQL queries. Valid options are `obfuscated`, `raw`, or `none`.'
        },
        :'slow_sql.use_longer_sql_id' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Generate a longer `sql_id` for slow SQL traces. `sql_id` is used for aggregation of similar queries.'
        },
        # Span events
        :'span_events.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, enables span event sampling.'
        },
        :'span_events.queue_size' => {
          :default => 10_000,
          :public => true,
          :type => Integer,
          :allowed_from_server => false,
          :external => :infinite_tracing,
          :description => 'Sets the maximum number of span events to buffer when streaming to the trace observer.'
        },
        :'span_events.max_samples_stored' => {
          :default => 2000,
          :public => true,
          :type => Integer,
          :allowed_from_server => true,
          # Keep the extra two-space indent before the second bullet to appease translation tool
          :description => <<~DESC
            * Defines the maximum number of span events reported from a single harvest. Any Integer between `1` and `10000` is valid.'
              * When configuring the agent for [AI monitoring](/docs/ai-monitoring/intro-to-ai-monitoring), set to max value `10000`.\
            This ensures the agent captures the maximum amount of distributed traces.
          DESC
        },
        # Strip exception messages
        :'strip_exception_messages.enabled' => {
          :default => value_of(:high_security),
          :documentation_default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If true, the agent strips messages from all exceptions except those in the [allowlist](#strip_exception_messages-allowlist). Enabled automatically in [high security mode](/docs/accounts-partnerships/accounts/security/high-security).'
        },
        :'strip_exception_messages.allowed_classes' => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_constant_list),
          :description => 'Specify a list of exceptions you do not want the agent to strip when [strip_exception_messages](#strip_exception_messages-enabled) is `true`. Separate exceptions with a comma. For example, `"ImportantException,PreserveMessageException"`.'
        },
        # Thread profiler
        :'thread_profiler.enabled' => {
          :default => DefaultSource.thread_profiler_enabled,
          :documentation_default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If `true`, enables use of the [thread profiler](/docs/apm/applications-menu/events/thread-profiler-tool).'
        },
        # Utilization
        :'utilization.detect_aws' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :description => 'If `true`, the agent automatically detects that it is running in an AWS environment.'
        },
        :'utilization.detect_azure' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :description => 'If `true`, the agent automatically detects that it is running in an Azure environment.'
        },
        :'utilization.detect_docker' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent automatically detects that it is running in Docker.'
        },
        :'utilization.detect_gcp' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :description => 'If `true`, the agent automatically detects that it is running in an Google Cloud Platform environment.'
        },
        :'utilization.detect_kubernetes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the agent automatically detects that it is running in Kubernetes.'
        },
        :'utilization.detect_pcf' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :description => 'If `true`, the agent automatically detects that it is running in a Pivotal Cloud Foundry environment.'
        },
        # Private
        :account_id => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'The account id associated with your application.'
        },
        :aggressive_keepalive => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If true, attempt to keep the TCP connection to the collector alive between harvests.'
        },
        :api_host => {
          :default => DefaultSource.api_host,
          :public => false,
          :type => String,
          :allowed_from_server => false,
          :description => 'API host for New Relic.'
        },
        :api_port => {
          :default => value_of(:port),
          :public => false,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'Port for the New Relic API host.'
        },
        :application_id => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Application ID for real user monitoring.'
        },
        :beacon => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Beacon for real user monitoring.'
        },
        :browser_key => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Real user monitoring license key for the browser timing header.'
        },
        :'browser_monitoring.loader' => {
          :default => 'rum',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Type of JavaScript agent loader to use for browser monitoring instrumentation.'
        },
        :'browser_monitoring.loader_version' => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Version of JavaScript agent loader (returned from the New Relic [collector](/docs/apm/new-relic-apm/getting-started/glossary#collector).)'
        },
        :'browser_monitoring.debug' => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable debugging version of JavaScript agent loader for browser monitoring instrumentation.'
        },
        :'browser_monitoring.ssl_for_http' => {
          :default => false,
          :allow_nil => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable HTTPS instrumentation by JavaScript agent on HTTP pages.'
        },
        :compressed_content_encoding => {
          :default => 'gzip',
          :public => false,
          :type => String,
          :allowed_from_server => false,
          :description => 'Encoding to use if data needs to be compressed. The options are deflate and gzip.'
        },
        :config_search_paths => {
          :default => DefaultSource.config_search_paths,
          :public => false,
          :type => Array,
          :allowed_from_server => false,
          :description => "An array of candidate locations for the agent's configuration file."
        },
        :cross_process_id => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Cross process ID for cross-application tracing.'
        },
        :data_report_period => {
          :default => 60,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic data collection service.'
        },
        :dispatcher => {
          :default => DefaultSource.dispatcher,
          :public => false,
          :type => Symbol,
          :allowed_from_server => false,
          :description => 'Autodetected application component that reports metrics to New Relic.'
        },
        :disable_harvest_thread => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable the harvest thread.'
        },
        :disable_rails_middleware => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Internal name for controlling Rails 3+ middleware instrumentation'
        },
        :enabled => {
          :default => true,
          :public => false,
          :type => Boolean,
          :aliases => [:enable],
          :allowed_from_server => false,
          :description => 'Enable or disable the agent.'
        },
        :encoding_key => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Encoding key for cross-application tracing.'
        },
        :entity_guid => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'The [Entity GUID](/attribute-dictionary/span/entityguid) for the entity running your agent.'
        },
        :error_beacon => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Error beacon for real user monitoring.'
        },
        :event_report_period => {
          :default => 60,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic event collection services.'
        },
        :'event_report_period.transaction_event_data' => {
          :default => 60,
          :public => false,
          :type => Integer,
          :dynamic_name => true,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic transaction event collection services.'
        },
        :'event_report_period.custom_event_data' => {
          :default => 60,
          :public => false,
          :type => Integer,
          :dynamic_name => true,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic custom event collection services.'
        },
        :'event_report_period.error_event_data' => {
          :default => 60,
          :public => false,
          :type => Integer,
          :dynamic_name => true,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic error event collection services.'
        },
        :'event_report_period.log_event_data' => {
          :default => 60,
          :public => false,
          :type => Integer,
          :dynamic_name => true,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic log event collection services.'
        },
        :'event_report_period.span_event_data' => {
          :default => 60,
          :public => false,
          :type => Integer,
          :dynamic_name => true,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic span event collection services.'
        },
        :force_reconnect => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Force a new connection to the server before running the worker loop. Creates a separate agent run and is recorded as a separate instance by the New Relic data collection service.'
        },
        :framework => {
          :default => DefaultSource.framework,
          :public => false,
          :type => Symbol,
          :allowed_from_server => false,
          :description => 'Autodetected application framework used to enable framework-specific functionality.'
        },
        :host => {
          :default => DefaultSource.host,
          :public => false,
          :type => String,
          :allowed_from_server => false,
          :description => 'URI for the New Relic data collection service.'
        },
        :'infinite_tracing.batching' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :external => :infinite_tracing,
          :description => 'If `true` (the default), data sent to the trace observer is batched instead of ' \
          'sending each span individually.'
        },
        :'infinite_tracing.compression_level' => {
          :default => :high,
          :public => true,
          :type => Symbol,
          :allowed_from_server => false,
          :allowlist => %i[none low medium high],
          :external => :infinite_tracing,
          :description => <<~DESC
            Configure the compression level for data sent to the trace observer.

              May be one of: `:none`, `:low`, `:medium`, `:high`.

              Set the level to `:none` to disable compression.
          DESC
        },
        :js_agent_file => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'JavaScript agent file for real user monitoring.'
        },
        :js_agent_loader => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'JavaScript agent loader content.',
          :exclude_from_reported_settings => true
        },
        :keep_alive_timeout => {
          :default => 60,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Timeout for keep alive on TCP connection to collector if supported by Ruby version. Only used in conjunction when aggressive_keepalive is enabled.'
        },
        :max_payload_size_in_bytes => {
          :default => 1000000,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Maximum number of bytes to send to the New Relic data collection service.'
        },
        :normalize_json_string_encodings => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Controls whether to normalize string encodings prior to serializing data for the collector to JSON.'
        },
        :port => {
          :default => 443,
          :public => false,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'Port for the New Relic data collection service.'
        },
        :primary_application_id => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'The primary id associated with your application.'
        },
        :put_for_data_send => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Use HTTP PUT requests instead of POST.'
        },
        :report_instance_busy => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable transmission of metrics recording the percentage of time application instances spend servicing requests (duty cycle metrics).'
        },
        :restart_thread_in_children => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Controls whether to check on running a transaction whether to respawn the harvest thread.'
        },
        :'resque.use_ruby_dns' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Replace the libc DNS resolver with the all Ruby resolver Resolv'
        },
        :'rum.enabled' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable page load timing (sometimes referred to as real user monitoring or RUM).'
        },
        :sampling_target => {
          :default => 10,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'The target number of transactions to mark as sampled during a sampled period.'
        },
        :sampling_target_period_in_seconds => {
          :default => 60,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'The period during which a target number of transactions should be marked as sampled.'
        },
        :send_environment_info => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable transmission of application environment information to the New Relic data collection service.'
        },
        :simple_compression => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When enabled the agent will compress payloads destined for the collector, but will not pre-compress parts of the payload.'
        },
        :skip_ar_instrumentation => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable active record instrumentation.'
        },
        :'synthetics.traces_limit' => {
          :default => 20,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Maximum number of synthetics transaction traces to hold for a given harvest'
        },
        :'synthetics.events_limit' => {
          :default => 200,
          :public => false,
          :type => Integer,
          :allowed_from_server => true,
          :description => 'Maximum number of synthetics transaction events to hold for a given harvest'
        },
        :test_mode => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Used in tests for the agent to start-up, but not connect to the collector. Formerly used `developer_mode` in test config for this purpose.'
        },
        :'thread_profiler.max_profile_overhead' => {
          :default => 0.05,
          :public => false,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Maximum overhead percentage for thread profiling before agent reduces polling frequency'
        },
        :trusted_account_ids => {
          :default => [],
          :public => false,
          :type => Array,
          :allowed_from_server => true,
          :description => 'List of trusted New Relic account IDs for the purposes of cross-application tracing. Inbound requests from applications including cross-application headers that do not come from an account in this list will be ignored.'
        },
        :trusted_account_key => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'A shared key to validate that a distributed trace payload came from a trusted account.'
        },
        :'utilization.billing_hostname' => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => String,
          :allowed_from_server => false,
          :description => 'The configured server name by a customer.'
        },
        :'utilization.logical_processors' => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'The total number of hyper-threaded execution contexts available.'
        },
        :'utilization.total_ram_mib' => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => Integer,
          :allowed_from_server => false,
          :description => 'This value represents the total amount of memory available to the host (not the process), in mebibytes (1024 squared or 1,048,576 bytes).'
        },
        # security agent
        :'security.agent.enabled' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => "If `true`, the security agent is loaded (a Ruby 'require' is performed)"
        },
        :'security.enabled' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, the security agent is started (the agent runs in its event loop)'
        },
        :'security.mode' => {
          :default => 'IAST',
          :external => true,
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :allowlist => %w[IAST RASP],
          :description => 'Defines the mode for the security agent to operate in. Currently only `IAST` is supported',
          :dynamic_name => true
        },
        :'security.validator_service_url' => {
          :default => 'wss://csec.nr-data.net',
          :external => true,
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :description => 'Defines the endpoint URL for posting security-related data',
          :dynamic_name => true
        },
        :'security.detection.rci.enabled' => {
          :default => true,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables RCI (remote code injection) detection'
        },
        :'security.detection.rxss.enabled' => {
          :default => true,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables RXSS (reflected cross-site scripting) detection'
        },
        :'security.detection.deserialization.enabled' => {
          :default => true,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, enables deserialization detection'
        },
        :'security.application_info.port' => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => Integer,
          :external => true,
          :allowed_from_server => false,
          :description => 'The port the application is listening on. This setting is mandatory for Passenger servers. Other servers should be detected by default.'
        },
        :'security.exclude_from_iast_scan.api' => {
          :default => [],
          :public => true,
          :type => Array,
          :external => true,
          :allowed_from_server => true,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Defines api paths you want the security agent to ignore in IAST scan, by specifying a list of patterns matching the URI you want to ignore.'
        },
        :'security.exclude_from_iast_scan.http_request_parameters.header' => {
          :default => [],
          :public => true,
          :type => Array,
          :external => true,
          :allowed_from_server => true,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Define http request headers you want the security agent to ignore in IAST scan, by specifying a list of patterns matching the header you want to ignore.'
        },
        :'security.exclude_from_iast_scan.http_request_parameters.query' => {
          :default => [],
          :public => true,
          :type => Array,
          :external => true,
          :allowed_from_server => true,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Defines http request query parameters you want the security agent to ignore in IAST scan, by specifying a list of patterns matching the http request query parameters you want to ignore.'
        },
        :'security.exclude_from_iast_scan.http_request_parameters.body' => {
          :default => [],
          :public => true,
          :type => Array,
          :external => true,
          :allowed_from_server => true,
          :transform => DefaultSource.method(:convert_to_list),
          :description => 'Defines key values in http request body you want the security agent to ignore in IAST scan, by specifying a list of keys in the http request body you want to ignore.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.insecure_settings' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables detection of low-severity insecure settings (e.g., hash, crypto, cookie, random generators, trust boundary).'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.invalid_file_access' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables file operation related IAST detections(File Access & Application integrity violation)'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.sql_injection' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables SQL injection detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.nosql_injection' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables NOSQL injection detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.ldap_injection' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables LDAP injection detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.javascript_injection' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables javascript injection detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.command_injection' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables system command injection detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.xpath_injection' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables XPATH injection detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.ssrf' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Sever-Side Request Forgery (SSRF) detection in IAST scans.'
        },
        :'security.exclude_from_iast_scan.iast_detection_category.rxss' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, disables Reflected Cross-Site Scripting (RXSS) detection in IAST scans.'
        },
        :'security.scan_schedule.delay' => {
          :default => 0,
          :public => true,
          :type => Integer,
          :external => true,
          :allowed_from_server => true,
          :description => 'Specifies the delay time (in minutes) before the IAST scan begins after the application starts.'
        },
        :'security.scan_schedule.duration' => {
          :default => 0,
          :public => true,
          :type => Integer,
          :external => true,
          :allowed_from_server => true,
          :description => 'Specifies the length of time (in minutes) that the IAST scan will run.'
        },
        :'security.scan_schedule.schedule' => {
          :default => '',
          :public => true,
          :type => String,
          :external => true,
          :allowed_from_server => true,
          :description => 'Specifies a cron expression that sets when the IAST scan should run.',
          :dynamic_name => true
        },
        :'security.scan_schedule.always_sample_traces' => {
          :default => false,
          :external => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If `true`, allows IAST to continuously gather trace data in the background. Collected data will be used by Security Agent to perform an IAST Scan at the scheduled time.'
        },
        :'security.scan_controllers.iast_scan_request_rate_limit' => {
          :default => 3600,
          :public => true,
          :type => Integer,
          :external => true,
          :allowed_from_server => true,
          :description => 'Sets the maximum number of HTTP requests allowed for the IAST scan per minute. Any Integer between 12 and 3600 is valid. The default value is 3600.'
        },
        :'security.scan_controllers.scan_instance_count' => {
          :default => 0,
          :public => true,
          :type => Integer,
          :external => true,
          :allowed_from_server => true,
          :description => 'The number of application instances for a specific entity on which IAST analysis is performed.'
        },
        :'security.scan_controllers.report_http_response_body' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :external => true,
          :allowed_from_server => true,
          :description => 'If `true`, enables the sending of HTTP responses bodies. Disabling this also disables Reflected Cross-Site Scripting (RXSS) vulnerability detection.'
        },
        :'security.iast_test_identifier' => {
          :default => nil,
          :public => true,
          :type => String,
          :external => true,
          :allowed_from_server => true,
          :description => 'This will allow users to run IAST for CI/CD'
        }
      }.freeze
      # rubocop:enable Metrics/CollectionLiteralLength
    end
  end
end
