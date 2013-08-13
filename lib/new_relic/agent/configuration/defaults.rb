# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'forwardable'

module NewRelic
  module Agent
    module Configuration
      class DefaultSource
        extend Forwardable

        def initialize
          @defaults = ::NewRelic::Agent::Configuration::DEFAULTS
        end

        def [](key)
          @defaults[key][:default]
        end

        def_delegators :@defaults, :has_key?, :each, :merge, :delete, :to_hash
      end

      DEFAULTS = {
        :config_path                                => { :default => Proc.new {
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
                                                    }, :public => true, :description => 'Path to newrelic.yml (determined from a collection of predefined paths).' },

        :app_name                                   => { :default => Proc.new { NewRelic::Control.instance.env }, :public => true, :description => 'Application name.' },
        :dispatcher                                 => { :default => Proc.new { NewRelic::Control.instance.local_env.discovered_dispatcher }, :public => true, :description => 'Dispatcher.' },

        :framework                                  => { :default => Proc.new {
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
                                                    }, :public => true, :description => 'Framework.' },

        :enabled                                    => { :default => true, :public => true, :description => 'FIXME' },
        :monitor_mode                               => { :default => Proc.new { self[:enabled] }, :public => true, :description => 'FIXME' },

        :agent_enabled                              => { :default => Proc.new {
                                                      self[:enabled] && (self[:developer_mode] || self[:monitor_mode] || self[:monitor_daemons]) && ::NewRelic::Agent::Autostart.agent_should_start?
                                                    }, :public => true, :description => 'Determines whether or not the agent will try to start and report data.' },

        :'autostart.blacklisted_constants'          => { :default => 'Rails::Console', :public => true, :description => "Don't autostart the agent if we're in IRB or Rails console. This config option accepts a comma separated list of constants." },
        :'autostart.blacklisted_executables'        => { :default => 'irb,rspec', :public => true, :description => "Comma separated list of executables that won't trigger when agents start. e.g. 'rake,my_ruby_script.rb'"},
        :'autostart.blacklisted_rake_tasks'         => { :default => 'about,assets:clean,assets:clobber,assets:environment,assets:precompile,db:create,db:drop,db:fixtures:load,db:migrate,db:migrate:status,db:rollback,db:schema:cache:clear,db:schema:cache:dump,db:schema:dump,db:schema:load,db:seed,db:setup,db:structure:dump,db:version,doc:app,log:clear,middleware,notes,notes:custom,rails:template,rails:update,routes,secret,spec,spec:controllers,spec:helpers,spec:models,spec:rcov,stats,test,test:all,test:all:db,test:recent,test:single,test:uncommitted,time:zones:all,tmp:clear,tmp:create', :public => true, :description => 'FIXME'},
        :developer_mode                             => { :default => Proc.new { self[:developer] }, :public => true, :description => 'FIXME' },
        :developer                                  => { :default => false, :public => true, :description => 'FIXME' },
        :apdex_t                                    => { :default => 0.5, :public => true, :description => 'FIXME' },
        :monitor_daemons                            => { :default => false, :public => true, :description => 'FIXME' },
        :multi_homed                                => { :default => false, :public => true, :description => 'FIXME' },
        :high_security                              => { :default => false, :public => true, :description => 'FIXME' },

        :'strip_exception_messages.enabled'         => { :default => Proc.new { self[:high_security] }, :public => true, :description => 'Strip messages from all exceptions that are not specified in the whitelist.' },
        :'strip_exception_messages.whitelist'       => { :default => '', :public => true, :description => "Comma separated list of exceptions that should show messages when strip_exception_messages is enabled (e.g. 'NewException, RelicException')." },

        :host                                       => { :default => 'collector.newrelic.com', :public => true, :description => 'FIXME'},
        :api_host                                   => { :default => 'rpm.newrelic.com', :public => true, :description => 'FIXME'},
        :port                                       => { :default => Proc.new { self[:ssl] ? 443 : 80 }, :public => true, :description => 'FIXME' },
        :api_port                                   => { :default => Proc.new { self[:port] }, :public => true, :description => 'FIXME' },
        :ssl                                        => { :default => true, :public => true, :description => 'FIXME' },
        :sync_startup                               => { :default => false, :public => true, :description => 'FIXME' },
        :send_data_on_exit                          => { :default => true, :public => true, :description => 'FIXME' },
        :post_size_limit                            => { :default => 2 * 1024 * 1024, :public => true, :description => 'FIXME' }, # 2 megs
        :timeout                                    => { :default => 2 * 60, :public => true, :description => 'FIXME' },          # 2 minutes
        :force_send                                 => { :default => false, :public => true, :description => 'FIXME' },
        :send_environment_info                      => { :default => true, :public => true, :description => 'FIXME' },
        :start_channel_listener                     => { :default => false, :public => true, :description => 'FIXME' },
        :data_report_period                         => { :default => 60, :public => true, :description => 'FIXME' },
        :keep_retrying                              => { :default => true, :public => true, :description => 'FIXME' },
        :report_instance_busy                       => { :default => true, :public => true, :description => 'FIXME' },

        :log_file_name                              => { :default => 'newrelic_agent.log', :public => true, :description => 'FIXME'},
        :log_file_path                              => { :default => 'log/', :public => true, :description => 'FIXME'},
        :log_level                                  => { :default => 'info', :public => true, :description => 'FIXME'},

        :'audit_log.enabled'                        => { :default => false, :public => true, :description => 'FIXME' },

        :'audit_log.path'                           => { :default => Proc.new {
                                                      File.join(self[:log_file_path], 'newrelic_audit.log')
                                                    }, :public => true, :description => 'FIXME' },

        :disable_samplers                           => { :default => false, :public => true, :description => 'Disable samplers.' },
        :disable_resque                             => { :default => false, :public => true, :description => 'Disable resque.' },
        :disable_dj                                 => { :default => false, :public => true, :description => 'Disable delayed job.' },
        :disable_sinatra                            => { :default => false, :public => true, :description => 'Disable sinatra.' },
        :disable_sinatra_auto_middleware            => { :default => false, :public => true, :description => 'Disable sinatra automatic middleware.' },
        :disable_view_instrumentation               => { :default => false, :public => true, :description => 'Disable views.' },
        :disable_backtrace_cleanup                  => { :default => false, :public => true, :description => 'Disable backtrace cleanup.' },
        :disable_harvest_thread                     => { :default => false, :public => true, :description => 'This disables the samplers' },
        :skip_ar_instrumentation                    => { :default => false, :public => true, :description => 'This disables the samplers' },
        :disable_activerecord_instrumentation       => { :default => Proc.new { self[:skip_ar_instrumentation] }, :public => true, :description => 'Disable ActiveRecord.' },
        :disable_memcache_instrumentation           => { :default => false, :public => true, :description => 'Disable memcache.' },
        :disable_mobile_headers                     => { :default => true, :public => true, :description => 'Disable mobile headers' },

        :capture_params                             => { :default => false, :public => true, :description => 'Capture params.' },
        :capture_memcache_keys                      => { :default => false, :public => true, :description => 'Capture memcache keys.' },
        :textmate                                   => { :default => false, :public => true, :description => 'Enable Textmate integration.' },

        :'transaction_tracer.enabled'               => { :default => true, :public => true, :description => 'Enable transaction tracer.' },
        :'transaction_tracer.transaction_threshold' => { :default => Proc.new { self[:apdex_t] * 4 }, :public => true, :description => 'Transaction tracer transaction threshold.' },
        :'transaction_tracer.stack_trace_threshold' => { :default => 0.5, :public => true, :description => 'Transaction tracer explain threshold.' },
        :'transaction_tracer.explain_threshold'     => { :default => 0.5, :public => true, :description => 'FIXME' },
        :'transaction_tracer.explain_enabled'       => { :default => true, :public => true, :description => 'FIXME' },
        :'transaction_tracer.record_sql'            => { :default => 'obfuscated', :public => true, :description => 'FIXME' },
        :'transaction_tracer.limit_segments'        => { :default => 4000, :public => true, :description => 'FIXME' },
        :'transaction_tracer.random_sample'         => { :default => false, :public => true, :description => 'FIXME' },
        :sample_rate                                => { :default => 10, :public => true, :description => 'FIXME' },

        :'slow_sql.enabled'                         => { :default => Proc.new { self[:'transaction_tracer.enabled'] }, :public => true, :description => 'FIXME' },
        :'slow_sql.stack_trace_threshold'           => { :default => Proc.new { self[:'transaction_tracer.stack_trace_threshold'] }, :public => true, :description => 'FIXME'},
        :'slow_sql.explain_threshold'               => { :default => Proc.new { self[:'transaction_tracer.explain_threshold'] }, :public => true, :description => 'FIXME'},
        :'slow_sql.explain_enabled'                 => { :default => Proc.new { self[:'transaction_tracer.explain_enabled'] }, :public => true, :description => 'FIXME'},
        :'slow_sql.record_sql'                      => { :default => Proc.new { self[:'transaction_tracer.record_sql'] }, :public => true, :description => 'FIXME'},

        :'error_collector.enabled'                  => { :default => true, :public => true, :description => 'FIXME'},
        :'error_collector.capture_source'           => { :default => true, :public => true, :description => 'FIXME'},
        :'error_collector.ignore_errors'            => { :default => 'ActionController::RoutingError,Sinatra::NotFound', :public => true, :description => 'FIXME' },

        :'rum.enabled'                              => { :default => true, :public => true, :description => 'FIXME' },
        :'rum.jsonp'                                => { :default => true, :public => true, :description => 'FIXME' },
        :'rum.load_episodes_file'                   => { :default => true, :public => true, :description => 'FIXME' },
        :'browser_monitoring.auto_instrument'       => { :default => Proc.new { self[:'rum.enabled'] }, :public => true, :description => 'FIXME' },

        :trusted_account_ids                        => { :default => [], :public => true, :description => 'FIXME' },
        :"cross_application_tracer.enabled"         => { :default => true, :public => true, :description => 'FIXME' },

        :'thread_profiler.enabled'                  => { :default => Proc.new { NewRelic::Agent::ThreadProfiler.is_supported? }, :public => true, :description => 'FIXME' },

        :marshaller                                 => { :default => Proc.new { NewRelic::Agent::NewRelicService::JsonMarshaller.is_supported? ? 'json' : 'pruby' }, :public => true, :description => 'FIXME' },

        :'request_sampler.enabled'                  => { :default => true, :public => true, :description => 'FIXME' },
        :'request_sampler.max_samples'              => { :default => 1200, :public => true, :description => 'FIXME' },
      }.freeze
    end
  end
end
