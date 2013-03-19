# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
      rescue SystemCallError => e
        ::NewRelic::Agent.logger.warn("Failed writing to audit log: #{e}")
      end

      def setup_logger
        path = ensure_log_path
        if path
          @log = ::Logger.new(path)
          @log.formatter = log_formatter
          ::NewRelic::Agent.logger.info("Audit log enabled at '#{path}'")
        else
          @log = NewRelic::Agent::NullLogger.new
        end
      end

      def ensure_log_path
        path = File.expand_path(@config[:'audit_log.path'])
        log_dir = File.dirname(path)

        begin
          FileUtils.mkdir_p(log_dir)
          FileUtils.touch(path)
        rescue SystemCallError => e
          msg = "Audit log disabled, failed opening log at '#{path}': #{e}"
          ::NewRelic::Agent.logger.warn(msg)
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
