module NewRelic
  module Agent
    module Configuration
      DEFAULTS = {
        'config_path' => File.join('config', 'newrelic.yml'),

        'enabled'       => true,
        'monitor_mode'  => Proc.new { self['enabled'] },
        'apdex_t'       => 0.5,

        'host'               => 'collector.newrelic.com',
        'ssl'                => false,
        'verify_certificate' => false,
        'sync_startup'       => false,
        'send_data_on_exit'  => true,
        'post_size_limit'    => 2 * 1024 * 1024,

        'log_file_path' => 'log/',
        'log_level'     => 'info',

        'transaction_tracer.enabled'               => true,
        'transaction_tracer.stack_trace_threshold' => 0.5,
        'transaction_tracer.explain_threshold'     => 0.5,
        'transaction_tracer.explain_enabled'       => true,
        'transaction_tracer.record_sql'            => 'obfuscated',

        'slow_sql.enabled'               => Proc.new { self['transaction_tracer.enabled'] },
        'slow_sql.stack_trace_threshold' => Proc.new { self['transaction_tracer.stack_trace_threshold'] },
        'slow_sql.explain_threshold'     => Proc.new { self['transaction_tracer.explain_threshold'] },
        'slow_sql.explain_enabled'       => Proc.new { self['transaction_tracer.explain_enabled'] },
        'slow_sql.record_sql'            => Proc.new { self['transaction_tracer.record_sql'] }
      }.freeze
    end
  end
end
