
module NewRelic
  class Control
    module LoggingMethods

      attr_accessor :log_file

      def log
        # If we try to get a log before one has been set up, return a stdout log
        unless @log
          l = Logger.new(STDOUT)
          l.level = Logger::INFO
          return l
        end
        @log
      end

      # send the given message to STDOUT so that it shows
      # up in the console.  This should be used for important informational messages at boot.
      # The to_stdout may be implemented differently by different config subclasses.
      # This will NOT print anything if tracers are not enabled
      def log!(msg, level=:info)
        return unless should_log?
        to_stdout msg
        log.send level, msg if @log
      end

      def should_log?
        @settings && agent_enabled?
      end

      # Control subclasses may override this, but it can be called multiple times.
      def setup_log
        @log_file = "#{log_path}/#{log_file_name}"
        @log = Logger.new(@log_file) rescue nil

        # change the format just for our logger

        def log.format_message(severity, timestamp, progname, msg)
          "[#{timestamp.strftime("%m/%d/%y %H:%M:%S %z")} #{Socket.gethostname} (#{$$})] #{severity} : #{msg}\n"
        end

        # set the log level as specified in the config file

        case fetch("log_level","info").downcase
          when "debug" then log.level = Logger::DEBUG
          when "info" then log.level = Logger::INFO
          when "warn" then log.level = Logger::WARN
          when "error" then log.level = Logger::ERROR
          when "fatal" then log.level = Logger::FATAL
        else log.level = Logger::INFO
        end
        log
      end

      def to_stdout(msg)
        STDOUT.puts "** [NewRelic] " + msg
      end

      def log_path
        return if @log_path
        @log_path = File.expand_path(fetch('log_file_path', 'log/'))
        if !File.directory?(@log_path) && ! (Dir.mkdir(@log_path) rescue nil)
          log!("Error creating New Relic log directory '#{@log_path}'", :error)
        end
        @log_path
      end

      def log_file_name
        fetch('log_file_name', 'newrelic_agent.log')
      end
    end
  end
end
