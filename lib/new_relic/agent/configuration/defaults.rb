# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Configuration
      # This is so we can easily differentiate between the actual
      # default source and a Hash that was simply pushed onto the
      # config stack.
      class DefaultSource < Hash; end

      DEFAULTS = DefaultSource[
        :config_path => Proc.new {
          # Check a sequence of file locations for newrelic.yml
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
        },
        :app_name   => Proc.new { NewRelic::Control.instance.env },
        :dispatcher => Proc.new { NewRelic::Control.instance.local_env.discovered_dispatcher },
        :framework => Proc.new do
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
        end,
        :enabled         => true,
        :monitor_mode    => Proc.new { self[:enabled] },

        # agent_enabled determines whether the agent should try to start and
        # report data.
        :agent_enabled   => Proc.new do
          self[:enabled] &&
          (self[:developer_mode] || self[:monitor_mode] || self[:monitor_daemons]) &&
          ::NewRelic::Agent::Autostart.agent_should_start?
        end,
        # Don't autostart the agent if we're in IRB or Rails console.
        # This config option accepts a comma separated list of constants.
        :'autostart.blacklisted_constants' => 'Rails::Console',
        # Comma separated list of executables that you don't want to trigger
        # agents start. e.g. 'rake,my_ruby_script.rb'
        :'autostart.blacklisted_executables' => 'irb,rspec',
        :'autostart.blacklisted_rake_tasks' => 'about,assets:clean,assets:clobber,assets:environment,assets:precompile,db:create,db:drop,db:fixtures:load,db:migrate,db:migrate:status,db:rollback,db:schema:cache:clear,db:schema:cache:dump,db:schema:dump,db:schema:load,db:seed,db:setup,db:structure:dump,db:version,doc:app,log:clear,middleware,notes,notes:custom,rails:template,rails:update,routes,secret,spec,spec:controllers,spec:helpers,spec:models,spec:rcov,stats,test,test:all,test:all:db,test:recent,test:single,test:uncommitted,time:zones:all,tmp:clear,tmp:create',
        :developer_mode  => Proc.new { self[:developer] },
        :developer       => false,
        :apdex_t         => 0.5,
        :monitor_daemons => false,
        :multi_homed     => false,
        :high_security   => false,
        # Strip messages from all exceptions that are not specified in the whitelist.
        :'strip_exception_messages.enabled' => Proc.new { self[:high_security] },
        # Comma separated list of exceptions that should show messages when
        # strip_exception_messages is enabled (e.g. 'NewException, RelicException').
        :'strip_exception_messages.whitelist' => '',

        :host                   => 'collector.newrelic.com',
        :api_host               => 'rpm.newrelic.com',
        :port                   => Proc.new { self[:ssl] ? 443 : 80 },
        :api_port               => Proc.new { self[:port] },
        :ssl                    => true,
        :sync_startup           => false,
        :send_data_on_exit      => true,
        :post_size_limit        => 2 * 1024 * 1024, # 2 megs
        :timeout                => 2 * 60,          # 2 minutes
        :force_send             => false,
        :send_environment_info  => true,
        :start_channel_listener => false,
        :data_report_period     => 60,
        :keep_retrying          => true,
        :report_instance_busy   => true,

        :log_file_name => 'newrelic_agent.log',
        :log_file_path => 'log/',
        :log_level     => 'info',

        :'audit_log.enabled'      => false,
        :'audit_log.path'         => Proc.new {
          File.join(self[:log_file_path], 'newrelic_audit.log')
        },

        :disable_samplers                     => false,
        :disable_resque                       => false,
        :disable_dj                           => false,
        :disable_sinatra                      => false,
        :disable_sinatra_auto_middleware      => false,
        :disable_view_instrumentation         => false,
        :disable_backtrace_cleanup            => false,
        :disable_harvest_thread               => false,
        :skip_ar_instrumentation              => false,
        :disable_activerecord_instrumentation => Proc.new { self[:skip_ar_instrumentation] },
        :disable_memcache_instrumentation     => false,
        :disable_mobile_headers               => true,

        :capture_params        => false,
        :capture_memcache_keys => false,
        :textmate              => false,

        :'transaction_tracer.enabled'               => true,
        :'transaction_tracer.transaction_threshold' => Proc.new { self[:apdex_t] * 4 },
        :'transaction_tracer.stack_trace_threshold' => 0.5,
        :'transaction_tracer.explain_threshold'     => 0.5,
        :'transaction_tracer.explain_enabled'       => true,
        :'transaction_tracer.record_sql'            => 'obfuscated',
        :'transaction_tracer.limit_segments'        => 4000,
        :'transaction_tracer.random_sample'         => false,
        :sample_rate                                => 10,

        :'slow_sql.enabled'               => Proc.new { self[:'transaction_tracer.enabled'] },
        :'slow_sql.stack_trace_threshold' => Proc.new { self[:'transaction_tracer.stack_trace_threshold'] },
        :'slow_sql.explain_threshold'     => Proc.new { self[:'transaction_tracer.explain_threshold'] },
        :'slow_sql.explain_enabled'       => Proc.new { self[:'transaction_tracer.explain_enabled'] },
        :'slow_sql.record_sql'            => Proc.new { self[:'transaction_tracer.record_sql'] },

        :'error_collector.enabled'        => true,
        :'error_collector.capture_source' => true,
        :'error_collector.ignore_errors'  => 'ActionController::RoutingError,Sinatra::NotFound',

        :'rum.enabled'            => true,
        :'rum.jsonp'              => true,
        :'rum.load_episodes_file' => true,
        :'browser_monitoring.auto_instrument' => Proc.new { self[:'rum.enabled'] },

        :trusted_account_ids                => [],
        :"cross_application_tracer.enabled" => true,

        :'thread_profiler.enabled' => Proc.new { NewRelic::Agent::ThreadProfiler.is_supported? },

        :marshaller => Proc.new { NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported? ? 'json' : 'pruby' },

        :'request_sampler.enabled'        => true,
        :'request_sampler.sample_rate_ms' => 50
      ].freeze
    end
  end
end
