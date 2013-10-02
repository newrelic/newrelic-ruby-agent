# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
        format_and_send(:fatal, msgs)
      end

      def error(*msgs)
        format_and_send(:error, msgs)
      end

      def warn(*msgs)
        format_and_send(:warn, msgs)
      end

      def info(*msgs)
        format_and_send(:info, msgs)
      end

      def debug(*msgs)
        format_and_send(:debug, msgs)
      end

      def is_startup_logger?
        false
      end

      # Use this when you want to log an exception with explicit control over
      # the log level that the backtrace is logged at. If you just want the
      # default behavior of backtraces logged at debug, use one of the methods
      # above and pass an Exception as one of the args.
      def log_exception(level, e, backtrace_level=level)
        @log.send(level, "%p: %s" % [ e.class, e.message ])
        @log.send(backtrace_level) do
          backtrace = e.backtrace
          if backtrace
            "Debugging backtrace:\n" + backtrace.join("\n  ")
          else
            "No backtrace available."
          end
        end
      end

      # Allows for passing exceptions in explicitly, which format with backtrace
      def format_and_send(level, *msgs)
        msgs.flatten.each do |item|
          case item
          when Exception then log_exception(level, item, :debug)
          else @log.send(level, item)
          end
        end
      end

      def create_log(config, root, override_logger)
        if !override_logger.nil?
          @log = override_logger
        elsif config[:agent_enabled] == false
          create_null_logger
        else
          if wants_stdout(config)
            @log = ::Logger.new(STDOUT)
          else
            create_log_to_file(config, root)
          end
        end
      end

      def create_log_to_file(config, root)
        path = find_or_create_file_path(config[:log_file_path], root)
        if path.nil?
          @log = ::Logger.new(STDOUT)
          warn("Error creating log directory #{config[:log_file_path]}, using standard out for logging.")
        else
          file_path = "#{path}/#{config[:log_file_name]}"
          begin
            @log = ::Logger.new(file_path)
          rescue => e
            @log = ::Logger.new(STDOUT)
            warn("Failed creating logger for file #{file_path}, using standard out for logging.", e)
          end
        end
      end

      def create_null_logger
        @log = NewRelic::Agent::NullLogger.new
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
        "debug" => ::Logger::DEBUG,
        "info"  => ::Logger::INFO,
        "warn"  => ::Logger::WARN,
        "error" => ::Logger::ERROR,
        "fatal" => ::Logger::FATAL,
      }

      def self.log_level_for(level)
        LOG_LEVELS.fetch(level.to_s.downcase, ::Logger::INFO)
      end

      def set_log_format!
        def @log.format_message(severity, timestamp, progname, msg)
          prefix = @logdev.dev == STDOUT ? '** [NewRelic]' : ''
          prefix + "[#{timestamp.strftime("%m/%d/%y %H:%M:%S %z")} #{Socket.gethostname} (#{$$})] #{severity} : #{msg}\n"
        end
      end

      def gather_startup_logs
        StartupLogger.instance.dump(self)
      end
    end

    # In an effort to not lose messages during startup, we trap them in memory
    # The real logger will then dump its contents out when it arrives.
    class StartupLogger < MemoryLogger
      include Singleton
    end
  end
end
