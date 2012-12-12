require 'forwardable'
require 'logger'

module NewRelic
  module Agent
    class AgentLogger

      extend Forwardable
      def_delegators :@log, :fatal, :error, :info, :debug

      # TODO Figure out if we can do better because of Kernel#warn
      def warn(msg)
        @log.warn(msg)
      end

      attr_reader :log_file

      def initialize(config, root = "", options={})
        if options.has_key?(:log)
          @log = options[:log]
        elsif config[:agent_enabled] == false
          @log = NullLogger.new
        else
          @log_file = "#{log_path(config, root)}/#{config[:log_file_name]}"
          @log = ::Logger.new(@log_file)
        end
      end

      def log_path(config, root)
        log_path_setting = config[:log_file_path]

        path = find_or_create_file_path(log_path_setting, root)
        #log!("Error creating log directory #{log_path_setting}, using standard out for logging.", :warn) unless path
        #path
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

      class NullLogger
        def fatal(msg); end
        def error(msg); end
        def warn(msg); end
        def info(msg); end
        def debug(msg); end
      end
    end
  end
end
