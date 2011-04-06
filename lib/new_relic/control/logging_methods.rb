
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

      # set the log level as specified in the config file
      def set_log_level!(logger)
        case fetch("log_level","info").downcase
          when "debug" then logger.level = Logger::DEBUG
          when "info" then logger.level = Logger::INFO
          when "warn" then logger.level = Logger::WARN
          when "error" then logger.level = Logger::ERROR
          when "fatal" then logger.level = Logger::FATAL
          else logger.level = Logger::INFO
        end
        logger
      end

      # change the format just for our logger
      def set_log_format!(logger)
        def logger.format_message(severity, timestamp, progname, msg)
          "[#{timestamp.strftime("%m/%d/%y %H:%M:%S %z")} #{Socket.gethostname} (#{$$})] #{severity} : #{msg}\n"
        end
        logger
      end

      # Create the logger using the configuration variables
      #
      # Control subclasses may override this, but it can be called multiple times.
      def setup_log
        @log_file = "#{log_path}/#{log_file_name}"
        @log = Logger.new(@log_file) rescue nil
        if @log
          set_log_format!(@log)
          set_log_level!(@log)
        end
        # note this is not the variable from above - it is the `log`
        # method, which returns a default logger if none is setup
        # above
        log
      end

      def to_stdout(msg)
        STDOUT.puts "** [NewRelic] " + msg
      end

      def log_path
        return @log_path if @log_path
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
    include LoggingMethods
  end
end
