module NewRelic
  class Control
    # used to contain methods to look up settings from the
    # configuration located in newrelic.yml
    module Configuration
      def settings
        unless @settings
          @settings = (@yaml && @yaml[env]) || {}
          # At the time we bind the settings, we also need to run this little piece
          # of magic which allows someone to augment the id with the app name, necessary
          if Agent.config['multi_homed'] && Agent.config.app_names.size > 0
            if @local_env.dispatcher_instance_id
              @local_env.dispatcher_instance_id << ":#{Agent.config.app_names.first}"
            else
              @local_env.dispatcher_instance_id = Agent.config.app_names.first
            end
          end

        end
        @settings
      end

      # Merge the given options into the config options.
      # They might be a nested hash
      def merge_options(options, hash=self)
        options.each do |key, val|
          case
          when key == :config then next
          when val.is_a?(Hash)
            merge_options(val, hash[key.to_s] ||= {})
          when val.nil?
            hash.delete(key.to_s)
          else
            hash[key.to_s] = val
          end
        end
      end

      def merge_server_side_config(data)
        remove_server_controlled_configs
        config = Hash.new
        data.each_pair do |key, value|
          if key.include?('.')
            key = key.split('.')
            config[key.first] ||= Hash.new
            config[key.first][key[1]] = value
          else
            config[key] = value
          end
        end
        merge_options(config)
      end

      def remove_server_controlled_configs
        settings.delete('transaction_tracer')
        settings.delete('slow_sql')
        settings.delete('error_collector')
        settings.delete('capture_params')
      end

      def [](key)
        fetch(key)
      end

      def []=(key, value)
        settings[key] = value
      end

      def fetch(key, default=nil)
        settings.fetch(key, default)
      end

      def apdex_t
        Agent.config[:apdex_t]
      end
      
      # Configuration option of the same name to indicate that we should flush
      # data to the server on exiting.  Defaults to true.
      def send_data_on_exit
        fetch('send_data_on_exit', true)
      end

      def validate_seed
        self['validate_seed'] || ENV['NR_VALIDATE_SEED']
      end

      def validate_token
        self['validate_token'] || ENV['NR_VALIDATE_TOKEN']
      end

      def log_file_path
        fetch('log_file_path', 'log/')
      end
      
      def disable_backtrace_cleanup?
        fetch('disable_backtrace_cleanup')
      end

      def has_slow_sql_config?
        self['slow_sql'] && self['slow_sql'].has_key?('enabled')
      end
    end
    include Configuration
  end
end
