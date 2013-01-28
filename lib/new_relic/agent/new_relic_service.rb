require 'zlib'
require 'new_relic/agent/audit_logger'

module NewRelic
  module Agent
    class NewRelicService
      # Specifies the version of the agent's communication protocol with
      # the NewRelic hosted site.

      PROTOCOL_VERSION = 10
      # cf0d1ff1: v9 (tag 3.5.0)
      # 14105: v8 (tag 2.10.3)
      # (no v7)
      # 10379: v6 (not tagged)
      # 4078:  v5 (tag 2.5.4)
      # 2292:  v4 (tag 2.3.6)
      # 1754:  v3 (tag 2.3.0)
      # 534:   v2 (shows up in 2.1.0, our first tag)

      attr_accessor :request_timeout, :agent_id
      attr_reader :collector, :marshaller

      def initialize(license_key=nil, collector=control.server)
        @license_key = license_key || Agent.config[:license_key]
        @collector = collector
        @request_timeout = Agent.config[:timeout]

        @audit_logger = ::NewRelic::Agent::AuditLogger.new(Agent.config)
        Agent.config.register_callback(:'audit_log.enabled') do |enabled|
          @audit_logger.enabled = enabled
        end
        
        Agent.config.register_callback(:marshaller) do |marshaller|
          begin
            if marshaller == 'json'
              require 'json'
              @marshaller = JsonMarshaller.new
            else
              @marshaller = PrubyMarshaller.new
            end
          rescue LoadError
            @marshaller = PrubyMarshaller.new
          end
        end
      end

      def connect(settings={})
        if host = get_redirect_host
          @collector = NewRelic::Control.instance.server_from_host(host)
        end
        response = invoke_remote(:connect, settings)
        @agent_id = response['agent_run_id']
        response
      end

      def get_redirect_host
        invoke_remote(:get_redirect_host)
      end

      def shutdown(time)
        invoke_remote(:shutdown, @agent_id, time.to_i) if @agent_id
      end

      def metric_data(last_harvest_time, now, unsent_timeslice_data)
        invoke_remote(:metric_data, @agent_id, last_harvest_time, now,
                      unsent_timeslice_data)
      end

      def error_data(unsent_errors)
        invoke_remote(:error_data, @agent_id, unsent_errors)
      end

      def transaction_sample_data(traces)
        invoke_remote(:transaction_sample_data, @agent_id, traces)
      end

      def sql_trace_data(sql_traces)
        invoke_remote(:sql_trace_data, sql_traces)
      end

      def profile_data(profile)
        invoke_remote(:profile_data, @agent_id, profile) || ''
      end

      def get_agent_commands
        invoke_remote(:get_agent_commands, @agent_id)
      end

      def agent_command_results(command_id, error=nil)
        results = {}
        results["error"] = error unless error.nil?

        invoke_remote(:agent_command_results, @agent_id, { command_id.to_s => results })
      end

      # We do not compress if content is smaller than 64kb.  There are
      # problems with bugs in Ruby in some versions that expose us
      # to a risk of segfaults if we compress aggressively.
      def compress_request_if_needed(data)
        encoding = 'identity'
        if data.size > 64 * 1024
          data = Encoders::Compressed.encode(data)
          encoding = 'deflate'
        end
        check_post_size(data)
        [data, encoding]
      end

      private

      # A shorthand for NewRelic::Control.instance
      def control
        NewRelic::Control.instance
      end

      # The path on the server that we should post our data to
      def remote_method_uri(method, format='ruby')
        params = {'run_id' => @agent_id, 'marshal_format' => format}
        uri = "/agent_listener/#{PROTOCOL_VERSION}/#{@license_key}/#{method}"
        uri << '?' + params.map do |k,v|
          next unless v
          "#{k}=#{v}"
        end.compact.join('&')
        uri
      end

      # send a message via post to the actual server. This attempts
      # to automatically compress the data via zlib if it is large
      # enough to be worth compressing, and handles any errors the
      # server may return
      def invoke_remote(method, *args)
        now = Time.now

        data = @marshaller.dump(args)
        data, encoding = compress_request_if_needed(data)

        uri = remote_method_uri(method, @marshaller.format)
        full_uri = "#{@collector}#{uri}"

        @audit_logger.log_request(full_uri, args, @marshaller)
        response = send_request(:data      => data,
                                :uri       => uri,
                                :encoding  => encoding,
                                :collector => @collector)
        @marshaller.load(decompress_response(response))
      rescue NewRelic::Agent::ForceRestartException => e
        ::NewRelic::Agent.logger.debug e.message
        raise
      ensure
        record_supportability_metrics(method, now)
      end

      def record_supportability_metrics(method, now)
        NewRelic::Agent.instance.stats_engine. \
          get_stats_no_scope('Supportability/invoke_remote'). \
          record_data_point((Time.now - now).to_f)
        NewRelic::Agent.instance.stats_engine. \
          get_stats_no_scope('Supportability/invoke_remote/' + method.to_s). \
          record_data_point((Time.now - now).to_f)
      end

      # Raises an UnrecoverableServerException if the post_string is longer
      # than the limit configured in the control object
      def check_post_size(post_string)
        return if post_string.size < Agent.config[:post_size_limit]
        ::NewRelic::Agent.logger.debug "Tried to send too much data: #{post_string.size} bytes"
        raise UnrecoverableServerException.new('413 Request Entity Too Large')
      end

      # Posts to the specified server
      #
      # Options:
      #  - :uri => the path to request on the server (a misnomer of
      #              course)
      #  - :encoding => the encoding to pass to the server
      #  - :collector => a URI object that responds to the 'name' method
      #                    and returns the name of the collector to
      #                    contact
      #  - :data => the data to send as the body of the request
      def send_request(opts)
        request = Net::HTTP::Post.new(opts[:uri], 'CONTENT-ENCODING' => opts[:encoding], 'HOST' => opts[:collector].name)
        request['user-agent'] = user_agent
        request.content_type = "application/octet-stream"
        request.body = opts[:data]

        ::NewRelic::Agent.logger.debug "Connect to #{opts[:collector]}#{opts[:uri]}"

        response = nil
        http = control.http_connection(@collector)
        http.read_timeout = nil
        begin
          NewRelic::TimerLib.timeout(@request_timeout) do
            response = http.request(request)
          end
        rescue Timeout::Error
          ::NewRelic::Agent.logger.warn "Timed out trying to post data to New Relic (timeout = #{@request_timeout} seconds)" unless @request_timeout < 30
          raise
        end
        if response.is_a? Net::HTTPUnauthorized
          raise LicenseException, 'Invalid license key, please contact support@newrelic.com'
        elsif response.is_a? Net::HTTPServiceUnavailable
          raise ServerConnectionException, "Service unavailable (#{response.code}): #{response.message}"
        elsif response.is_a? Net::HTTPGatewayTimeOut
          ::NewRelic::Agent.logger.warn("Timed out getting response: #{response.message}")
          raise Timeout::Error, response.message
        elsif response.is_a? Net::HTTPRequestEntityTooLarge
          raise UnrecoverableServerException, '413 Request Entity Too Large'
        elsif response.is_a? Net::HTTPUnsupportedMediaType
          raise UnrecoverableServerException, '415 Unsupported Media Type'
        elsif !(response.is_a? Net::HTTPSuccess)
          raise ServerConnectionException, "Unexpected response from server (#{response.code}): #{response.message}"
        end
        response
      rescue SystemCallError, SocketError => e
        # These include Errno connection errors
        raise NewRelic::Agent::ServerConnectionException, "Recoverable error connecting to the server: #{e}"
      end

      # Decompresses the response from the server, if it is gzip
      # encoded, otherwise returns it verbatim
      def decompress_response(response)
        if response['content-encoding'] != 'gzip'
          ::NewRelic::Agent.logger.debug "Uncompressed content returned"
          return response.body
        end
        ::NewRelic::Agent.logger.debug "Decompressing return value"
        i = Zlib::GzipReader.new(StringIO.new(response.body))
        i.read
      end

      # Sets the user agent for connections to the server, to
      # conform with the HTTP spec and allow for debugging. Includes
      # the ruby version and also zlib version if available since
      # that may cause corrupt compression if there is a problem.
      def user_agent
        ruby_description = ''
        # note the trailing space!
        ruby_description << "(ruby #{::RUBY_VERSION} #{::RUBY_PLATFORM}) " if defined?(::RUBY_VERSION) && defined?(::RUBY_PLATFORM)
        zlib_version = ''
        zlib_version << "zlib/#{Zlib.zlib_version}" if defined?(::Zlib) && Zlib.respond_to?(:zlib_version)
        "NewRelic-RubyAgent/#{NewRelic::VERSION::STRING} #{ruby_description}#{zlib_version}"
      end

      module Encoders
        module Identity
          def self.encode(data)
            data
          end
        end

        module Compressed
          def self.encode(data)
            Zlib::Deflate.deflate(data, Zlib::DEFAULT_COMPRESSION)
          end
        end

        module Base64CompressedJSON
          def self.encode(data)
            Base64.encode64(Compressed.encode(JSON.dump(data)))
          end
        end
      end

      class Marshaller
        def parsed_error(error)
          error_class = error['error_type'].split('::') \
            .inject(Module) {|mod,const| mod.const_get(const) }
          error_class.new(error['message'])
        rescue NameError
          CollectorError.new("#{error['error_type']}: #{error['message']}")
        end

        def prepare(data, options={})
          encoder = options[:encoder] || default_encoder
          if data.respond_to?(:to_collector_array)
            data.to_collector_array(encoder)
          elsif data.kind_of?(Array)
            data.map { |element| prepare(element, options) }
          else
            data
          end
        end

        def default_encoder
          Encoders::Identity
        end

        def self.human_readable?
          false
        end

        protected

        def return_value(data)
          if data.respond_to?(:has_key?)
            if data.has_key?('exception')
              raise parsed_error(data['exception'])
            elsif data.has_key?('return_value')
              return data['return_value']
            end
          end
          ::NewRelic::Agent.logger.debug("Unexpected response from collector: #{data}")
          nil
        end
      end

      # Primitive Ruby Object Notation which complies JSON format data strutures
      class PrubyMarshaller < Marshaller
        def initialize
          ::NewRelic::Agent.logger.debug 'Using Pruby marshaller'
        end

        def dump(ruby, opts={})
          NewRelic::LanguageSupport.with_cautious_gc do
            Marshal.dump(prepare(ruby, opts))
          end
        rescue => e
          ::NewRelic::Agent.logger.debug("#{e.class.name} : #{e.message} when marshalling #{ruby.inspect}")
          raise
        end

        def load(data)
          return unless data && data != ''
          NewRelic::LanguageSupport.with_cautious_gc do
            return_value(Marshal.load(data))
          end
        rescue
          ::NewRelic::Agent.logger.debug "Error encountered loading collector response: #{data}"
          raise
        end

        def format
          'pruby'
        end

        def self.is_supported?
          true
        end
      end

      # Marshal collector protocol with JSON when available
      class JsonMarshaller < Marshaller
        def initialize
          ::NewRelic::Agent.logger.debug 'Using JSON marshaller'
        end

        def dump(ruby, opts={})
          JSON.dump(prepare(ruby, opts))
        end

        def load(data)
          return unless data && data != ''
          return_value(JSON.load(data))
        rescue
          ::NewRelic::Agent.logger.debug "Error encountered loading collector response: #{data}"
          raise
        end

        def default_encoder
          Encoders::Base64CompressedJSON
        end

        def format
          'json'
        end

        def self.is_supported?
          RUBY_VERSION >= '1.9.2'
        end

        def self.human_readable?
          true # for some definitions of 'human'
        end
      end

      class CollectorError < StandardError; end
    end
  end
end
