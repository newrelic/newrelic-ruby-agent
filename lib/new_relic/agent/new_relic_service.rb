# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'zlib'
require 'new_relic/agent/audit_logger'
require 'new_relic/agent/new_relic_service/encoders'
require 'new_relic/agent/new_relic_service/marshaller'
require 'new_relic/agent/new_relic_service/json_marshaller'
require 'new_relic/agent/new_relic_service/pruby_marshaller'

module NewRelic
  module Agent
    class NewRelicService
      # Specifies the version of the agent's communication protocol with
      # the NewRelic hosted site.

      PROTOCOL_VERSION = 12
      # 1f147a42: v10 (tag 3.5.3.17)
      # cf0d1ff1: v9 (tag 3.5.0)
      # 14105: v8 (tag 2.10.3)
      # (no v7)
      # 10379: v6 (not tagged)
      # 4078:  v5 (tag 2.5.4)
      # 2292:  v4 (tag 2.3.6)
      # 1754:  v3 (tag 2.3.0)
      # 534:   v2 (shows up in 2.1.0, our first tag)

      attr_accessor :request_timeout, :agent_id
      attr_reader :collector, :marshaller, :metric_id_cache

      def initialize(license_key=nil, collector=control.server)
        @license_key = license_key || Agent.config[:license_key]
        @collector = collector
        @request_timeout = Agent.config[:timeout]
        @metric_id_cache = {}

        @audit_logger = ::NewRelic::Agent::AuditLogger.new
        Agent.config.register_callback(:'audit_log.enabled') do |enabled|
          @audit_logger.enabled = enabled
        end
        Agent.config.register_callback(:ssl) do |ssl|
          if !ssl
            ::NewRelic::Agent.logger.warn("Agent is configured not to use SSL when communicating with New Relic's servers")
          else
            ::NewRelic::Agent.logger.debug("Agent is configured to use SSL")
          end
        end

        Agent.config.register_callback(:marshaller) do |marshaller|
          begin
            if marshaller == 'json'
              @marshaller = JsonMarshaller.new
            else
              @marshaller = PrubyMarshaller.new
            end
          rescue LoadError
            ::NewRelic::Agent.logger.warn("JSON marshaller requested, but the 'json' gem was not available, falling back to pruby. This will not be supported in future versions of the agent.")
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

      def reset_metric_id_cache
        @metric_id_cache = {}
      end

      # takes an array of arrays of spec and id, adds it into the
      # metric cache so we can save the collector some work by
      # sending integers instead of strings the next time around
      def fill_metric_id_cache(pairs_of_specs_and_ids)
        Array(pairs_of_specs_and_ids).each do |metric_spec_hash, metric_id|
          metric_spec = MetricSpec.new(metric_spec_hash['name'],
                                       metric_spec_hash['scope'])
          metric_id_cache[metric_spec] = metric_id
        end
      rescue => e
        # If we've gotten this far, we don't want this error to propagate and
        # make this post appear to have been non-successful, which would trigger
        # re-aggregation of the same metric data into the next post, so just log
        NewRelic::Agent.logger.error("Failed to fill metric ID cache from response, error details follow ", e)
      end

      # The collector wants to recieve metric data in a format that's different
      # from how we store it internally, so this method handles the translation.
      # It also handles translating metric names to IDs using our metric ID cache.
      def build_metric_data_array(stats_hash)
        metric_data_array = []
        stats_hash.each do |metric_spec, stats|
          # Omit empty stats as an optimization
          unless stats.is_reset?
            metric_id = metric_id_cache[metric_spec]
            metric_data = if metric_id
              NewRelic::MetricData.new(nil, stats, metric_id)
            else
              NewRelic::MetricData.new(metric_spec, stats, nil)
            end
            metric_data_array << metric_data
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
          @agent_id,
          timeslice_start.to_f,
          timeslice_end.to_f,
          metric_data_array
        )
        fill_metric_id_cache(result)
        result
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

      def agent_command_results(results)
        invoke_remote(:agent_command_results, @agent_id, results)
      end

      def get_xray_metadata(xray_ids)
        invoke_remote(:get_xray_metadata, @agent_id, *xray_ids)
      end

      # Send fine-grained analytic data to the collector.
      def analytic_event_data(data)
        invoke_remote(:analytic_event_data, @agent_id, data)
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

      # One session with the service's endpoint.  In this case the session
      # represents 1 tcp connection which may transmit multiple HTTP requests
      # via keep-alive.
      def session(&block)
        raise ArgumentError, "#{self.class}#shared_connection must be passed a block" unless block_given?

        begin
          t0 = Time.now
          if NewRelic::Agent.config[:aggressive_keepalive]
            session_with_keepalive(&block)
          else
            session_without_keepalive(&block)
          end
        rescue Timeout::Error
          elapsed = Time.now - t0
          ::NewRelic::Agent.logger.warn "Timed out opening connection to collector after #{elapsed} seconds. If this problem persists, please see http://status.newrelic.com"
          raise
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
          connection = create_http_connection
          NewRelic::Agent.logger.debug("Opening shared TCP connection to #{connection.address}:#{connection.port}")
          NewRelic::TimerLib.timeout(@request_timeout) { connection.start }
          @shared_tcp_connection = connection
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

      # Return a Net::HTTP connection object to make a call to the collector.
      # We'll reuse the same handle for cases where we're using keep-alive, or
      # otherwise create a new one.
      def http_connection
        @shared_tcp_connection || create_http_connection
      end

      # Return the Net::HTTP with proxy configuration given the NewRelic::Control::Server object.
      def create_http_connection
        proxy_server = control.proxy_server
        # Proxy returns regular HTTP if @proxy_host is nil (the default)
        http_class = Net::HTTP::Proxy(proxy_server.name, proxy_server.port,
                                      proxy_server.user, proxy_server.password)

        http = http_class.new((@collector.ip || @collector.name), @collector.port)
        if Agent.config[:ssl]
          begin
            # Jruby 1.6.8 requires a gem for full ssl support and will throw
            # an error when use_ssl=(true) is called and jruby-openssl isn't
            # installed
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            http.ca_file = cert_file_path
          rescue StandardError, LoadError
            msg = "Agent is configured to use SSL, but SSL is not available in the environment. "
            msg << "Either disable SSL in the agent configuration, or install SSL support."
            raise UnrecoverableAgentException.new(msg)
          end
        end

        if http.respond_to?(:keep_alive_timeout) && NewRelic::Agent.config[:aggressive_keepalive]
          http.keep_alive_timeout = NewRelic::Agent.config[:keep_alive_timeout]
        end

        ::NewRelic::Agent.logger.debug("Created net/http handle to #{http.address}:#{http.port}")
        http
      end


      # The path to the certificate file used to verify the SSL
      # connection if verify_peer is enabled
      def cert_file_path
        File.expand_path(File.join(control.newrelic_root, 'cert', 'cacert.pem'))
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
        start_ts = Time.now

        data, size, serialize_finish_ts = nil
        begin
          data = @marshaller.dump(args)
        rescue StandardError, SystemStackError => e
          handle_serialization_error(method, e)
        end
        serialize_finish_ts = Time.now

        data, encoding = compress_request_if_needed(data)
        size = data.size

        uri = remote_method_uri(method, @marshaller.format)
        full_uri = "#{@collector}#{uri}"

        @audit_logger.log_request(full_uri, args, @marshaller)
        response = send_request(:data      => data,
                                :uri       => uri,
                                :encoding  => encoding,
                                :collector => @collector)
        @marshaller.load(decompress_response(response))
      ensure
        record_supportability_metrics(method, start_ts, serialize_finish_ts, size)
      end

      def handle_serialization_error(method, e)
        NewRelic::Agent.increment_metric("Supportability/serialization_failure")
        NewRelic::Agent.increment_metric("Supportability/serialization_failure/#{method}")
        msg = "Failed to serialize #{method} data using #{@marshaller.class.to_s}: #{e.inspect}"
        error = SerializationError.new(msg)
        error.set_backtrace(e.backtrace)
        raise error
      end

      def record_supportability_metrics(method, start_ts, serialize_finish_ts, size)
        serialize_time = serialize_finish_ts && (serialize_finish_ts - start_ts)
        duration = (Time.now - start_ts).to_f
        NewRelic::Agent.record_metric("Supportability/invoke_remote", duration)
        NewRelic::Agent.record_metric("Supportability/invoke_remote/#{method.to_s}", duration)
        if serialize_time
          NewRelic::Agent.record_metric("Supportability/invoke_remote_serialize", serialize_time)
          NewRelic::Agent.record_metric("Supportability/invoke_remote_serialize/#{method.to_s}", serialize_time)
        end
        if size
          NewRelic::Agent.record_metric("Supportability/invoke_remote_size", size)
          NewRelic::Agent.record_metric("Supportability/invoke_remote_size/#{method.to_s}", size)
        end
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

        response = nil
        http = http_connection
        http.read_timeout = nil
        NewRelic::TimerLib.timeout(@request_timeout) do
          ::NewRelic::Agent.logger.debug "Sending request to #{opts[:collector]}#{opts[:uri]}"
          response = http.request(request)
        end
        case response
        when Net::HTTPSuccess
          true # fall through
        when Net::HTTPUnauthorized
          raise LicenseException, 'Invalid license key, please visit support.newrelic.com'
        when Net::HTTPServiceUnavailable
          raise ServerConnectionException, "Service unavailable (#{response.code}): #{response.message}"
        when Net::HTTPGatewayTimeOut
          raise Timeout::Error, response.message
        when Net::HTTPRequestEntityTooLarge
          raise UnrecoverableServerException, '413 Request Entity Too Large'
        when Net::HTTPUnsupportedMediaType
          raise UnrecoverableServerException, '415 Unsupported Media Type'
        else
          raise ServerConnectionException, "Unexpected response from server (#{response.code}): #{response.message}"
        end
        response
      rescue Timeout::Error, EOFError, SystemCallError, SocketError => e
        # These include Errno connection errors, and all signify that the
        # connection may be in a bad state, so drop it and re-create if needed.
        close_shared_connection
        raise NewRelic::Agent::ServerConnectionException, "Recoverable error connecting to #{@collector}: #{e}"
      end



      # Decompresses the response from the server, if it is gzip
      # encoded, otherwise returns it verbatim
      def decompress_response(response)
        if response['content-encoding'] != 'gzip'
          ::NewRelic::Agent.logger.debug "Uncompressed content returned"
          response.body
        else
          ::NewRelic::Agent.logger.debug "Decompressing return value"
          i = Zlib::GzipReader.new(StringIO.new(response.body))
          i.read
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

      # Used to wrap errors reported to agent by the collector
      class CollectorError < StandardError; end
    end
  end
end
