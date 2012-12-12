require 'forwardable'
require 'logger'

module NewRelic
  module Agent
    class AgentLogger

      extend Forwardable
      def_delegators :@log, :fatal, :error, :info, :debug

      # TODO Figure out if we can do better because of Kernel#warn interfering with Forwardable
      def warn(msg)
        @log.warn(msg)
      end

      def initialize(config, root = "", options={})
        create_log(config, root, options)
        set_log_level!(config)
        set_log_format!
      end

      def create_log(config, root, options)
        if options.has_key?(:log)
          @log = options[:log]
        elsif config[:agent_enabled] == false
          @log = NullLogger.new
        else
          path = find_or_create_file_path(config[:log_file_path], root)
          if path.nil?
            @log = ::Logger.new(STDOUT)
            @log.warn("Error creating log directory #{config[:log_path_setting]}, using standard out for logging.")
          else
            @log = ::Logger.new("#{path}/#{config[:log_file_name]}")
          end
        end
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
        @log.level = AgentLogger.log_level_for(config.fetch(:log_level, ""))
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

      class NullLogger
        def level=(level); end

        def fatal(msg); end
        def error(msg); end
        def warn(msg); end
        def info(msg); end
        def debug(msg); end
      end
    end
  end
end
