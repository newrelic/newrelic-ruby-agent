module NewRelic
  module Agent
    module Configuration
      DEFAULTS = {
        :config_path => File.join('config', 'newrelic.yml'),

        :app_name   => Proc.new { NewRelic::Control.instance.env },
        :dispatcher => Proc.new { NewRelic::Control.instance.local_env.dispatcher },

        :enabled         => true,
        :monitor_mode    => Proc.new { self[:enabled] },
        :agent_enabled   => Proc.new do
          self[:enabled] &&
          (self[:developer_mode] || self[:monitor_mode] || self[:monitor_daemons]) &&
          !!NewRelic::Control.instance.local_env.dispatcher
        end,
        :developer_mode  => Proc.new { self[:developer] },
        :developer       => false,
        :apdex_t         => 0.5,
        :monitor_daemons => false,
        :multi_homed     => false,

        :host               => 'collector.newrelic.com',
        :api_host           => 'rpm.newrelic.com',
        :port               => Proc.new { self[:ssl] ? 443 : 80 },
        :api_port           => Proc.new { self[:port] },
        :ssl                => false,
        :verify_certificate => false,
        :sync_startup       => false,
        :send_data_on_exit  => true,
        :post_size_limit    => 2 * 1024 * 1024, # 2 megs
        :timeout            => 2 * 60,          # 2 minutes

        :log_file_name => 'newrelic_agent.log',
        :log_file_path => 'log/',
        :log_level     => 'info',

        :disable_samplers                     => false,
        :disable_resque                       => false,
        :disable_dj                           => false,
        :disable_view_instrumentation         => false,
        :disable_backtrace_cleanup            => false,
        :disable_activerecord_instrumentation => false,
        :disable_memcache_instrumentation     => false,
        :disable_mobile_headers               => true,

        :capture_memcache_keys => false,
        :multi_threaded        => false,
        :textmate              => false,

        :'transaction_tracer.enabled'               => true,
        :'transaction_tracer.transaction_threshold' => Proc.new { self[:apdex_t] * 4 },
        :'transaction_tracer.stack_trace_threshold' => 0.5,
        :'transaction_tracer.explain_threshold'     => 0.5,
        :'transaction_tracer.explain_enabled'       => true,
        :'transaction_tracer.record_sql'            => 'obfuscated',
        :'transaction_tracer.limit_segments'        => 4000,
        :'transaction_tracer.random_sample'         => false,

        :'slow_sql.enabled'               => Proc.new { self[:'transaction_tracer.enabled'] },
        :'slow_sql.stack_trace_threshold' => Proc.new { self[:'transaction_tracer.stack_trace_threshold'] },
        :'slow_sql.explain_threshold'     => Proc.new { self[:'transaction_tracer.explain_threshold'] },
        :'slow_sql.explain_enabled'       => Proc.new { self[:'transaction_tracer.explain_enabled'] },
        :'slow_sql.record_sql'            => Proc.new { self[:'transaction_tracer.record_sql'] },

        :'error_collector.enabled'        => true,
        :'error_collector.capture_source' => true,
        :'error_collector.ignore_errors'  => 'ActionController::RoutingError'
      }.freeze
    end
  end
end
