require 'logger'

module NewRelic
  module Agent
    class AgentLogger

      def initialize(config, root = "", override_logger=nil)
        create_log(config, root, override_logger)
        set_log_level!(config)
        set_log_format!

        gather_startup_logs
      end

      def fatal(*msgs)
        @log.fatal(format_messages(msgs))
      end

      def error(*msgs)
        @log.error(format_messages(msgs))
      end

      def warn(*msgs)
        @log.warn(format_messages(msgs))
      end

      def info(*msgs)
        @log.info(format_messages(msgs))
      end

      def debug(*msgs)
        @log.debug(format_messages(msgs))
      end

      # Allows for passing exceptions in explicitly, which format with backtrace
      def format_messages(msgs)
        msgs.map do |msg|
          if msg.respond_to?(:backtrace)
            "#{msg.class}: #{msg}\n\t#{(msg.backtrace || []).join("\n\t")}"
          else
            msg
          end
        end.join("\n")
      end

      def create_log(config, root, override_logger)
        if !override_logger.nil?
          @log = override_logger
        elsif config[:agent_enabled] == false
          @log = ::Logger.new("/dev/null")
        else
          if wants_stdout(config)
            @log = ::Logger.new(STDOUT)
          else
            path = find_or_create_file_path(config[:log_file_path], root)
            if path.nil?
              @log = ::Logger.new(STDOUT)
              @log.warn("Error creating log directory #{config[:log_file_path]}, using standard out for logging.")
            else
              @log = ::Logger.new("#{path}/#{config[:log_file_name]}")
            end
          end
        end
      end

      def wants_stdout(config)
        config[:log_file_path].upcase == "STDOUT"
      end

      def find_or_create_file_path(path_setting, root)
        for abs_path in [ File.expand_path(path_setting),
                          File.expand_path(File.join(root, path_setting)) ] do
          if File.directory?(abs_path) || (Dir.mkdir(abs_path) rescue nil)
            return abs_path[%r{^(.*?)/?$}]
          end
        end
        nil
      end

      def set_log_level!(config)
        @log.level = AgentLogger.log_level_for(config.fetch(:log_level))
      end

      LOG_LEVELS = {
        "debug" => Logger::DEBUG,
        "info"  => Logger::INFO,
        "warn"  => Logger::WARN,
        "error" => Logger::ERROR,
        "fatal" => Logger::FATAL,
      }

      def self.log_level_for(level)
        LOG_LEVELS.fetch(level.to_s.downcase, Logger::INFO)
      end

      def set_log_format!
        def @log.format_message(severity, timestamp, progname, msg)
          "[#{timestamp.strftime("%m/%d/%y %H:%M:%S %z")} #{Socket.gethostname} (#{$$})] #{severity} : #{msg}\n"
        end
      end

      def gather_startup_logs
        StartupLogger.instance.dump(self)
      end
    end

    # BBase class for startup logging and testing in multiverse
    class MemoryLogger
      def initialize
        @messages = []
      end

      attr_accessor :messages, :level

      def fatal(*msgs)
        messages << [:fatal, msgs]
      end

      def error(*msgs)
        messages << [:error, msgs]
      end

      def warn(*msgs)
        messages << [:warn, msgs]
      end

      def info(*msgs)
        messages << [:info, msgs]
      end

      def debug(*msgs)
        messages << [:debug, msgs]
      end

      def dump(logger)
        messages.each do |msg|
          logger.send(msg[0], msg[1])
        end
        messages.clear
      end
    end

    # In an effort to not lose messages during startup, we trap them in memory
    # The real logger will then dump its contents out when it arrives.
    class StartupLogger < MemoryLogger
      include Singleton
    end
  end
end
