# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'

module NewRelic
  module Agent
    module Configuration
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

        def self.config_path
          Proc.new {
            files = []
            files << File.join("config","newrelic.yml")
            files << File.join("newrelic.yml")
            if ENV["HOME"]
              files << File.join(ENV["HOME"], ".newrelic", "newrelic.yml")
              files << File.join(ENV["HOME"], "newrelic.yml")
            end
            found_path = files.detect do |file|
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
            when defined?(::Rails)
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
            self[:enabled] && (self[:developer_mode] || self[:monitor_mode] || self[:monitor_daemons]) && ::NewRelic::Agent::Autostart.agent_should_start?
          }
        end

        def self.audit_log_path
          Proc.new {
            File.join(self[:log_file_path], 'newrelic_audit.log')
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

        def self.thread_profiler_enabled
          Proc.new { NewRelic::Agent::Threading::BacktraceService.is_supported? }
        end

        def self.browser_monitoring_auto_instrument
          Proc.new { self[:'rum.enabled'] }
        end

        def self.slow_sql_record_sql
          Proc.new { self[:'transaction_tracer.record_sql'] }
        end

        def self.slow_sql_explain_enabled
          Proc.new { self[:'transaction_tracer.explain_enabled'] }
        end

        def self.slow_sql_explain_threshold
          Proc.new { self[:'transaction_tracer.explain_threshold'] }
        end

        def self.slow_sql_stack_trace_threshold
          Proc.new { self[:'transaction_tracer.stack_trace_threshold'] }
        end

        def self.slow_sql_enabled
          Proc.new { self[:'transaction_tracer.enabled'] }
        end

        def self.transaction_tracer_transaction_threshold
          Proc.new { self[:apdex_t] * 4 }
        end

        def self.disable_activerecord_instrumentation
          Proc.new { self[:skip_ar_instrumentation] }
        end

        def self.api_port
          Proc.new { self[:port] }
        end

        def self.port
          Proc.new { self[:ssl] ? 443 : 80 }
        end

        def self.strip_exception_messages_enabled
          Proc.new { self[:high_security] }
        end

        def self.developer_mode
          Proc.new { self[:developer] }
        end

        def self.monitor_mode
          Proc.new { self[:enabled] }
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
        'spec:controllers',
        'spec:helpers',
        'spec:models',
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
          :description => "New Relic license key."
        },
        :log => {
          :default => '',
          :public => false,
          :type => String,
          :description => "Override to set log file name and path to STDOUT."
        },
        :omit_fake_collector => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => "Override to omit fake collector in multiverse tests."
        },
        :config_path => {
          :default => DefaultSource.config_path,
          :public => true,
          :type => String,
          :description => "Path to newrelic.yml. When omitted the agent will check (in order) 'config/newrelic.yml', 'newrelic.yml', $HOME/.newrelic/newrelic.yml' and $HOME/newrelic.yml."
        },
        :app_name => {
          :default => DefaultSource.app_name,
          :public => true,
          :type => String,
          :description => "Semicolon delimited list of application names where metrics will be recorded in the dashboard (e.g. 'MyApplication' or 'MyAppStaging;Instance1')."
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
        :enabled => {
          :default => true,
          :public => false,
          :type => Boolean,
          :aliases => [:enable],
          :description => 'Enable or disable the agent.'
        },
        :monitor_mode => {
          :default => DefaultSource.monitor_mode,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable transmission of data to the New Relic data collection service.'
        },
        :agent_enabled => {
          :default => DefaultSource.agent_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the agent.'
        },
        :'autostart.blacklisted_constants' => {
          :default => 'Rails::Console',
          :public => true,
          :type => String,
          :description => "Comma delimited list of constants whose presence should prevent the agent from automatically starting (e.g. 'Rails::Console, UninstrumentedBackgroundJob')."
        },
        :'autostart.blacklisted_executables' => {
          :default => 'irb,rspec',
          :public => true,
          :type => String,
          :description => "Comma delimited list of executables that should not be instrumented by the agent (e.g. 'rake,my_ruby_script.rb')."
        },
        :'autostart.blacklisted_rake_tasks' => {
          :default => AUTOSTART_BLACKLISTED_RAKE_TASKS,
          :public => true,
          :type => String,
          :description => "Comma delimited list of rake tasks that should not be instrumented by the agent (e.g. 'assets:precompile,db:migrate')."
        },
        :developer_mode => {
          :default => DefaultSource.developer_mode,
          :public => true,
          :type => Boolean,
          :description => "Enable or disable developer mode, a local analytics package built into the agent for rack applications. Access developer mode analytics by visiting '/newrelic' in your application."
        },
        :developer => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Alternative method of enabling developer_mode.'
        },
        :apdex_t => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'Threshold at which New Relic will begin alerting. By default the agent will send alerts when the Apdex score drops below 0.5, or when more than half of users are experiencing degraded application performance.'
        },
        :monitor_daemons => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enables or disables the agent for background processes. No longer necessary as the agent now automatically instruments background processes.'
        },
        :multi_homed => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable instrumentation for multiple applications on the same host bound to different interfaces serving the same port.'
        },
        :high_security => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable security features designed to protect data in an enterprise setting.'
        },
        :'strip_exception_messages.enabled' => {
          :default => DefaultSource.strip_exception_messages_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the stripping of messages from all exceptions that are not specified in the whitelist. Enabled automatically in high security mode.'
        },
        :'strip_exception_messages.whitelist' => {
          :default => '',
          :public => true,
          :type => String,
          :description => "Comma delimited list of exceptions that should not have their messages stripped when strip_exception_messages is enabled (e.g. 'ImportantException, PreserveMessageException')."
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
          :default => DefaultSource.api_port,
          :public => false,
          :type => Fixnum,
          :description => 'Port for the New Relic API host.'
        },
        :ssl => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => "Enable or disable SSL for transmissions to the New Relic data collection service."
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
          :description => 'Enable or disable the exit handler that sends data to the New Relic data collection service before shutting down.'
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
          :description => 'Maximum number of seconds to try and contact the New Relic data collection service.'
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
        :start_channel_listener => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable spawning of a background thread that listens for connections from child processes. Primarily used for Resque instrumentation.'
        },
        :'resque.use_harvest_lock' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable synchronizing Resque job forking with New Relic\'s harvest thread. Defaulted to false. This helps prevent Resque jobs from deadlocking, but pauses starting new jobs during harvest.'
        },
        :data_report_period => {
          :default => 60,
          :public => false,
          :type => Fixnum,
          :description => 'Number of seconds betwixt connections to the New Relic data collection service.'
        },
        :keep_retrying => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => '(Deprecated) Enable or disable retrying failed connections to the New Relic data collection service.'
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
          :description => 'Filename of the agent log file.'
        },
        :log_file_path => {
          :default => 'log/',
          :public => true,
          :type => String,
          :description => 'Path to the agent log file, excluding the filename.'
        },
        :log_level => {
          :default => 'info',
          :public => true,
          :type => String,
          :description => 'Log level for agent logging: error, warn, info or debug.'
        },
        :'audit_log.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the audit log, a log of communications with the New Relic data collection service.'
        },
        :'audit_log.path' => {
          :default => DefaultSource.audit_log_path,
          :public => true,
          :type => String,
          :description => 'Path to the audit log file (including the filename).'
        },
        :disable_samplers => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the collection of sampler metrics, metrics that are not event based (e.g. CPU time or memory usage).'
        },
        :disable_resque => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable resque instrumentation.'
        },
        :disable_dj => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable delayed job instrumentation.'
        },
        :disable_sinatra => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable sinatra instrumentation.'
        },
        :disable_sinatra_auto_middleware => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable agent middleware for sinatra. This middleware is responsible for instrumenting advanced feature support for sinatra (e.g. Cross-application tracing, Real User Monitoring, Error collection).'
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
          :description => 'Enable or disable removal of newrelic_rpm from backtraces.'
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
          :default => DefaultSource.disable_activerecord_instrumentation,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable active record instrumentation.'
        },
        :disable_memcache_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable memcache instrumentation.'
        },
        :capture_params => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable capturing and attachment of HTTP request parameters to transaction traces and traced errors.'
        },
        :'sidekiq.capture_params' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable capturing job arguments for transaction traces and traced errors in Sidekiq.'
        },
        :'resque.capture_params' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable capturing job arguments for transaction traces and traced errors in Resque.'
        },
        :capture_memcache_keys => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable capturing and attachment of memcache keys to transaction traces.'
        },
        :textmate => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Enables Textmate integration.'
        },
        :'transaction_tracer.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable transaction tracer.'
        },
        :'transaction_tracer.transaction_threshold' => {
          :default => DefaultSource.transaction_tracer_transaction_threshold,
          :public => true,
          :type => Float,
          :description => 'Transaction traces will be generated for transactions that exceed this threshold.'
        },
        :'transaction_tracer.stack_trace_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'Stack traces will be included in transaction trace segments with durations that exceed this threshold.'
        },
        :'transaction_tracer.explain_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'Explain plans will be generated and included in transaction trace segments with durations that exceed this threshold.'
        },
        :'transaction_tracer.explain_enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the generation and inclusion of explain queries in transaction trace segments.'
        },
        :'transaction_tracer.record_sql' => {
          :default => 'obfuscated',
          :public => true,
          :type => String,
          :description => "Obfuscation level for sql queries reported in transaction trace segments (e.g. 'obfuscated', 'raw', 'none')."
        },
        :'transaction_tracer.limit_segments' => {
          :default => 4000,
          :public => true,
          :type => Fixnum,
          :description => 'Maximum number of transaction trace segments to record in a single transaction trace.'
        },
        :'slow_sql.enabled' => {
          :default => DefaultSource.slow_sql_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable collection of slow sql queries.'
        },
        :'slow_sql.stack_trace_threshold' => {
          :default => DefaultSource.slow_sql_stack_trace_threshold,
          :public => true,
          :type => Float,
          :description => 'Stack traces will be generated and included in slow sql queries with durations that exceed this threshold.'
        },
        :'slow_sql.explain_threshold' => {
          :default => DefaultSource.slow_sql_explain_threshold,
          :public => true,
          :type => Float,
          :description => 'Explain plans will be generated and included in slow sql queries with durations that exceed this threshold.'
        },
        :'slow_sql.explain_enabled' => {
          :default => DefaultSource.slow_sql_explain_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the generation and inclusion of explain plans in slow sql queries.'
        },
        :'slow_sql.record_sql' => {
          :default => DefaultSource.slow_sql_record_sql,
          :public => true,
          :type => String,
          :description => "Obfuscation level for slow sql queries (e.g. 'obfuscated', 'raw', 'none')."
        },
        :'error_collector.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable recording of traced errors and error count metrics.'
        },
        :'error_collector.capture_source' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable collection of source code for errors that support it.'
        },
        :'error_collector.ignore_errors' => {
          :default => 'ActionController::RoutingError,Sinatra::NotFound',
          :public => true,
          :type => String,
          :description => 'Comma delimited list of error classes that should be ignored.'
        },
        :'rum.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable real user monitoring.'
        },
        :'rum.jsonp' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable jsonp as the default means of communicating with the beacon.'
        },
        :'rum.load_episodes_file' => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Enable or disable real user monitoring.'
        },
        :'browser_monitoring.auto_instrument' => {
          :default => DefaultSource.browser_monitoring_auto_instrument,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable automatic insertion of the real user monitoring header and footer into outgoing responses.'
        },
        :'js_agent_loader_version' => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'Version of the JavaScript agent loader retrieved by the collector. This is only informational, setting the value does nothing.'
        },
        :'js_agent_loader' => {
          :default => '',
          :public => false,
          :type => String,
          :description => 'JavaScript agent loader content.'
        },
        :'js_errors_beta' => {
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
          :description => 'Enable or disable cross-application tracing.'
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
          :description => 'Enable or disable X-Ray sessions.'
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
          :description => 'Marshaller to use when marshalling data for transmission to the New Relic data collection service (e.g json, pruby).'
        },
        :'analytics_events.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the analytics event sampling.'
        },
        :'analytics_events.transactions.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable or disable the analytics event sampling for transactions.'
        },
        :'analytics_events.max_samples_stored' => {
          :default => 1200,
          :public => false,
          :type => Fixnum,
          :description => 'Maximum number of request events recorded by the analytics event sampling in a single harvest.'
        },
      }.freeze

    end
  end
end
