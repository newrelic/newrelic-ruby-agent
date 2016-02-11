# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'

module NewRelic
  module Agent
    module Configuration

      # Helper since default Procs are evaluated in the context of this module
      def self.value_of(key)
        Proc.new do
          NewRelic::Agent.config[key]
        end
      end

      class Boolean; end

      class DefaultSource
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

        def self.transform_for(key)
          default_settings = ::NewRelic::Agent::Configuration::DEFAULTS[key]
          default_settings[:transform] if default_settings
        end

        def self.config_search_paths
          Proc.new {
            paths = [
              File.join("config","newrelic.yml"),
              File.join("newrelic.yml")
            ]

            if NewRelic::Control.instance.root
              paths << File.join(NewRelic::Control.instance.root, "config", "newrelic.yml")
              paths << File.join(NewRelic::Control.instance.root, "newrelic.yml")
            end

            if ENV["HOME"]
              paths << File.join(ENV["HOME"], ".newrelic", "newrelic.yml")
              paths << File.join(ENV["HOME"], "newrelic.yml")
            end

            # If we're packaged for warbler, we can tell from GEM_HOME
            if ENV["GEM_HOME"] && ENV["GEM_HOME"].end_with?(".jar!")
              app_name = File.basename(ENV["GEM_HOME"], ".jar!")
              paths << File.join(ENV["GEM_HOME"], app_name, "config", "newrelic.yml")
            end

            paths
          }
        end

        def self.config_path
          Proc.new {
            found_path = NewRelic::Agent.config[:config_search_paths].detect do |file|
              File.expand_path(file) if File.exist? file
            end
            found_path || ""
          }
        end

        def self.framework
          Proc.new {
            case
            when defined?(::NewRelic::TEST) then :test
            when defined?(::Merb) && defined?(::Merb::Plugins) then :merb
            when defined?(::Rails::VERSION)
              case Rails::VERSION::MAJOR
              when 0..2
                :rails
              when 3
                :rails3
              when 4
                :rails4
              when 5
                :rails5
              else
                ::NewRelic::Agent.logger.error "Detected unsupported Rails version #{Rails::VERSION::STRING}"
              end
            when defined?(::Sinatra) && defined?(::Sinatra::Base) then :sinatra
            when defined?(::NewRelic::IA) then :external
            else :ruby
            end
          }
        end

        def self.agent_enabled
          Proc.new {
            NewRelic::Agent.config[:enabled] &&
            (NewRelic::Agent.config[:developer_mode] || NewRelic::Agent.config[:monitor_mode]) &&
            NewRelic::Agent::Autostart.agent_should_start?
          }
        end

        def self.audit_log_path
          Proc.new {
            File.join(NewRelic::Agent.config[:log_file_path], 'newrelic_audit.log')
          }
        end

        def self.app_name
          Proc.new { NewRelic::Control.instance.env }
        end

        def self.dispatcher
          Proc.new { NewRelic::Control.instance.local_env.discovered_dispatcher }
        end

        # On Rubies with string encodings support (1.9.x+), default to always
        # normalize encodings since it's safest and fast. Without that support
        # the conversions are too expensive, so only enable if overridden to.
        def self.normalize_json_string_encodings
          Proc.new { NewRelic::LanguageSupport.supports_string_encodings? }
        end

        def self.thread_profiler_enabled
          Proc.new { NewRelic::Agent::Threading::BacktraceService.is_supported? }
        end

        # This check supports the js_errors_beta key we've asked clients to
        # set. Once JS errors are GA, browser_monitoring.loader can stop
        # being dynamic.
        def self.browser_monitoring_loader
          Proc.new { NewRelic::Agent.config[:js_errors_beta] ? "full" : "rum"}
        end

        def self.transaction_tracer_transaction_threshold
          Proc.new { NewRelic::Agent.config[:apdex_t] * 4 }
        end

        def self.port
          Proc.new { NewRelic::Agent.config[:ssl] ? 443 : 80 }
        end

        def self.profiling_available
          Proc.new {
            begin
              require 'ruby-prof'
              true
            rescue LoadError
              false
            end
          }
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

        def self.convert_to_constant_list(raw_value)
          const_names = convert_to_list(raw_value)
          const_names.map! do |class_name|
            const = ::NewRelic::LanguageSupport.constantize(class_name)

            unless const
              NewRelic::Agent.logger.warn("Ignoring unrecognized constant '#{class_name}' in #{raw_value}")
            end

            const
          end
          const_names.compact
        end
      end

      AUTOSTART_BLACKLISTED_RAKE_TASKS = [
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
        'tmp:create'
      ].join(',').freeze

      DEFAULTS = {
        :license_key => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Your New Relic <a href="https://docs.newrelic.com/docs/accounts-partnerships/accounts/account-setup/license-key">license key</a>.'
        },
        :agent_enabled => {
          :default => DefaultSource.agent_enabled,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, allows the Ruby agent to run.'
        },
        :enabled => {
          :default => true,
          :public => false,
          :type => Boolean,
          :aliases => [:enable],
          :allowed_from_server => false,
          :description => 'Enable or disable the agent.'
        },
        :app_name => {
          :default => DefaultSource.app_name,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specify the <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/installation-configuration/name-your-application">application name</a> used to aggregate data in the New Relic UI. To report data to <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/installation-configuration/using-multiple-names-app">multiple apps at the same time</a>, specify a list of names separated by a semicolon <code>;</code>. For example, <code>MyApp</code> or <code>MyStagingApp;Instance1</code>.'
        },
        :monitor_mode => {
          :default => value_of(:enabled),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When <code>true</code>, the agent transmits data about your app to the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>.'
        },
        :developer_mode => {
          :default => value_of(:developer),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When <code>true</code>, enables developer mode, a local analytics package built into the agent for rack applications. Access developer mode analytics by visiting <b>/newrelic</b> in your application.'
        },
        :developer => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Alternative method of enabling developer_mode.'
        },
        :log_level => {
          :default => 'info',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Sets the level of detail of log messages. Possible log levels, in increasing verbosity, are: <code>error</code>, <code>warn</code>, <code>info</code> or <code>debug</code>.'
        },
        :high_security => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, enables <a href="https://docs.newrelic.com/docs/accounts-partnerships/accounts/security/high-security">high security mode</a>. Ensure you understand the implications of high security mode before enabling this setting.'
        },
        :ssl => {
          :default => true,
          :allow_nil => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, enables SSL for transmissions to the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>.'
        },
        :proxy_host => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a host for communicating with the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a> via a proxy server.'
        },
        :proxy_port => {
          :default => 8080,
          :allow_nil => true,
          :public => true,
          :type => Fixnum,
          :allowed_from_server => false,
          :description => 'Defines a port for communicating with the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a> via a proxy server.'
        },
        :proxy_user => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :exclude_from_reported_settings => true,
          :description => 'Defines a user for communicating with the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a> via a proxy server.'
        },
        :proxy_pass => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :exclude_from_reported_settings => true,
          :description => 'Defines a password for communicating with the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a> via a proxy server.'
        },
        :capture_params => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When <code>true</code>, the agent captures HTTP request parameters and attaches them to transaction traces and traced errors.'
        },
        :config_path => {
          :default => DefaultSource.config_path,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Path to <b>newrelic.yml</b>. If undefined, the agent checks the following directories (in order): <b>config/newrelic.yml</b>, <b>newrelic.yml</b>, <b>$HOME/.newrelic/newrelic.yml</b> and <b>$HOME/newrelic.yml</b>.'
        },
        :config_search_paths => {
          :default => DefaultSource.config_search_paths,
          :public => false,
          :type => Array,
          :allowed_from_server => false,
          :description => "An array of candidate locations for the agent\'s configuration file."
        },
        :dispatcher => {
          :default => DefaultSource.dispatcher,
          :public => false,
          :type => Symbol,
          :allowed_from_server => false,
          :description => 'Autodetected application component that reports metrics to New Relic.'
        },
        :framework => {
          :default => DefaultSource.framework,
          :public => false,
          :type => Symbol,
          :allowed_from_server => false,
          :description => 'Autodetected application framework used to enable framework-specific functionality.'
        },
        :'autostart.blacklisted_constants' => {
          :default => 'Rails::Console',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specify a list of constants that should prevent the agent from starting automatically. Separate individual constants with a comma <code>,</code>. For example, <code>Rails::Console,UninstrumentedBackgroundJob</code>.'
        },
        :'autostart.blacklisted_executables' => {
          :default => 'irb,rspec',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a comma-delimited list of executables that the agent should not instrument. For example, <code>rake,my_ruby_script.rb</code>.'
        },
        :'autostart.blacklisted_rake_tasks' => {
          :default => AUTOSTART_BLACKLISTED_RAKE_TASKS,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a comma-delimited list of Rake tasks that the agent should not instrument. For example, <code>assets:precompile,db:migrate</code>.'
        },
        :disable_rake => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables Rake instrumentation.'
        },
        :disable_rake_instrumentation => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable Rake instrumentation. Preferred key is `disable_rake`'
        },
        :'rake.tasks' => {
          :default => [],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_regexp_list),
          :description => 'Specify an array of Rake tasks to automatically instrument.'
        },
        :'rake.connect_timeout' => {
          :default => 10,
          :public => true,
          :type => Fixnum,
          :allowed_from_server => false,
          :description => 'Timeout for waiting on connect to complete before a rake task'
        },
        :'profiling.available' => {
          :default => DefaultSource.profiling_available,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Determines if ruby-prof is available for developer mode profiling.'
        },
        :apdex_t => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :deprecated => true,
          :description => 'Deprecated. For agent versions 3.5.0 or higher, <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/apdex/changing-your-apdex-settings">set your Apdex T via the New Relic UI</a>.'
        },
        :'strip_exception_messages.enabled' => {
          :default => value_of(:high_security),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If true, the agent strips messages from all exceptions except those in the <a href="#strip_exception_messages-whitelist">whitelist</a>. Enabled automatically in <a href="https://docs.newrelic.com/docs/accounts-partnerships/accounts/security/high-security">high security mode</a>.'
        },
        :'strip_exception_messages.whitelist' => {
          :default => '',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_constant_list),
          :description => 'Specify a whitelist of exceptions you do not want the agent to strip when <a href="#strip_exception_messages-enabled">strip_exception_messages</a> is <code>true</code>. Separate exceptions with a comma. For example, <code>"ImportantException,PreserveMessageException"</code>.'
        },
        :host => {
          :default => 'collector.newrelic.com',
          :public => false,
          :type => String,
          :allowed_from_server => false,
          :description => "URI for the New Relic data collection service."
        },
        :api_host => {
          :default => 'rpm.newrelic.com',
          :public => false,
          :type => String,
          :allowed_from_server => false,
          :description => 'API host for New Relic.'
        },
        :port => {
          :default => DefaultSource.port,
          :public => false,
          :type => Fixnum,
          :allowed_from_server => false,
          :description => 'Port for the New Relic data collection service.'
        },
        :api_port => {
          :default => value_of(:port),
          :public => false,
          :type => Fixnum,
          :allowed_from_server => false,
          :description => 'Port for the New Relic API host.'
        },
        :sync_startup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'When set to <code>true</code>, forces a synchronous connection to the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a> during application startup. For very short-lived processes, this helps ensure the New Relic agent has time to report.'
        },
        :send_data_on_exit => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, enables the exit handler that sends data to the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a> before shutting down.'
        },
        :post_size_limit => {
          :default => 2 * 1024 * 1024, # 2MB
          :public => false,
          :type => Fixnum,
          :allowed_from_server => true,
          :description => 'Maximum number of bytes to send to the New Relic data collection service.'
        },
        :timeout => {
          :default => 2 * 60, # 2 minutes
          :public => true,
          :type => Fixnum,
          :allowed_from_server => false,
          :description => 'Defines the maximum number of seconds the agent should spend attempting to connect to the collector.'
        },
        :send_environment_info => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable transmission of application environment information to the New Relic data collection service.'
        },
        :data_report_period => {
          :default => 60,
          :public => false,
          :type => Fixnum,
          :allowed_from_server => true,
          :description => 'Number of seconds betwixt connections to the New Relic data collection service. Note that transaction events have a separate report period, specified by data_report_periods.analytic_event_data.'
        },
        :'data_report_periods.analytic_event_data' => {
          :default => 60,
          :public => false,
          :type => Fixnum,
          :dynamic_name => true,
          :allowed_from_server => true,
          :description => 'Number of seconds between connections to the New Relic data collection service for sending transaction event data.'
        },
        :keep_retrying => {
          :default => true,
          :public => false,
          :type => Boolean,
          :deprecated => true,
          :allowed_from_server => false,
          :description => 'Enable or disable retrying failed connections to the New Relic data collection service.'
        },
        :force_reconnect => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Force a new connection to the server before running the worker loop. Creates a separate agent run and is recorded as a separate instance by the New Relic data collection service.'
        },
        :report_instance_busy => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable transmission of metrics recording the percentage of time application instances spend servicing requests (duty cycle metrics).'
        },
        :log_file_name => {
          :default => 'newrelic_agent.log',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a name for the log file.'
        },
        :log_file_path => {
          :default => 'log/',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Defines a path to the agent log file, excluding the filename.'
        },
        :'audit_log.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, enables an audit log which logs communications with the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>.'
        },
        :'audit_log.path' => {
          :default => DefaultSource.audit_log_path,
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specifies a path to the audit log file (including the filename).'
        },
        :'audit_log.endpoints' => {
          :default => [".*"],
          :public => true,
          :type => Array,
          :allowed_from_server => false,
          :transform => DefaultSource.method(:convert_to_regexp_list),
          :description => 'List of allowed endpoints to include in audit log'
        },
        :disable_samplers => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables the collection of sampler metrics. Sampler metrics are metrics that are not event-based (such as CPU time or memory usage).'
        },
        :disable_resque => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables <a href="https://docs.newrelic.com/docs/agents/ruby-agent/background-jobs/resque-instrumentation">Resque instrumentation</a>.'
        },
        :disable_sidekiq => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables <a href="https://docs.newrelic.com/docs/agents/ruby-agent/background-jobs/sidekiq-instrumentation">Sidekiq instrumentation</a>.'
        },
        :disable_dj => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables <a href="https://docs.newrelic.com/docs/agents/ruby-agent/background-jobs/delayedjob">Delayed::Job instrumentation</a>.'
        },
        :disable_sinatra => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code> , disables <a href="https://docs.newrelic.com/docs/agents/ruby-agent/frameworks/sinatra-support">Sinatra instrumentation</a>.'
        },
        :disable_sinatra_auto_middleware => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables agent middleware for Sinatra. This middleware is responsible for advanced feature support such as <a href="https://docs.newrelic.com/docs/apm/transactions/cross-application-traces/cross-application-tracing">cross application tracing</a>, <a href="https://docs.newrelic.com/docs/browser/new-relic-browser/getting-started/new-relic-browser">page load timing</a>, and <a href="https://docs.newrelic.com/docs/apm/applications-menu/events/view-apm-error-analytics">error collection</a>.'
        },
        :disable_view_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables view instrumentation.'
        },
        :disable_backtrace_cleanup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent won\'t remove <code>newrelic_rpm</code> from backtraces.'
        },
        :disable_harvest_thread => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable the harvest thread.'
        },
        :skip_ar_instrumentation => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Enable or disable active record instrumentation.'
        },
        :disable_activerecord_instrumentation => {
          :default => value_of(:skip_ar_instrumentation),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables active record instrumentation.'
        },
        :disable_data_mapper => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables DataMapper instrumentation.'
        },
        :disable_activejob => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables ActiveJob instrumentation.'
        },
        :disable_memcached => {
          :default => value_of(:disable_memcache_instrumentation),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables instrumentation for the memcached gem.'
        },
        :disable_memcache_client => {
          :default => value_of(:disable_memcache_instrumentation),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables instrumentation for the memcache-client gem.'
        },
        :disable_dalli => {
          :default => value_of(:disable_memcache_instrumentation),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables instrumentation for the dalli gem.'
        },
        :disable_dalli_cas_client => {
          :default => value_of(:disable_memcache_instrumentation),
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => "If <code>true</code>, disables instrumentation for the dalli gem\'s additional CAS client support."
        },
        :disable_memcache_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables memcache instrumentation.'
        },
        :disable_gc_profiler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables the use of GC::Profiler to measure time spent in garbage collection'
        },
        :'sidekiq.capture_params' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :deprecated => true,
          :description => 'If <code>true</code>, enables the capture of job arguments for transaction traces and traced errors in Sidekiq.'
        },
        :'resque.capture_params' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :deprecated => true,
          :description => 'If <code>true</code>, enables the capture of job arguments for transaction traces and traced errors in Resque.'
        },
        :'resque.use_ruby_dns' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Replace the libc DNS resolver with the all Ruby resolver Resolv'
        },
        :capture_memcache_keys => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable the capture of memcache keys from transaction traces.'
        },
        :'transaction_tracer.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables collection of <a href="https://docs.newrelic.com/docs/apm/traces/transaction-traces/transaction-traces">transaction traces</a>.'
        },
        :'transaction_tracer.transaction_threshold' => {
          :default => DefaultSource.transaction_tracer_transaction_threshold,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Specify a threshold in seconds. Transactions with a duration longer than this threshold are eligible for transaction traces. Specify a float value or the string <code><a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#apdex_f">apdex_f</a></code>.'
        },
        :'transaction_tracer.record_sql' => {
          :default => 'obfuscated',
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :description => 'Obfuscation level for SQL queries reported in transaction trace nodes. Valid options are <code>obfuscated</code>, <code>raw</code>, or <code>none</code>.'
        },
        :'transaction_tracer.record_redis_arguments' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent records Redis command arguments in transaction traces.'
        },
        :'transaction_tracer.capture_attributes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :deprecated => true,
          :allowed_from_server => false,
          :description => 'Deprecated; use <a href="#transaction_tracer-attributes-enabled"><code>transaction_tracer.attributes.enabled</code></a> instead.'
        },
        :'transaction_tracer.explain_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Threshold (in seconds) above which the agent will collect explain plans. Relevant only when <code><a href="#transaction_tracer.explain_enabled">explain_enabled</a></code> is true.'
        },
        :'transaction_tracer.explain_enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables the collection of explain plans in transaction traces. This setting will also apply to explain plans in slow SQL traces if <a href="#slow_sql-explain_enabled"><code>slow_sql.explain_enabled</code></a> is not set separately.'
        },
        :'transaction_tracer.stack_trace_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Specify a threshold in seconds. The agent includes stack traces in transaction trace nodes when the stack trace duration exceeds this threshold.'
        },
        :'transaction_tracer.limit_segments' => {
          :default => 4000,
          :public => true,
          :type => Fixnum,
          :allowed_from_server => true,
          :description => 'Maximum number of transaction trace nodes to record in a single transaction trace.'
        },
        :disable_sequel_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, disables <a href="https://docs.newrelic.com/docs/agents/ruby-agent/frameworks/sequel-instrumentation">Sequel instrumentation</a>.'
        },
        :disable_database_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => false,
          :deprecated => true,
          :description => 'Deprecated; use <a href="#disable_sequel_instrumentation"><code>disable_sequel_instrumentation</code></a> instead.'
        },
        :disable_mongo => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :allowed_from_server => false,
          :dynamic_name => true,
          :description  => 'If <code>true</code>, the agent won\'t install <a href="https://docs.newrelic.com/docs/agents/ruby-agent/frameworks/mongo-instrumentation">instrumentation for the Mongo gem</a>.'
        },
        :disable_redis => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t install <a href="https://docs.newrelic.com/docs/agents/ruby-agent/frameworks/redis-instrumentation">instrumentation for Redis</a>.'
        },
        :disable_redis_instrumentation => {
          :default      => false,
          :public       => false,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'Disables installation of Redis instrumentation. Standard key to use is disable_redis.'
        },
        :'slow_sql.enabled' => {
          :default => value_of(:'transaction_tracer.enabled'),
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, the agent collects <a href="https://docs.newrelic.com/docs/apm/applications-menu/monitoring/viewing-slow-query-details">slow SQL queries</a>.'
        },
        :'slow_sql.explain_threshold' => {
          :default => value_of(:'transaction_tracer.explain_threshold'),
          :public => true,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Specify a threshold in seconds. The agent collects <a href="https://docs.newrelic.com/docs/apm/applications-menu/monitoring/viewing-slow-query-details">slow SQL queries</a> and explain plans that exceed this threshold.'
        },
        :'slow_sql.explain_enabled' => {
          :default => value_of(:'transaction_tracer.explain_enabled'),
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, the agent collects explain plans in slow SQL queries. If this setting is omitted, the <a href="#transaction_tracer-explain_enabled"><code>transaction_tracer.explain_enabled</code></a> setting will be applied as the default setting for explain plans in slow SQL as well.'
        },
        :'slow_sql.record_sql' => {
          :default => value_of(:'transaction_tracer.record_sql'),
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :description => 'Defines an obfuscation level for slow SQL queries. Valid options are <code>obfuscated</code>, <code>raw</code>, or <code>none</code>).'
        },
        :'slow_sql.use_longer_sql_id' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Generate a longer sql_id for slow SQL traces. sql_id is used for aggregation of similar queries.'
        },
        :'mongo.capture_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, the agent captures Mongo queries in transaction traces.'
        },
        :'mongo.obfuscate_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, the agent obfuscates Mongo queries in transaction traces.'
        },
        :'error_collector.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, the agent captures traced errors and error count metrics.'
        },
        :'error_collector.capture_attributes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :deprecated => true,
          :allowed_from_server => false,
          :description => 'Deprecated; use <a href="#error_collector-attributes-enabled"><code>error_collector.attributes.enabled</code></a> instead.'
        },
        :'error_collector.ignore_errors' => {
          :default => 'ActionController::RoutingError,Sinatra::NotFound',
          :public => true,
          :type => String,
          :allowed_from_server => true,
          :description => 'Specify a comma-delimited list of error classes that the agent should ignore.'
        },
        :'error_collector.capture_events' => {
          :default => value_of(:'error_collector.enabled'),
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, the agent collects <a href="https://docs.newrelic.com/docs/insights/new-relic-insights/decorating-events/error-event-default-attributes-insights">TransactionError events</a>.'
        },
        :'error_collector.max_event_samples_stored' => {
          :default => 100,
          :public => true,
          :type => Fixnum,
          :allowed_from_server => true,
          :description => 'Defines the maximum number of <a href="https://docs.newrelic.com/docs/insights/new-relic-insights/decorating-events/error-event-default-attributes-insights">TransactionError events</a> sent to Insights per harvest cycle.'
        },
        :'rum.enabled' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable page load timing (sometimes referred to as real user monitoring or RUM).'
        },
        :browser_key => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Real user monitoring license key for the browser timing header.'
        },
        :beacon => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Beacon for real user monitoring.'
        },
        :error_beacon => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Error beacon for real user monitoring.'
        },
        :application_id => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Application ID for real user monitoring.'
        },
        :js_agent_file => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Javascript agent file for real user monitoring.'
        },
        :'browser_monitoring.auto_instrument' => {
          :default => value_of(:'rum.enabled'),
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables <a href="https://docs.newrelic.com/docs/browser/new-relic-browser/installation-configuration/adding-apps-new-relic-browser#select-apm-app">auto-injection</a> of the JavaScript header for page load timing (sometimes referred to as real user monitoring or RUM).'
        },
        :'browser_monitoring.capture_attributes' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :deprecated => true,
          :allowed_from_server => false,
          :description => 'Deprecated; use <a href="#browser_monitoring-attributes-enabled"><code>browser_monitoring.attributes.enabled</code></a> instead.'
        },
        :'browser_monitoring.loader' => {
          :default => DefaultSource.browser_monitoring_loader,
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
          :description => 'Version of JavaScript agent loader (returned from the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>.)'
        },
        :'browser_monitoring.debug' => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable debugging version of JavaScript agent loader for browser monitoring instrumentation.'
        },
        :'browser_monitoring.ssl_for_http' => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable HTTPS instrumentation by JavaScript agent on HTTP pages.'
        },
        :js_agent_loader => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'JavaScript agent loader content.'
        },
        :js_errors_beta => {
          :default => false,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :deprecated => true,
          :description => 'Enable or disable beta JavaScript error reporting.'
        },
        :trusted_account_ids => {
          :default => [],
          :public => false,
          :type => Array,
          :allowed_from_server => true,
          :description => 'List of trusted New Relic account IDs for the purposes of cross-application tracing. Inbound requests from applications including cross-application headers that do not come from an account in this list will be ignored.'
        },
        :"cross_application_tracer.enabled" => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables <a href="https://docs.newrelic.com/docs/apm/transactions/cross-application-traces/cross-application-tracing">cross-application tracing</a>.'
        },
        :cross_application_tracing => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :deprecated => true,
          :description => 'Deprecated in favor of cross_application_tracer.enabled'
        },
        :encoding_key => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Encoding key for cross-application tracing.'
        },
        :cross_process_id => {
          :default => '',
          :public => false,
          :type => String,
          :allowed_from_server => true,
          :description => 'Cross process ID for cross-application tracing.'
        },
        :'thread_profiler.enabled' => {
          :default => DefaultSource.thread_profiler_enabled,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables use of the <a href="https://docs.newrelic.com/docs/apm/applications-menu/events/thread-profiler-tool">thread profiler</a>.'
        },
        :'xray_session.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables <a href="https://docs.newrelic.com/docs/apm/transactions-menu/x-ray-sessions/x-ray-sessions">X-Ray sessions</a>.'
        },
        :'xray_session.allow_traces' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable X-Ray sessions recording transaction traces.'
        },
        :'xray_session.allow_profiles' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'Enable or disable X-Ray sessions taking thread profiles.'
        },
        :'xray_session.max_samples' => {
          :default => 10,
          :public => false,
          :type => Fixnum,
          :allowed_from_server => true,
          :description => 'Maximum number of transaction traces to buffer for active X-Ray sessions'
        },
        :'xray_session.max_profile_overhead' => {
          :default => 0.05,
          :public => false,
          :type => Float,
          :allowed_from_server => true,
          :description => 'Maximum overhead percentage for thread profiling before agent reduces polling frequency'
        },
        :marshaller => {
          :default => 'json',
          :public => true,
          :type => String,
          :allowed_from_server => false,
          :description => 'Specifies a marshaller for transmitting data to the New Relic <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>. Currently <code>json</code> is the only valid value for this setting.'
        },
        :'analytics_events.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :allowed_from_server => true,
          :description => 'If <code>true</code>, enables analytics event sampling.'
        },
        :'analytics_events.max_samples_stored' => {
          :default => 1200,
          :public => true,
          :type => Fixnum,
          :allowed_from_server => true,
          :description => 'Defines the maximum number of request events reported from a single harvest.'
        },
        :'analytics_events.capture_attributes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :deprecated => true,
          :allowed_from_server => false,
          :description => 'Deprecated; use <a href="#transaction_events-attributes-enabled"><code>transaction_events.attributes.enabled</code></a> instead.'
        },
        :restart_thread_in_children => {
          :default => true,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Controls whether to check on running a transaction whether to respawn the harvest thread.'
        },
        :normalize_json_string_encodings => {
          :default => DefaultSource.normalize_json_string_encodings,
          :public => false,
          :type => Boolean,
          :allowed_from_server => false,
          :description => 'Controls whether to normalize string encodings prior to serializing data for the collector to JSON.'
        },
        :disable_vm_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t <a href="https://docs.newrelic.com/docs/agents/ruby-agent/features/ruby-vm-measurements">sample performance measurements from the Ruby VM</a>.'
        },
        :disable_memory_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t sample the memory usage of the host process.'
        },
        :disable_cpu_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t sample the CPU usage of the host process.'
        },
        :disable_delayed_job_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t measure the depth of Delayed Job queues.'
        },
        :disable_active_record_4 => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, disables instrumentation for ActiveRecord 4.'
        },
        :disable_curb => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, disables instrumentation for the curb gem.'
        },
        :disable_excon => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, disables instrumentation for the excon gem.'
        },
        :disable_httpclient => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, disables instrumentation for the httpclient gem.'
        },
        :disable_net_http => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, disables instrumentation for Net::HTTP.'
        },
        :disable_rack => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, prevents the agent from hooking into the <code>to_app</code> method in Rack::Builder to find gems to instrument during application startup.'
        },
        :disable_rack_urlmap => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, prevents the agent from hooking into Rack::URLMap to install middleware tracing.'
        },
        :disable_puma_rack => {
          :default      => value_of(:disable_rack),
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, prevents the agent from hooking into the <code>to_app</code> method in Puma::Rack::Builder to find gems to instrument during application startup.'
        },
        :disable_puma_rack_urlmap => {
          :default      => value_of(:disable_rack_urlmap),
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, prevents the agent from hooking into Puma::Rack::URLMap to install middleware tracing.'
        },
        :disable_rubyprof => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t use RubyProf in developer mode.'
        },
        :disable_typhoeus => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t install instrumentation for the typhoeus gem.'
        },
        :disable_middleware_instrumentation => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t wrap third-party middlewares in instrumentation (regardless of whether they are installed via Rack::Builder or Rails).'
        },
        :disable_rails_middleware => {
          :default      => false,
          :public       => false,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'Internal name for controlling Rails 3+ middleware instrumentation'
        },
        :'heroku.use_dyno_names' => {
          :default      => true,
          :public       => true,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent uses Heroku dyno names as the hostname.'
        },
        :'heroku.dyno_name_prefixes_to_shorten' => {
          :default      => ['scheduler', 'run'],
          :public       => true,
          :type         => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description  => 'Ordinarily the agent reports dyno names with a trailing dot and process ID (for example, <b>worker.3</b>). You can remove this trailing data by specifying the prefixes you want to report without trailing data (for example, <b>worker</b>).'
        },
        :'process_host.display_name' => {
          :default      => Proc.new{ NewRelic::Agent::Hostname.get },
          :public       => true,
          :type         => String,
          :allowed_from_server => false,
          :description  => 'Specify a custom host name for <a href="https://docs.newrelic.com/docs/apm/new-relic-apm/maintenance/add-rename-remove-hosts#display_name">display in the New Relic UI</a>.'
        },
        :labels => {
          :default      => '',
          :public       => true,
          :type         => String,
          :allowed_from_server => false,
          :description  => 'A dictionary of <a href="/docs/data-analysis/user-interface-functions/labels-categories-organize-your-apps-servers">label names</a> and values that will be applied to the data sent from this agent. May also be expressed as a semicolon-delimited <code>;</code> string of colon-separated <code>:</code> pairs. For example, <code><var>Server</var>:<var>One</var>;<var>Data Center</var>:<var>Primary</var></code>.'
        },
        :aggressive_keepalive => {
          :default      => true,
          :public       => false,
          :type         => Boolean,
          :allowed_from_server => true,
          :description  => 'If true, attempt to keep the TCP connection to the collector alive between harvests.'
        },
        :keep_alive_timeout => {
          :default      => 60,
          :public       => false,
          :type         => Fixnum,
          :allowed_from_server => true,
          :description  => 'Timeout for keep alive on TCP connection to collector if supported by Ruby version. Only used in conjunction when aggressive_keepalive is enabled.'
        },
        :ca_bundle_path => {
          :default      => nil,
          :allow_nil    => true,
          :public       => true,
          :type         => String,
          :allowed_from_server => false,
          :description  => "Manual override for the path to your local CA bundle. This CA bundle will be used to validate the SSL certificate presented by New Relic\'s data collection service."
        },
        :'rules.ignore_url_regexes' => {
          :default      => [],
          :public       => true,
          :type         => Array,
          :allowed_from_server => true,
          :transform    => DefaultSource.method(:convert_to_regexp_list),
          :description  => 'Define transactions you want the agent to ignore, by specifying a list of patterns matching the URI you want to ignore.'
        },
        :'synthetics.traces_limit' => {
          :default      => 20,
          :public       => false,
          :type         => Fixnum,
          :allowed_from_server => true,
          :description  => 'Maximum number of synthetics transaction traces to hold for a given harvest'
        },
        :'synthetics.events_limit' => {
          :default      => 200,
          :public       => false,
          :type         => Fixnum,
          :allowed_from_server => true,
          :description  => 'Maximum number of synthetics transaction events to hold for a given harvest'
        },
        :'custom_insights_events.enabled' => {
          :default      => true,
          :public       => true,
          :type         => Boolean,
          :allowed_from_server => true,
          :description  => 'If <code>true</code>, the agent captures <a href="/docs/insights/new-relic-insights/adding-querying-data/inserting-custom-events-new-relic-apm-agents">New Relic Insights custom events</a>.'
        },
        :'custom_insights_events.max_samples_stored' => {
          :default      => 1000,
          :public       => true,
          :type         => Fixnum,
          :allowed_from_server => true,
          :description  => 'Specify a maximum number of custom Insights events to buffer in memory at a time.',
          :dynamic_name => true
        },
        :disable_grape_instrumentation => {
          :default      => false,
          :public       => false,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t install Grape instrumentation.'
        },
        :disable_grape => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :allowed_from_server => false,
          :description  => 'If <code>true</code>, the agent won\'t install Grape instrumentation.'
        },
        :'attributes.enabled' => {
          :default     => true,
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, enables capture of attributes for all destinations.'
        },
        :'transaction_tracer.attributes.enabled' => {
          :default     => value_of(:'transaction_tracer.capture_attributes'),
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent captures attributes from transaction traces.'
        },
        :'transaction_events.attributes.enabled' => {
          :default     => value_of(:'analytics_events.capture_attributes'),
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent captures attributes from transaction events.'
        },
        :'error_collector.attributes.enabled' => {
          :default     => value_of(:'error_collector.capture_attributes'),
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent captures attributes from error collection.'
        },
        :'browser_monitoring.attributes.enabled' => {
          :default     => value_of(:'browser_monitoring.capture_attributes'),
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent captures attributes from browser monitoring.'
        },
        :'attributes.exclude' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform   => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from all destinations. Allows <code>*</code> as wildcard at end.'
        },
        :'transaction_tracer.attributes.exclude' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform   => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from transaction traces. Allows <code>*</code> as wildcard at end.'
        },
        :'transaction_events.attributes.exclude' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from transaction events. Allows <code>*</code> as wildcard at end.'
        },
        :'error_collector.attributes.exclude' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from error collection. Allows <code>*</code> as wildcard at end.'
        },
        :'browser_monitoring.attributes.exclude' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to exclude from browser monitoring. Allows <code>*</code> as wildcard at end.'
        },
        :'attributes.include' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in all destinations. Allows <code>*</code> as wildcard at end.'
        },
        :'transaction_tracer.attributes.include' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in transaction traces. Allows <code>*</code> as wildcard at end.'
        },
        :'transaction_events.attributes.include' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in transaction events. Allows <code>*</code> as wildcard at end.'
        },
        :'error_collector.attributes.include' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in error collection. Allows <code>*</code> as wildcard at end.'
        },
        :'browser_monitoring.attributes.include' => {
          :default     => [],
          :public      => true,
          :type        => Array,
          :allowed_from_server => false,
          :transform    => DefaultSource.method(:convert_to_list),
          :description => 'Prefix of attributes to include in browser monitoring. Allows <code>*</code> as wildcard at end.'
        },
        :'utilization.detect_aws' => {
          :default     => true,
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent automatically detects that it is running in an AWS environment.'
        },
        :'utilization.detect_docker' => {
          :default     => true,
          :public      => true,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'If <code>true</code>, the agent automatically detects that it is running in Docker.'
        },
        :'disable_utilization' => {
          :default     => false,
          :public      => false,
          :type        => Boolean,
          :allowed_from_server => false,
          :description => 'Disable sending utilization data as part of connect settings hash.'
        }
      }.freeze
    end
  end
end
