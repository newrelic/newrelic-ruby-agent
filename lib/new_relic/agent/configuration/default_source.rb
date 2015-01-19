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
              File.expand_path(file) if File.exists? file
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
            (NewRelic::Agent.config[:developer_mode] || NewRelic::Agent.config[:monitor_mode] || NewRelic::Agent.config[:monitor_daemons]) &&
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

        def self.marshaller
          Proc.new { NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported? ? 'json' : 'pruby' }
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

        def self.rules_ignore
          Proc.new do |rules|
            rules = convert_to_list(rules)

            rules.map do |rule|
              /#{rule}/
            end
          end
        end

        def self.convert_to_list(value)
          case value
          when String
            value.split(',')
          when Array
            value
          else
            raise ArgumentError.new("Config value '#{value}' couldn't be turned into a list.")
          end
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
          :description => 'Your New Relic <a href="/docs/accounts-partnerships/accounts/account-setup/license-key">license key</a>.'
        },
        :agent_enabled => {
          :default => DefaultSource.agent_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the agent.'
        },
        :enabled => {
          :default => true,
          :public => false,
          :type => Boolean,
          :aliases => [:enable],
          :description => 'Enable or disable the agent.'
        },
        :app_name => {
          :default => DefaultSource.app_name,
          :public => true,
          :type => String,
          :description => 'Semicolon-delimited list of <a href="/docs/apm/new-relic-apm/installation-and-configuration/naming-your-application">application names</a> to which the agent will report metrics (e.g. \'MyApplication\' or \'MyAppStaging;Instance1\'). For more information, see <a href="/docs/apm/new-relic-apm/installation-and-configuration/naming-your-application">Naming your application</a>.'
        },
        :monitor_mode => {
          :default => value_of(:enabled),
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the transmission of data to the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>).'
        },
        :developer_mode => {
          :default => value_of(:developer),
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable developer mode, a local analytics package built into the agent for rack applications. Access developer mode analytics by visiting <b>/newrelic</b> in your application.'
        },
        :developer => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Alternative method of enabling developer_mode.'
        },
        :log_level => {
          :default => 'info',
          :public => true,
          :type => String,
          :description => 'Log level for agent logging: error, warn, info or debug.'
        },
        :high_security => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/accounts-partnerships/accounts/security/high-security">high security mode</a>, a suite of security features designed to protect data in an enterprise setting.'
        },
        :ssl => {
          :default => true,
          :allow_nil => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable SSL for transmissions to the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>). Defaults to true in versions 3.5.6 and higher.'
        },
        :proxy_host => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :description => 'Defines a host for communicating with New Relic via a proxy server.'
        },
        :proxy_port => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => Fixnum,
          :description => 'Defines a port for communicating with New Relic via a proxy server.'
        },
        :proxy_user => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :local_only => true,
          :description => 'Defines a user for communicating with New Relic via a proxy server.'
        },
        :proxy_pass => {
          :default => nil,
          :allow_nil => true,
          :public => true,
          :type => String,
          :local_only => true,
          :description => 'Defines a password for communicating with New Relic via a proxy server.'
        },
        :capture_params => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the capture of HTTP request parameters to be attached to transaction traces and traced errors.'
        },
        :config_path => {
          :default => DefaultSource.config_path,
          :public => true,
          :type => String,
          :description => 'Path to <b>newrelic.yml</b>. When omitted the agent will check (in order) <b>config/newrelic.yml</b>, <b>newrelic.yml</b>, <b>$HOME/.newrelic/newrelic.yml</b> and <b>$HOME/newrelic.yml</b>.'
        },
        :config_search_paths => {
          :default => DefaultSource.config_search_paths,
          :public => false,
          :type => Array,
          :description => "An array of candidate locations for the agent's configuration file."
        },
        :dispatcher => {
          :default => DefaultSource.dispatcher,
          :public => false,
          :type => Symbol,
          :description => 'Autodetected application component that reports metrics to New Relic.'
        },
        :framework => {
          :default => DefaultSource.framework,
          :public => false,
          :type => Symbol,
          :description => 'Autodetected application framework used to enable framework-specific functionality.'
        },
        :'autostart.blacklisted_constants' => {
          :default => 'Rails::Console',
          :public => true,
          :type => String,
          :description => 'Defines a comma-delimited list of constants. When these constants are present, the agent will not start automatically (e.g. \'Rails::Console, UninstrumentedBackgroundJob\').'
        },
        :'autostart.blacklisted_executables' => {
          :default => 'irb,rspec',
          :public => true,
          :type => String,
          :description => 'Defines a comma-delimited list of executables that should not be instrumented by the agent (e.g. \'rake,my_ruby_script.rb\').'
        },
        :'autostart.blacklisted_rake_tasks' => {
          :default => AUTOSTART_BLACKLISTED_RAKE_TASKS,
          :public => true,
          :type => String,
          :description => 'Defines a comma-delimited list of rake tasks that should not be instrumented by the agent (e.g. \'assets:precompile,db:migrate\').'
        },
        :'profiling.available' => {
          :default => DefaultSource.profiling_available,
          :public => false,
          :type => Boolean,
          :description => 'Determines if ruby-prof is available for developer mode profiling.'
        },
        :apdex_t => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :deprecated => true,
          :description => 'In versions 3.5.0 and higher, <a href="/docs/apm/new-relic-apm/apdex/changing-your-apdex-settings">set your Apdex T via the New Relic UI</a>. In addition to determining your <a href="/docs/apm/new-relic-apm/apdex/apdex-measuring-user-satisfaction">Apdex score</a>, Apdex T is the threshold at which New Relic will begin alerting. By default the agent will send alerts when the Apdex score drops below 0.5, or when more than half of users are experiencing degraded application performance.'
        },
        :monitor_daemons => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enables or disables the agent for background processes. No longer necessary as the agent now automatically instruments background processes.'
        },
        :'strip_exception_messages.enabled' => {
          :default => value_of(:high_security),
          :public => true,
          :type => Boolean,
          :description => 'Defines whether the agent should strip messages from all exceptions that are not specified in the whitelist. Enabled automatically in <a href="/docs/accounts-partnerships/accounts/security/high-security">high security mode</a>.'
        },
        :'strip_exception_messages.whitelist' => {
          :default => '',
          :public => true,
          :type => String,
          :description => 'Defines a comma-delimited list of exceptions from which the agent will not strip messages when <a href="#strip_exception_messages.enabled">strip_exception_messages</a> is enabled (such as \'ImportantException, PreserveMessageException\').'
        },
        :host => {
          :default => 'collector.newrelic.com',
          :public => false,
          :type => String,
          :description => "URI for the New Relic data collection service."
        },
        :api_host => {
          :default => 'rpm.newrelic.com',
          :public => false,
          :type => String,
          :description => 'API host for New Relic.'
        },
        :port => {
          :default => DefaultSource.port,
          :public => false,
          :type => Fixnum,
          :description => 'Port for the New Relic data collection service.'
        },
        :api_port => {
          :default => value_of(:port),
          :public => false,
          :type => Fixnum,
          :description => 'Port for the New Relic API host.'
        },
        :sync_startup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable synchronous connection to the New Relic data collection service during application startup.'
        },
        :send_data_on_exit => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the exit handler that sends data to the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>) before shutting down.'
        },
        :post_size_limit => {
          :default => 2 * 1024 * 1024, # 2MB
          :public => false,
          :type => Fixnum,
          :description => 'Maximum number of bytes to send to the New Relic data collection service.'
        },
        :timeout => {
          :default => 2 * 60, # 2 minutes
          :public => true,
          :type => Fixnum,
          :description => 'Maximum number of seconds to attempt to contact the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>).'
        },
        :force_send => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable the forced sending of data to the New Relic data collection service when shutting down.'
        },
        :send_environment_info => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable transmission of application environment information to the New Relic data collection service.'
        },
        :'resque.use_harvest_lock' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable synchronizing Resque job forking with New Relic\'s harvest thread. The default is <code>false</code>. This helps prevent Resque jobs from deadlocking, but prevents New Relic from starting new jobs during harvest.'
        },
        :data_report_period => {
          :default => 60,
          :public => false,
          :type => Fixnum,
          :description => 'Number of seconds betwixt connections to the New Relic data collection service. Note that transaction events have a separate report period, specified by data_report_periods.analytic_event_data.'
        },
        :'data_report_periods.analytic_event_data' => {
          :default => 60,
          :public => false,
          :type => Fixnum,
          :dynamic_name => true,
          :description => 'Number of seconds between connections to the New Relic data collection service for sending transaction event data.'
        },
        :keep_retrying => {
          :default => true,
          :public => false,
          :type => Boolean,
          :deprecated => true,
          :description => 'Enable or disable retrying failed connections to the New Relic data collection service.'
        },
        :force_reconnect => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Force a new connection to the server before running the worker loop. Creates a separate agent run and is recorded as a separate instance by the New Relic data collection service.'
        },
        :report_instance_busy => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable transmission of metrics recording the percentage of time application instances spend servicing requests (duty cycle metrics).'
        },
        :log_file_name => {
          :default => 'newrelic_agent.log',
          :public => true,
          :type => String,
          :description => 'Defines a name for the log file.'
        },
        :log_file_path => {
          :default => 'log/',
          :public => true,
          :type => String,
          :description => 'Defines a path to the agent log file, excluding the filename.'
        },
        :'audit_log.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the audit log, a log of communications with the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>).'
        },
        :'audit_log.path' => {
          :default => DefaultSource.audit_log_path,
          :public => true,
          :type => String,
          :description => 'Specifies a path to the audit log file (including the filename).'
        },
        :disable_samplers => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the collection of sampler metrics. Sampler metrics are metrics that are not event-based (such as CPU time or memory usage).'
        },
        :disable_resque => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/agents/ruby-agent/background-jobs/resque-instrumentation">Resque instrumentation</a>.'
        },
        :disable_sidekiq => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/agents/ruby-agent/background-jobs/sidekiq-instrumentation">Sidekiq instrumentation</a>.'
        },
        :disable_dj => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/agents/ruby-agent/background-jobs/delayedjob">Delayed::Job instrumentation</a>.'
        },
        :disable_sinatra => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/agents/ruby-agent/frameworks/sinatra-support">Sinatra instrumentation</a>.'
        },
        :disable_sinatra_auto_middleware => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable agent middleware for Sinatra. This middleware is responsible for Sinatra advanced feature support; for example, cross application tracing, page load timing (sometimes referred to as real user monitoring or RUM), and error collection.'
        },
        :disable_view_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable view instrumentation.'
        },
        :disable_backtrace_cleanup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Defines whether the agent will remove <code>newrelic_rpm</code> from backtraces.'
        },
        :disable_harvest_thread => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable the harvest thread.'
        },
        :skip_ar_instrumentation => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable active record instrumentation.'
        },
        :disable_activerecord_instrumentation => {
          :default => value_of(:skip_ar_instrumentation),
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable active record instrumentation.'
        },
        :disable_activejob => {
          :default => false,
          :public => true,
          :type => Boolean,
          :dynamic_name => true,
          :description => 'Enable or disable ActiveJob instrumentation.'
        },
        :disable_memcache_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable memcache instrumentation.'
        },
        :disable_gc_profiler => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the use of GC::Profiler to measure time spent in garbage collection'
        },
        :'sidekiq.capture_params' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the capture of job arguments for transaction traces and traced errors in Sidekiq.'
        },
        :'resque.capture_params' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the capture of job arguments for transaction traces and traced errors in Resque.'
        },
        :capture_memcache_keys => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the capture of memcache keys from transaction traces.'
        },
        :'transaction_tracer.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/apm/traces/transaction-traces/transaction-traces">transaction traces</a>.'
        },
        :'transaction_tracer.transaction_threshold' => {
          :default => DefaultSource.transaction_tracer_transaction_threshold,
          :public => true,
          :type => Float,
          :description => 'The agent will collect traces for transactions that exceed this time threshold (in seconds). Specify a float value or <code><a href="/docs/apm/new-relic-apm/getting-started/glossary#apdex_f">apdex_f</a></code>.'
        },
        :'transaction_tracer.record_sql' => {
          :default => 'obfuscated',
          :public => true,
          :type => String,
          :description => 'Obfuscation level for SQL queries reported in transaction trace segments. Valid options are <code>obfuscated</code>, <code>raw</code>, <code>none</code>.'
        },
        :'transaction_tracer.capture_attributes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable collection of <a href="/docs/apm/other-features/attributes/collecting-custom-attributes">custom attributes</a> on transaction traces.'
        },
        :'transaction_tracer.explain_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'Threshold (in seconds) above which the agent will collect explain plans. Relevant only when <code><a href="#transaction_tracer.explain_enabled">explain_enabled</a></code> is true.'
        },
        :'transaction_tracer.explain_enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the collection of explain plans in transaction traces. This setting will also apply to explain plans in Slow SQL traces if slow_sql.explain_enabled is not set separately.'
        },
        :'transaction_tracer.stack_trace_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'Stack traces will be included in transaction trace segments when their duration exceeds this threshold.'
        },
        :'transaction_tracer.limit_segments' => {
          :default => 4000,
          :public => true,
          :type => Fixnum,
          :description => 'Maximum number of transaction trace segments to record in a single transaction trace.'
        },
        :disable_sequel_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/agents/ruby-agent/frameworks/sequel-instrumentation">Sequel instrumentation</a>.'
        },
        :disable_database_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :deprecated => true,
          :description => 'Enable or disable Sequel instrumentation. This option is deprecated; instead, use <a href="/docs/agents/ruby-agent/installation-and-configuration/ruby-agent-configuration#disable_sequel_instrumentation"><code>disable_sequel_instrumentation</code></a>'
        },
        :disable_mongo => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install <a href="/docs/agents/ruby-agent/frameworks/mongo-instrumentation">instrumentation for the Mongo gem</a>.'
        },
        :'slow_sql.enabled' => {
          :default => value_of(:'transaction_tracer.enabled'),
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable collection of slow SQL queries.'
        },
        :'slow_sql.explain_threshold' => {
          :default => value_of(:'transaction_tracer.explain_threshold'),
          :public => true,
          :type => Float,
          :description => 'Defines a duration threshold, over which the agent will collect explain plans in slow SQL queries.'
        },
        :'slow_sql.explain_enabled' => {
          :default => value_of(:'transaction_tracer.explain_enabled'),
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the collection of explain plans in slow SQL queries. If this setting is omitted, the transaction_tracer.explain_enabled setting will be applied as the default setting for explain plans in Slow SQL as well.'
        },
        :'slow_sql.record_sql' => {
          :default => value_of(:'transaction_tracer.record_sql'),
          :public => true,
          :type => String,
          :description => 'Defines an obfuscation level for slow SQL queries. Valid options are <code>obfuscated</code>, <code>raw</code>, <code>none</code>).'
        },
        :'mongo.capture_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable capturing Mongo queries in transaction traces.'
        },
        :'mongo.obfuscate_queries' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable obfuscation of Mongo queries in transaction traces.'
        },
        :'error_collector.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable recording of traced errors and error count metrics.'
        },
        :'error_collector.capture_attributes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable collection of custom attributes on errors.'
        },
        :'error_collector.ignore_errors' => {
          :default => 'ActionController::RoutingError,Sinatra::NotFound',
          :public => true,
          :type => String,
          :description => 'Specifies a comma-delimited list of error classes that the agent should ignore.'
        },
        :'rum.enabled' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable page load timing (sometimes referred to as real user monitoring or RUM).'
        },
        :browser_key => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Real user monitoring license key for the browser timing header.'
        },
        :beacon => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Beacon for real user monitoring.'
        },
        :error_beacon => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Error beacon for real user monitoring.'
        },
        :application_id => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Application ID for real user monitoring.'
        },
        :js_agent_file => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Javascript agent file for real user monitoring.'
        },
        :'browser_monitoring.auto_instrument' => {
          :default => value_of(:'rum.enabled'),
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable automatic insertion of the JavaScript header into outgoing responses for page load timing (sometimes referred to as real user monitoring or RUM).'
        },
        :'browser_monitoring.capture_attributes' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Forward custom attributes to Browser for <a href="/docs/insights/new-relic-insights/decorating-events/insights-custom-attributes#forwarding-attributes">collection by New Relic Insights</a>.'
        },
        :'browser_monitoring.loader' => {
          :default => DefaultSource.browser_monitoring_loader,
          :public => private,
          :type => String,
          :description => 'Type of JavaScript agent loader to use for browser monitoring instrumentation.'
        },
        :'browser_monitoring.loader_version' => {
          :default => '',
          :public => private,
          :type => String,
          :description => 'Version of JavaScript agent loader (returned from the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>).)'
        },
        :'browser_monitoring.debug' => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable debugging version of JavaScript agent loader for browser monitoring instrumentation.'
        },
        :'browser_monitoring.ssl_for_http' => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable HTTPS instrumentation by JavaScript agent on HTTP pages.'
        },
        :'capture_attributes.page_view_events' => {
          :default => false,
          :public => false,
          :type => Boolean,
          :deprecated => true,
          :description => 'Correct setting is browser_monitoring.capture_attributes.'
        },
        :js_agent_loader => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'JavaScript agent loader content.'
        },
        :js_errors_beta => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable beta JavaScript error reporting.'
        },
        :trusted_account_ids => {
          :default => [],
          :public => false,
          :type => Array,
          :description => 'List of trusted New Relic account IDs for the purposes of cross-application tracing. Inbound requests from applications including cross-application headers that do not come from an account in this list will be ignored.'
        },
        :"cross_application_tracer.enabled" => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/apm/traces/cross-application-traces/cross-application-traces">cross application tracing</a>.'
        },
        :cross_application_tracing => {
          :default => nil,
          :allow_nil => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/apm/traces/cross-application-traces/cross-application-traces">cross application tracing</a>.'
        },
        :encoding_key => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Encoding key for cross-application tracing.'
        },
        :cross_process_id => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Cross process ID for cross-application tracing.'
        },
        :'thread_profiler.enabled' => {
          :default => DefaultSource.thread_profiler_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the thread profiler.'
        },
        :'xray_session.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable <a href="/docs/apm/transactions-menu/x-ray-sessions/x-ray-sessions">X-Ray sessions</a>.'
        },
        :'xray_session.allow_traces' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable X-Ray sessions recording transaction traces.'
        },
        :'xray_session.allow_profiles' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable X-Ray sessions taking thread profiles.'
        },
        :'xray_session.max_samples' => {
          :default => 10,
          :public => false,
          :type => Fixnum,
          :description => 'Maximum number of transaction traces to buffer for active X-Ray sessions'
        },
        :'xray_session.max_profile_overhead' => {
          :default => 0.05,
          :public => false,
          :type => Float,
          :description => 'Maximum overhead percentage for thread profiling before agent reduces polling frequency'
        },
        :marshaller => {
          :default => DefaultSource.marshaller,
          :public => true,
          :type => String,
          :description => 'Specifies a marshaller for transmitting data to the New Relic <a href="/docs/apm/new-relic-apm/getting-started/glossary#collector">collector</a>) (e.g json, pruby).'
        },
        :'analytics_events.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable analytics event sampling.'
        },
        :'analytics_events.max_samples_stored' => {
          :default => 1200,
          :public => true,
          :type => Fixnum,
          :description => 'Defines the maximum number of request events reported from a single harvest.'
        },
        :'analytics_events.capture_attributes' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Include <a href="/docs/insights/new-relic-insights/decorating-events/insights-custom-attributes">custom attributes</a> in analytics event data.'
        },
        :restart_thread_in_children => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Controls whether to check on running a transaction whether to respawn the harvest thread.'
        },
        :normalize_json_string_encodings => {
          :default => DefaultSource.normalize_json_string_encodings,
          :public => false,
          :type => Boolean,
          :description => 'Controls whether to normalize string encodings prior to serializing data for the collector to JSON.'
        },
        :disable_vm_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will <a href="/docs/agents/ruby-agent/features/ruby-vm-measurements">sample performance measurements from the Ruby VM</a>.'
        },
        :disable_memory_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will sample the memory usage of the host process.'
        },
        :disable_cpu_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will sample the CPU usage of the host process.'
        },
        :disable_delayed_job_sampler => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will measure the depth of Delayed Job queues.'
        },
        :disable_active_record_4 => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install instrumentation for ActiveRecord 4.'
        },
        :disable_curb => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install instrumentation for the curb gem.'
        },
        :disable_excon => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install instrumentation for the excon gem.'
        },
        :disable_httpclient => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install instrumentation for the httpclient gem.'
        },
        :disable_net_http => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install instrumentation for Net::HTTP.'
        },
        :disable_rack => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will hook into Rack::Builder\'s <code>to_app</code> method to find gems to instrument during application startup.'
        },
        :disable_rubyprof => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will use RubyProf in developer mode (if RubyProf is installed).'
        },
        :disable_typhoeus => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :dynamic_name => true,
          :description  => 'Defines whether the agent will install instrumentation for the typhoeus gem.'
        },
        :disable_middleware_instrumentation => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :description  => 'Defines whether the agent will wrap third-party middlewares in instrumentation (regardless of whether they are installed via Rack::Builder or Rails).'
        },
        :disable_rails_middleware => {
          :default      => false,
          :public       => false,
          :type         => Boolean,
          :description  => 'Internal name for controlling Rails 3+ middleware instrumentation'
        },
        :'heroku.use_dyno_names' => {
          :default      => true,
          :public       => true,
          :type         => Boolean,
          :description  => 'Controls whether or not we use the heroku dyno name as the hostname.'
        },
        :'heroku.dyno_name_prefixes_to_shorten' => {
          :default      => ['scheduler', 'run'],
          :public       => true,
          :type         => Array,
          :transform    => DefaultSource.method(:convert_to_list),
          :description  => 'List of prefixes for heroku dyno names (such as "scheduler") to report as hostname without trailing dot and process ID.'
        },
        :labels => {
          :default      => '',
          :public       => true,
          :type         => String,
          :description  => 'A dictionary of label names and values that will be applied to the data sent from this agent. May also be expressed as a semi-colon delimited string of colon-separated pairs (e.g. "Server:One;Data Center:Primary".'
        },
        :aggressive_keepalive => {
          :default      => true,
          :public       => false,
          :type         => Boolean,
          :description  => 'If true, attempt to keep the TCP connection to the collector alive between harvests.'
        },
        :keep_alive_timeout => {
          :default      => 60,
          :public       => false,
          :type         => Fixnum,
          :description  => 'Timeout for keep alive on TCP connection to collector if supported by Ruby version. Only used in conjunction when aggressive_keepalive is enabled.'
        },
        :ca_bundle_path => {
          :default      => nil,
          :allow_nil    => true,
          :public       => true,
          :type         => String,
          :description  => "Manual override for the path to your local CA bundle. This CA bundle will be used to validate the SSL certificate presented by New Relic's data collection service."
        },
        :collect_utilization => {
          :default      => false,
          :public       => false,
          :type         => Boolean,
          :description  => "Controls whether to collect processor and instance sizing data and send it to New Relic"
        },
        :'rules.ignore_url_regexes' => {
          :default      => [],
          :public       => true,
          :type         => Array,
          :transform    => DefaultSource.rules_ignore,
          :description  => 'A list of patterns that will cause a transaction to be ignored if any of them match the URI.'
        },
        :'synthetics.traces_limit' => {
          :default      => 20,
          :public       => false,
          :type         => Fixnum,
          :description  => 'Maximum number of synthetics transaction traces to hold for a given harvest'
        },
        :'synthetics.events_limit' => {
          :default      => 200,
          :public       => false,
          :type         => Fixnum,
          :description  => 'Maximum number of synthetics transaction events to hold for a given harvest'
        },
        :'custom_insights_events.enabled' => {
          :default      => true,
          :public       => true,
          :type         => Boolean,
          :description  => 'Enable or disable custom Insights event recording.'
        },
        :'custom_insights_events.max_samples_stored' => {
          :default      => 1000,
          :public       => true,
          :type         => Fixnum,
          :description  => 'Maximum number of custom Insights events buffered in memory at a time.',
          :dynamic_name => true
        },
        :disable_grape_instrumentation => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :description  => 'Disables installation of Grape instrumentation.'
        },
        :disable_grape => {
          :default      => false,
          :public       => true,
          :type         => Boolean,
          :description  => 'Disables installation of Grape instrumentation.'
        }
      }.freeze
    end
  end
end
