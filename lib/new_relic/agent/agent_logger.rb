require 'logger'

module NewRelic
  module Agent
    class AgentLogger

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

      def format_messages(*msgs)
        msgs.join("\n")
      end

      def initialize(config, root = "", override_logger=nil)
        create_log(config, root, override_logger)
        set_log_level!(config)
        set_log_format!
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
    end
  end
end
