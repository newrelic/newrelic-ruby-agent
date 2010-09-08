module NewRelic
  class Control

    # Structs holding info for the remote server and proxy server
    class Server < Struct.new :name, :port, :ip #:nodoc:
      def to_s; "#{name}:#{port}"; end
    end

    ProxyServer = Struct.new :name, :port, :user, :password #:nodoc:

    module ServerMethods

      def server
        @remote_server ||= server_from_host(nil)
      end

      def api_server
        api_host = self['api_host'] || 'rpm.newrelic.com'
        @api_server ||=
          NewRelic::Control::Server.new \
        api_host,
        (self['api_port'] || self['port'] || (use_ssl? ? 443 : 80)).to_i,
        nil
      end

      def proxy_server
        @proxy_server ||=
          NewRelic::Control::ProxyServer.new self['proxy_host'], self['proxy_port'], self['proxy_user'], self['proxy_pass']
      end

      def server_from_host(hostname=nil)
        host = hostname || self['host'] || 'collector.newrelic.com'

        # if the host is not an IP address, turn it into one
        NewRelic::Control::Server.new host, (self['port'] || (use_ssl? ? 443 : 80)).to_i, convert_to_ip_address(host)
      end

      # Look up the ip address of the host using the pure ruby lookup
      # to prevent blocking.  If that fails, fall back to the regular
      # IPSocket library.  Return nil if we can't find the host ip
      # address and don't have a good default.
      def convert_to_ip_address(host)
        # here we leave it as a host name since the cert verification
        # needs it in host form
        return host if verify_certificate?
        return nil if host.nil? || host.downcase == "localhost"
        # Fall back to known ip address in the common case
        ip_address = '65.74.177.195' if host.downcase == 'collector.newrelic.com'
        begin
          ip_address = Resolv.getaddress(host)
          log.info "Resolved #{host} to #{ip_address}"
        rescue => e
          log.warn "DNS Error caching IP address: #{e}"
          log.debug e.backtrace.join("\n   ")
          ip_address = IPSocket::getaddress host rescue ip_address
        end
        ip_address
      end

      # Return the Net::HTTP with proxy configuration given the NewRelic::Control::Server object.
      # Default is the collector but for api calls you need to pass api_server
      #
      # Experimental support for SSL verification:
      # swap 'VERIFY_NONE' for 'VERIFY_PEER' line to try it out
      # If verification fails, uncomment the 'http.ca_file' line
      # and it will use the included certificate.
      def http_connection(host = nil)
        host ||= server
        # Proxy returns regular HTTP if @proxy_host is nil (the default)
        http_class = Net::HTTP::Proxy(proxy_server.name, proxy_server.port,
                                      proxy_server.user, proxy_server.password)
        http = http_class.new(host.ip || host.name, host.port)
        log.debug("Http Connection opened to #{host.ip||host.name}:#{host.port}")
        if use_ssl?
          http.use_ssl = true
          if verify_certificate?
            http.verify_mode = OpenSSL::SSL::VERIFY_PEER
            http.ca_file = File.join(File.dirname(__FILE__), '..', '..', 'cert', 'cacert.pem')
          else
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
        end
        http
      end
    end
  end
end

