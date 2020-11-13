# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require 'zlib'
require 'timeout'
require 'new_relic/agent/audit_logger'
require 'new_relic/agent/new_relic_service/encoders'
require 'new_relic/agent/new_relic_service/marshaller'
require 'new_relic/agent/new_relic_service/json_marshaller'
require 'new_relic/agent/new_relic_service/security_policy_settings'

module NewRelic
  module Agent
    class NewRelicService
      # Specifies the version of the agent's communication protocol with
      # the NewRelic hosted site.

      PROTOCOL_VERSION = 17

      # 1f147a42: v10 (tag 3.5.3.17)
      # cf0d1ff1: v9 (tag 3.5.0)
      # 14105: v8 (tag 2.10.3)
      # (no v7)
      # 10379: v6 (not tagged)
      # 4078:  v5 (tag 2.5.4)
      # 2292:  v4 (tag 2.3.6)
      # 1754:  v3 (tag 2.3.0)
      # 534:   v2 (shows up in 2.1.0, our first tag)

      # These include Errno connection errors, and all indicate that the
      # underlying TCP connection may be in a bad state.
      CONNECTION_ERRORS = [Timeout::Error, EOFError, SystemCallError, SocketError].freeze

      attr_accessor :request_timeout
      attr_reader :collector, :marshaller, :agent_id

      def initialize(license_key=nil, collector=control.server)
        @license_key = license_key
        @collector = collector
        @configured_collector = collector
        @request_timeout = Agent.config[:timeout]
        @ssl_cert_store = nil
        @use_bundled_certs = false
        @in_session = nil
        @agent_id = nil
        @shared_tcp_connection = nil
        @request_headers_map = nil
        reset_remote_method_uris

        @audit_logger = ::NewRelic::Agent::AuditLogger.new
        Agent.config.register_callback(:'audit_log.enabled') do |enabled|
          @audit_logger.enabled = enabled
        end

        Agent.config.register_callback(:marshaller) do |marshaller|
          if marshaller != 'json'
            ::NewRelic::Agent.logger.warn("Non-JSON marshaller '#{marshaller}' requested but not supported, using JSON marshaller instead. pruby marshalling has been removed as of version 3.14.0.")
          end

          @marshaller = JsonMarshaller.new
        end
      end

      def agent_id=(id)
        # Remote URIs have the agent run ID in them, so we need to
        # clear out our cached values whenever the run ID changes.
        #
        reset_remote_method_uris
        @agent_id = id
      end

      def connect(settings={})
        @request_headers_map = nil
        security_policies = nil
        if response = preconnect
          if host = response['redirect_host']
            @collector = NewRelic::Control.instance.server_from_host(host)
          end
          if policies = response['security_policies']
            security_policies = SecurityPolicySettings.preliminary_settings(policies)
            settings.merge!(security_policies)
          end
        end
        response = invoke_remote(:connect, [settings])
        @request_headers_map = response['request_headers_map']
        self.agent_id = response['agent_run_id']
        response.merge!(security_policies) if security_policies
        response
      end

      def preconnect
        token = Agent.config[:security_policies_token]

        if token && !token.empty?
          response = invoke_remote(:preconnect, [{'security_policies_token' => token, 'high_security' => false}])

          validator = SecurityPolicySettings::Validator.new(response)
          validator.validate_matching_agent_config!

          response
        elsif Agent.config[:high_security]
          invoke_remote(:preconnect, [{'high_security' => true}])
        else
          invoke_remote(:preconnect, [{'high_security' => false}])
        end
      end

      def shutdown(time)
        invoke_remote(:shutdown, [@agent_id, time.to_i]) if @agent_id
      end

      def force_restart
        close_shared_connection
      end

      # The collector wants to receive metric data in a format that's different
      # from how we store it internally, so this method handles the translation.
      def build_metric_data_array(stats_hash)
        metric_data_array = []
        stats_hash.each do |metric_spec, stats|
          # Omit empty stats as an optimization
          unless stats.is_reset?
            metric_data_array << NewRelic::MetricData.new(metric_spec, stats)
          end
        end
        metric_data_array
      end

      def metric_data(stats_hash)
        timeslice_start = stats_hash.started_at
        timeslice_end  = stats_hash.harvested_at || Time.now
        metric_data_array = build_metric_data_array(stats_hash)
        result = invoke_remote(
          :metric_data,
          [@agent_id, timeslice_start.to_f, timeslice_end.to_f, metric_data_array],
          :item_count => metric_data_array.size
        )
        result
      end

      def error_data(unsent_errors)
        invoke_remote(:error_data, [@agent_id, unsent_errors],
          :item_count => unsent_errors.size)
      end

      def transaction_sample_data(traces)
        invoke_remote(:transaction_sample_data, [@agent_id, traces],
          :item_count => traces.size)
      end

      def sql_trace_data(sql_traces)
        invoke_remote(:sql_trace_data, [sql_traces],
          :item_count => sql_traces.size)
      end

      def profile_data(profile)
        invoke_remote(:profile_data, [@agent_id, profile], :skip_normalization => true) || ''
      end

      def get_agent_commands
        invoke_remote(:get_agent_commands, [@agent_id])
      end

      def agent_command_results(results)
        invoke_remote(:agent_command_results, [@agent_id, results])
      end

      def analytic_event_data(data)
        _, items = data
        invoke_remote(:analytic_event_data, [@agent_id, *data],
          :item_count => items.size)
      end

      def custom_event_data(data)
        _, items = data
        invoke_remote(:custom_event_data, [@agent_id, *data],
          :item_count => items.size)
      end

      def error_event_data(data)
        metadata, items = data
        invoke_remote(:error_event_data, [@agent_id, *data], :item_count => items.size)
        NewRelic::Agent.record_metric("Supportability/Events/TransactionError/Sent", :count => items.size)
        NewRelic::Agent.record_metric("Supportability/Events/TransactionError/Seen", :count => metadata[:events_seen])
      end

      def span_event_data(data)
        metadata, items = data
        invoke_remote(:span_event_data, [@agent_id, *data], :item_count => items.size)
        NewRelic::Agent.record_metric("Supportability/Events/SpanEvents/Sent", :count => items.size)
        NewRelic::Agent.record_metric("Supportability/Events/SpanEvents/Seen", :count => metadata[:events_seen])
      end

      # We do not compress if content is smaller than 64kb.  There are
      # problems with bugs in Ruby in some versions that expose us
      # to a risk of segfaults if we compress aggressively.
      def compress_request_if_needed(data, endpoint)
        encoding = 'identity'
        if data.size > 64 * 1024
          encoding = Agent.config[:compressed_content_encoding]
          data = if encoding == 'deflate'
            Encoders::Compressed::Deflate.encode(data)
          else
            Encoders::Compressed::Gzip.encode(data)
          end
        end
        check_post_size(data, endpoint)
        [data, encoding]
      end

      # One session with the service's endpoint.  In this case the session
      # represents 1 tcp connection which may transmit multiple HTTP requests
      # via keep-alive.
      def session(&block)
        raise ArgumentError, "#{self.class}#shared_connection must be passed a block" unless block_given?

        begin
          t0 = Time.now
          @in_session = true
          if NewRelic::Agent.config[:aggressive_keepalive]
            session_with_keepalive(&block)
          else
            session_without_keepalive(&block)
          end
        rescue *CONNECTION_ERRORS => e
          elapsed = Time.now - t0
          raise NewRelic::Agent::ServerConnectionException, "Recoverable error connecting to #{@collector} after #{elapsed} seconds: #{e}"
        ensure
          @in_session = false
        end
      end

      def session_with_keepalive(&block)
        establish_shared_connection
        block.call
      end

      def session_without_keepalive(&block)
        begin
          establish_shared_connection
          block.call
        ensure
          close_shared_connection
        end
      end

      def establish_shared_connection
        unless @shared_tcp_connection
          @shared_tcp_connection = create_and_start_http_connection
        end
        @shared_tcp_connection
      end

      def close_shared_connection
        if @shared_tcp_connection
          ::NewRelic::Agent.logger.debug("Closing shared TCP connection to #{@shared_tcp_connection.address}:#{@shared_tcp_connection.port}")
          @shared_tcp_connection.finish if @shared_tcp_connection.started?
          @shared_tcp_connection = nil
        end
      end

      def has_shared_connection?
        !@shared_tcp_connection.nil?
      end

      def ssl_cert_store
        path = cert_file_path
        if !@ssl_cert_store || path != @cached_cert_store_path
          ::NewRelic::Agent.logger.debug("Creating SSL certificate store from file at #{path}")
          @ssl_cert_store = OpenSSL::X509::Store.new
          @ssl_cert_store.add_file(path)
          @cached_cert_store_path = path
        end
        @ssl_cert_store
      end

      # Return a Net::HTTP connection object to make a call to the collector.
      # We'll reuse the same handle for cases where we're using keep-alive, or
      # otherwise create a new one.
      def http_connection
        if @in_session
          establish_shared_connection
        else
          create_http_connection
        end
      end

      def setup_connection_for_ssl(conn)
        # Jruby 1.6.8 requires a gem for full ssl support and will throw
        # an error when use_ssl=(true) is called and jruby-openssl isn't
        # installed
        conn.use_ssl     = true
        conn.verify_mode = OpenSSL::SSL::VERIFY_PEER
        set_cert_store(conn)
      rescue StandardError, LoadError
        msg = "SSL is not available in the environment; please install SSL support."
        raise UnrecoverableAgentException.new(msg)
      end

      def set_cert_store(conn)
        if @use_bundled_certs || NewRelic::Agent.config[:ca_bundle_path]
          conn.cert_store  = ssl_cert_store
        else
          ::NewRelic::Agent.logger.debug("Using default security certificates")
        end
      end

      def start_connection(conn)
        NewRelic::Agent.logger.debug("Opening TCP connection to #{conn.address}:#{conn.port}")
        Timeout.timeout(@request_timeout) { conn.start }
        conn
      end

      def setup_connection_timeouts(conn)
        # We use Timeout explicitly instead of this
        conn.read_timeout = nil

        if conn.respond_to?(:keep_alive_timeout) && NewRelic::Agent.config[:aggressive_keepalive]
          conn.keep_alive_timeout = NewRelic::Agent.config[:keep_alive_timeout]
        end
      end

      def create_http_connection
        if Agent.config[:proxy_host]
          ::NewRelic::Agent.logger.debug("Using proxy server #{Agent.config[:proxy_host]}:#{Agent.config[:proxy_port]}")

          proxy = Net::HTTP::Proxy(
            Agent.config[:proxy_host],
            Agent.config[:proxy_port],
            Agent.config[:proxy_user],
            Agent.config[:proxy_pass]
          )
          conn = proxy.new(@collector.name, @collector.port)
        else
          conn = Net::HTTP.new(@collector.name, @collector.port)
        end

        setup_connection_for_ssl(conn)
        setup_connection_timeouts(conn)

        ::NewRelic::Agent.logger.debug("Created net/http handle to #{conn.address}:#{conn.port}")
        conn
      end

      def create_and_start_http_connection
        conn = create_http_connection
        start_connection(conn)
        conn
      rescue Timeout::Error
        if @use_bundled_certs == false
          ::NewRelic::Agent.logger.info("Unable to connect. Falling back to bundled security certificates")
          @use_bundled_certs = true
          retry
        else
          raise
        end
      end

      # The path to the certificate file used to verify the SSL
      # connection if verify_peer is enabled
      def cert_file_path
        if path_override = NewRelic::Agent.config[:ca_bundle_path]
          NewRelic::Agent.logger.warn("Couldn't find CA bundle from configured ca_bundle_path: #{path_override}") unless File.exist? path_override
          path_override
        else
          ::NewRelic::Agent.increment_metric("Supportability/Ruby/Certificate/BundleRequired")
          File.expand_path(File.join(control.newrelic_root, 'cert', 'cacert.pem'))
        end
      end

      def valid_to_marshal?(data)
        @marshaller.dump(data)
        true
      rescue StandardError, SystemStackError => e
        NewRelic::Agent.logger.warn("Unable to marshal environment report on connect.", e)
        false
      end

      private

      # A shorthand for NewRelic::Control.instance
      def control
        NewRelic::Control.instance
      end

      def remote_method_uri(method)
        @remote_method_uris[method]
      end

      def reset_remote_method_uris
        @remote_method_uris = Hash.new do |hash, remote_method|
          hash[remote_method] = generate_remote_method_uri(remote_method)
        end
      end

      def generate_remote_method_uri(method)
        params = {
          'protocol_version' => PROTOCOL_VERSION,
          'license_key'      => license_key,
          'run_id'           => @agent_id,
          'method'           => method,
          'marshal_format'   => 'json', # Other formats are explicitly
                                        # ruled out; see the initializer
        }

        uri = "/agent_listener/invoke_raw_method?"
        uri << params.map do |k,v|
          next unless v
          "#{k}=#{v}"
        end.compact.join('&')
        uri
      end

      def license_key
        @license_key ||= Agent.config[:license_key]
      end

      # send a message via post to the actual server. This attempts
      # to automatically compress the data via zlib if it is large
      # enough to be worth compressing, and handles any errors the
      # server may return
      def invoke_remote(method, payload = [], options = {})
        start_ts = Time.now

        data, size, serialize_finish_ts, request_send_ts, response_check_ts = nil
        begin
          data = @marshaller.dump(payload, options)
        rescue StandardError, SystemStackError => e
          handle_serialization_error(method, e)
        end
        serialize_finish_ts = Time.now

        data, encoding = compress_request_if_needed(data, method)
        size = data.size

        # Preconnect needs to always use the configured collector host, not the redirect host
        endpoint_specific_collector = (method == :preconnect) ? @configured_collector : @collector

        uri = remote_method_uri(method)
        full_uri = "#{endpoint_specific_collector}#{uri}"

        @audit_logger.log_request(full_uri, payload, @marshaller)
        request_send_ts = Time.now
        response = send_request(:data      => data,
                                :uri       => uri,
                                :encoding  => encoding,
                                :collector => endpoint_specific_collector,
                                :endpoint  => method)
        response_check_ts = Time.now
        @marshaller.load(decompress_response(response))
      ensure
        record_timing_supportability_metrics(method, start_ts, serialize_finish_ts, request_send_ts, response_check_ts)
        if size
          record_size_supportability_metrics(method, size, options[:item_count])
        end
      end

      def handle_serialization_error(method, e)
        NewRelic::Agent.increment_metric("Supportability/serialization_failure")
        NewRelic::Agent.increment_metric("Supportability/serialization_failure/#{method}")
        msg = "Failed to serialize #{method} data using #{@marshaller.class.to_s}: #{e.inspect}"
        error = SerializationError.new(msg)
        error.set_backtrace(e.backtrace)
        raise error
      end

      def record_timing_supportability_metrics(method, start_ts, serialize_finish_ts, request_send_ts, response_check_ts)
        serialize_time = serialize_finish_ts && (serialize_finish_ts - start_ts)
        request_duration = response_check_ts && (response_check_ts - request_send_ts).to_f
        if request_duration
          NewRelic::Agent.record_metric("Supportability/Agent/Collector/#{method.to_s}/Duration", request_duration)
        end
        if serialize_time
          NewRelic::Agent.record_metric("Supportability/invoke_remote_serialize", serialize_time)
          NewRelic::Agent.record_metric("Supportability/invoke_remote_serialize/#{method.to_s}", serialize_time)
        end
      end

      # For these metrics, we use the following fields:
      # call_count           => number of times this remote method was invoked
      # total_call_time      => total size in bytes of payloads across all invocations
      # total_exclusive_time => total size in items (e.g. unique metrics, traces, events, etc) across all invocations
      #
      # The last field doesn't make sense for all methods (e.g. get_agent_commands),
      # so we omit it for those methods that don't really take collections
      # of items as arguments.
      def record_size_supportability_metrics(method, size_bytes, item_count)
        metrics = [
          "Supportability/invoke_remote_size",
          "Supportability/invoke_remote_size/#{method.to_s}"
        ]
        # we may not have an item count, in which case, just record 0 for the exclusive time
        item_count ||= 0
        NewRelic::Agent.agent.stats_engine.tl_record_unscoped_metrics(metrics, size_bytes, item_count)
      end

      # Raises an UnrecoverableServerException if the post_string is longer
      # than the limit configured in the control object
      def check_post_size(post_string, endpoint)
        return if post_string.size < Agent.config[:max_payload_size_in_bytes]
        ::NewRelic::Agent.logger.debug "Tried to send too much data: #{post_string.size} bytes"
        NewRelic::Agent.increment_metric("Supportability/Agent/Collector/#{endpoint}/MaxPayloadSizeLimit")
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
        headers = {
          'Content-Encoding' => opts[:encoding],
          'Host'             => opts[:collector].name
        }
        headers.merge!(@request_headers_map) if @request_headers_map

        if Agent.config[:put_for_data_send]
          request = Net::HTTP::Put.new(opts[:uri], headers)
        else
          request = Net::HTTP::Post.new(opts[:uri], headers)
        end
        @audit_logger.log_request_headers(opts[:uri], headers)
        request['user-agent'] = user_agent
        request.content_type = "application/octet-stream"
        request.body = opts[:data]

        response     = nil
        attempts     = 0
        max_attempts = 2
        endpoint     = opts[:endpoint]

        begin
          attempts += 1
          conn = http_connection
          ::NewRelic::Agent.logger.debug "Sending request to #{opts[:collector]}#{opts[:uri]} with #{request.method}"
          Timeout.timeout(@request_timeout) do
            response = conn.request(request)
          end
        rescue *CONNECTION_ERRORS => e
          close_shared_connection
          if attempts < max_attempts
            ::NewRelic::Agent.logger.debug("Retrying request to #{opts[:collector]}#{opts[:uri]} after #{e}")
            retry
          else
            raise ServerConnectionException, "Recoverable error talking to #{@collector} after #{attempts} attempts: #{e}"
          end
        end

        log_response(response)

        case response
        when Net::HTTPSuccess,
             Net::HTTPAccepted
          true # do nothing
        when Net::HTTPRequestTimeOut,
             Net::HTTPTooManyRequests,
             Net::HTTPInternalServerError,
             Net::HTTPServiceUnavailable
          record_endpoint_attempts_supportability_metrics(endpoint)
          raise ServerConnectionException, "#{response.code}: #{response.message}"
        when Net::HTTPBadRequest,
             Net::HTTPForbidden,
             Net::HTTPNotFound,
             Net::HTTPMethodNotAllowed,
             Net::HTTPProxyAuthenticationRequired,
             Net::HTTPLengthRequired,
             Net::HTTPRequestEntityTooLarge,
             Net::HTTPRequestURITooLong,
             Net::HTTPUnsupportedMediaType,
             Net::HTTPExpectationFailed,
             Net::HTTPUnsupportedMediaType,
             Net::HTTPRequestHeaderFieldsTooLarge
          record_endpoint_attempts_supportability_metrics(endpoint)
          record_error_response_supportability_metrics(response.code)
          raise UnrecoverableServerException, "#{response.code}: #{response.message}"
        when Net::HTTPConflict,
             Net::HTTPUnauthorized
          record_endpoint_attempts_supportability_metrics(endpoint)
          record_error_response_supportability_metrics(response.code)
          raise ForceRestartException, "#{response.code}: #{response.message}"
        when Net::HTTPGone
          record_endpoint_attempts_supportability_metrics(endpoint)
          record_error_response_supportability_metrics(response.code)
          raise ForceDisconnectException, "#{response.code}: #{response.message}"
        else
          record_endpoint_attempts_supportability_metrics(endpoint)
          record_error_response_supportability_metrics(response.code)
          raise UnrecoverableServerException, "#{response.code}: #{response.message}"
        end
        response
      end

      def log_response(response)
        ::NewRelic::Agent.logger.debug "Received response, status: #{response.code}, encoding: '#{response['content-encoding']}'"
      end

      # Per protocol 17, this metric should be recorded for all error response codes
      # that cause data to be discarded.
      def record_error_response_supportability_metrics(response_code)
        ::NewRelic::Agent.increment_metric("Supportability/Agent/Collector/HTTPError/#{response_code}")
      end

      def record_endpoint_attempts_supportability_metrics(endpoint)
        ::NewRelic::Agent.increment_metric("Supportability/Agent/Collector/#{endpoint}/Attempts")
      end

      # Decompresses the response from the server, if it is gzip
      # encoded, otherwise returns it verbatim
      def decompress_response(response)
        if response['content-encoding'] == 'gzip'
          Zlib::GzipReader.new(StringIO.new(response.body)).read
        else
          response.body
        end
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
    end
  end
end
