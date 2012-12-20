require 'logger'

module NewRelic
  module Agent
    class AuditLogger
      def initialize(config)
        @config = config
        @enabled = config[:'audit_log.enabled']
        @encoder = NewRelic::Agent::NewRelicService::Encoders::Identity
      end

      def enabled?
        @enabled
      end

      def log_request(uri, data, marshaller)
        if enabled?
          setup_logger unless @log
          prepared_data = marshaller.prepare(data, :encoder => @encoder)
          @log.add(::Logger::INFO, "REQUEST: #{uri}")
          @log.add(::Logger::INFO, "REQUEST BODY: #{prepared_data.inspect}")
        end
      end

      def setup_logger
        path = ensure_log_path
        @log = ::Logger.new(path || "/dev/null")
        @log.formatter = log_formatter
        ::NewRelic::Agent.logger.info("Audit log enabled at '#{path}'") if path
      end

      def ensure_log_path
        path = File.expand_path(@config[:'audit_log.path'])
        log_dir = File.dirname(path)
        error = if !File.directory?(log_dir)
          "Audit log disabled: '#{log_dir}' does not exist or is not a directory"
        elsif !File.writable?(path)
          "Audit log disabled: '#{path}' is not writable"
        end

        if error
          ::NewRelic::Agent.logger.warn(error)
          path = nil
        end

        path
      end

      def log_formatter
        if @formatter.nil?
          @formatter = Logger::Formatter.new
          def @formatter.call(severity, time, progname, msg)
            "[#{time} #{Socket.gethostname} (#{$$})] : #{msg}\n"
          end
        end
        @formatter
      end
    end
  end
end
