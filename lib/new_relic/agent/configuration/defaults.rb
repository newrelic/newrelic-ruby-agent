module NewRelic
  module Agent
    module Configuration
      DEFAULTS = {
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
              Agent.logger.error "Detected unsupported Rails version #{Rails::VERSION::STRING}"
            end
          when defined?(::Sinatra) && defined?(::Sinatra::Base) then :sinatra
          when defined?(::NewRelic::IA) then :external
          else :ruby
          end
        end,
        :enabled         => true,
        :monitor_mode    => Proc.new { self[:enabled] },
        :agent_enabled   => Proc.new do
          self[:enabled] &&
          (self[:developer_mode] || self[:monitor_mode] || self[:monitor_daemons]) &&
          !!NewRelic::Agent.config[:dispatcher]
        end,
        :developer_mode  => Proc.new { self[:developer] },
        :developer       => false,
        :apdex_t         => 0.5,
        :monitor_daemons => false,
        :multi_homed     => false,
        :high_security   => false,

        :host                   => 'collector.newrelic.com',
        :api_host               => 'rpm.newrelic.com',
        :port                   => Proc.new { self[:ssl] ? 443 : 80 },
        :api_port               => Proc.new { self[:port] },
        :ssl                    => false,
        :verify_certificate     => false,
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
        :disable_view_instrumentation         => false,
        :disable_backtrace_cleanup            => false,
        :skip_ar_instrumentation              => false,
        :disable_activerecord_instrumentation => Proc.new { self[:skip_ar_instrumentation] },
        :disable_memcache_instrumentation     => false,
        :disable_mobile_headers               => true,

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
        :'error_collector.ignore_errors'  => 'ActionController::RoutingError',

        :'rum.enabled'            => true,
        :'rum.jsonp'              => true,
        :'rum.load_episodes_file' => true,
        :'browser_monitoring.auto_instrument' => Proc.new { self[:'rum.enabled'] },

        :'cross_process.enabled'  => true,

        :'thread_profiler.enabled' => Proc.new { NewRelic::Agent::ThreadProfiler.is_supported? },

        :marshaller => Proc.new { NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported? ? 'json' : 'pruby' }
      }.freeze
    end
  end
end
