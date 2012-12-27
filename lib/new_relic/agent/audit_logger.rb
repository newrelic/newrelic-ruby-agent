require 'logger'
require 'fileutils'

module NewRelic
  module Agent
    class AuditLogger
      def initialize(config)
        @config = config
        @enabled = @config[:'audit_log.enabled']
        @encoder = NewRelic::Agent::NewRelicService::Encoders::Identity
      end

      attr_writer :enabled

      def enabled?
        @enabled
      end

      def setup?
        !@log.nil?
      end

      def log_request(uri, data, marshaller)
        if enabled?
          setup_logger unless setup?
          request_body = if marshaller.class.human_readable?
            marshaller.dump(data, :encoder => @encoder)
          else
            marshaller.prepare(data, :encoder => @encoder).inspect
          end
          @log.info("REQUEST: #{uri}")
          @log.info("REQUEST BODY: #{request_body}")
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

        error = nil
        if !File.directory?(log_dir)
          begin
            FileUtils.mkdir_p(log_dir)
          rescue SystemCallError => e
            error = "Audit log disabled, failed to create log directory '#{log_dir}': #{e}"
          end
        elsif !File.writable?(log_dir)
          error = "Audit log disabled: '#{log_dir}' is not writable"
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
