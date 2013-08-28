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
            files.detect do |file|
              File.expand_path(file) if File.exists? file
            end
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
          Proc.new { NewRelic::Agent::Commands::ThreadProfiler.is_supported? }
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
          :description => 'Boolean value to enable or disable the agent.'
        },
        :monitor_mode => {
          :default => DefaultSource.monitor_mode,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value to enable or disable the transmission of data to the New Relic data collection service.'
        },
        :agent_enabled => {
          :default => DefaultSource.agent_enabled,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to enable or disable the agent.'
        },
        :'autostart.blacklisted_constants' => {
          :default => 'Rails::Console',
          :public => true,
          :type => String,
          :description => "Don't autostart the agent if we're in IRB or Rails console. This config option accepts a comma separated list of constants."
        },
        :'autostart.blacklisted_executables' => {
          :default => 'irb,rspec',
          :public => true,
          :type => String,
          :description => "Comma delimited list of executables that not be instrumented by the agent (e.g. 'rake,my_ruby_script.rb')."
        },
        :'autostart.blacklisted_rake_tasks' => {
          :default => AUTOSTART_BLACKLISTED_RAKE_TASKS,
          :public => true,
          :type => String,
          :description => "Comma delimited list of rake tasks that should not be instrumented by the agent (e.g. 'assets:precompile,db:migrate')."
        },
        :developer_mode => { :default => DefaultSource.developer_mode,
          :public => true,
          :type => Boolean,
          :description => "Boolean value to enable or disable developer mode, a local analytics package built into the agent for rack applications. Access developer mode analytics by visiting '/newrelic' in your application."
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
          :description => 'Threshold at which New Relic will begin alerting you. By default you will receive alerts when your Apdex score drops below 0.5, or more than half of your users are experiencing degraded application performance.'
        },
        :monitor_daemons => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value that enables the agent for background processes. No longer necessary as the agent now automatically instruments background processes.'
        },
        :multi_homed => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value that allows instrumentation for multiple applications on the same host bound to different interfaces serving the same port.'
        },
        :high_security => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value that enables several security features designed to protect data in an enterprise setting.'
        },
        :'strip_exception_messages.enabled' => {
          :default => DefaultSource.strip_exception_messages_enabled,
          :public => true,
          :type => String,
          :description => 'Boolean value that strips messages from all exceptions that are not specified in the whitelist. Enabled automatically in high security mode.'
        },
        :'strip_exception_messages.whitelist' => {
          :default => '',
          :public => true,
          :type => String,
          :description => "Comma separated list of exceptions that should show messages when strip_exception_messages is enabled (e.g. 'NewException, RelicException')."
        },
        :host => {
          :default => 'collector.newrelic.com',
          :public => false,
          :type => String,
          :description => "URI for New Relic's data collection service."
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
          :description => 'Port for use connecting to the New Relic data collection service.'
        },
        :api_port => {
          :default => DefaultSource.api_port,
          :public => false,
          :type => Fixnum,
          :description => 'Port for use connecting to the API host for New Relic.'
        },
        :ssl => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => "Boolean value to enable SSL for transmissions to New Relic's data collection service."
        },
        :sync_startup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to force the agent to connect to New Relic synchronously when your application starts.'
        },
        :send_data_on_exit => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value that installs an exit handler to send data to New Relic before shutting down.'
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
          :description => "Maximum number of seconds to try and contact New Relic's data collection service."
        },
        :force_send => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value that forces the agent to send data when shutting down.'
        },
        :send_environment_info => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => "Boolean value to enable transmission of the application environment information to New Relic's data collection service."
        },
        :start_channel_listener => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value to spawn a background thread that listens for connections from child processes. Primarily used for Resque instrumentation.'
        },
        :data_report_period => {
          :default => 60,
          :public => true,
          :type => Fixnum,
          :description => 'Number of seconds betwixt connections to the New Relic data collection service.'
        },
        :keep_retrying => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to retry connection to the New Relic data collection service.'
        },
        :report_instance_busy => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to enable the transmission of duty cycle metrics to the New Relic data collection service.'
        },
        :log_file_name => {
          :default => 'newrelic_agent.log',
          :public => true,
          :type => String,
          :description => 'Name of the agent log file.'
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
          :description => 'Log level to use for agent logging: error, warn, info or debug.'
        },
        :'audit_log.enabled' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to enable the audit log, a log of communications with the New Relic data collection service.'
        },
        :'audit_log.path' => {
          :default => DefaultSource.audit_log_path,
          :public => true,
          :type => String,
          :description => 'Path to the audit log file, excluding the filename.'
        },
        :disable_samplers => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to enable collection of sampler metrics, metrics that are not event based (e.g. CPU time or memory usage).'
        },
        :disable_resque => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable resque instrumentation.'
        },
        :disable_dj => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable delayed job instrumentation.'
        },
        :disable_sinatra => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable sinatra instrumentation.'
        },
        :disable_sinatra_auto_middleware => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable the agent middleware for sinatra. The middleware is responsible for instrumenting some advanced feature support for sinatra (e.g. Cross-application tracing, Real User Monitoring, Error collection).'
        },
        :disable_view_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable view instrumentation.'
        },
        :disable_backtrace_cleanup => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable the removal of the gem path (newrelic_rpm) from backtraces.'
        },
        :disable_harvest_thread => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value disable the harvest thread entirely.'
        },
        :skip_ar_instrumentation => {
          :default => false,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value to disable the active record instrumentation.'
        },
        :disable_activerecord_instrumentation => {
          :default => DefaultSource.disable_activerecord_instrumentation,
          :public => true,
          :type => String,
          :description => 'Boolean value to disable the active record instrumentation.'
        },
        :disable_memcache_instrumentation => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Boolean value to disable memcache instrumentation.'
        },
        :disable_mobile_headers => {
          :default => true,
          :public => false,
          :type => Boolean,
          :description => 'Boolean value to disable the injection of mobile response headers when mobile headers are present in the incoming request.'
        },
        :capture_params => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Capture params.'
        },
        :capture_memcache_keys => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Capture memcache keys.'
        },
        :textmate => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'Enable Textmate integration.'
        },
        :'transaction_tracer.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'Enable transaction tracer.'
        },
        :'transaction_tracer.transaction_threshold' => {
          :default => DefaultSource.transaction_tracer_transaction_threshold,
          :public => true,
          :type => String,
          :description => 'Transaction tracer transaction threshold.'
        },
        :'transaction_tracer.stack_trace_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'Transaction tracer explain threshold.'
        },
        :'transaction_tracer.explain_threshold' => {
          :default => 0.5,
          :public => true,
          :type => Float,
          :description => 'FIXME'
        },
        :'transaction_tracer.explain_enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'transaction_tracer.record_sql' => {
          :default => 'obfuscated',
          :public => true,
          :type => String,
          :description => 'FIXME'
        },
        :'transaction_tracer.limit_segments' => {
          :default => 4000,
          :public => true,
          :type => Fixnum,
          :description => 'FIXME'
        },
        :'transaction_tracer.random_sample' => {
          :default => false,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :sample_rate => {
          :default => 10,
          :public => true,
          :type => Fixnum,
          :description => 'FIXME'
        },
        :'slow_sql.enabled' => {
          :default => DefaultSource.slow_sql_enabled,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'slow_sql.stack_trace_threshold' => {
          :default => DefaultSource.slow_sql_stack_trace_threshold,
          :public => true,
          :type => Float,
          :description => 'FIXME'
        },
        :'slow_sql.explain_threshold' => {
          :default => DefaultSource.slow_sql_explain_threshold,
          :public => true,
          :type => Float,
          :description => 'FIXME'
        },
        :'slow_sql.explain_enabled' => {
          :default => DefaultSource.slow_sql_explain_enabled,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'slow_sql.record_sql' => {
          :default => DefaultSource.slow_sql_record_sql,
          :public => true,
          :type => String,
          :description => 'FIXME'
        },
        :'error_collector.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'error_collector.capture_source' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'error_collector.ignore_errors' => {
          :default => 'ActionController::RoutingError,Sinatra::NotFound',
          :public => true,
          :type => String,
          :description => 'FIXME'
        },
        :'rum.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'rum.jsonp' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'rum.load_episodes_file' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'browser_monitoring.auto_instrument' => {
          :default => DefaultSource.browser_monitoring_auto_instrument,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :trusted_account_ids => {
          :default => [],
          :public => true,
          :type => Array,
          :description => 'FIXME'
        },
        :"cross_application_tracer.enabled" => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'thread_profiler.enabled' => {
          :default => DefaultSource.thread_profiler_enabled,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :marshaller => {
          :default => DefaultSource.marshaller,
          :public => true,
          :type => String,
          :description => 'FIXME'
        },
        :'request_sampler.enabled' => {
          :default => true,
          :public => true,
          :type => Boolean,
          :description => 'FIXME'
        },
        :'request_sampler.max_samples' => {
          :default => 1200,
          :public => true,
          :type => Fixnum,
          :description => 'FIXME'
        },
      }.freeze

    end
  end
end
