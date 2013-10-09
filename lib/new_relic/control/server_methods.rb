# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  class Control

    # Structs holding info for the remote server and proxy server
    class Server < Struct.new :name, :port, :ip #:nodoc:
      def to_s; "#{name}:#{port}"; end
    end

    ProxyServer = Struct.new :name, :port, :user, :password #:nodoc:

    # Contains methods that deal with connecting to the server
    module ServerMethods

      def server
        @remote_server ||= server_from_host(nil)
      end

      # the server we should contact for api requests, like uploading
      # deployments and the like
      def api_server
        @api_server ||= NewRelic::Control::Server.new(Agent.config[:api_host], Agent.config[:api_port], nil)
      end

      # a new instances of the proxy server - this passes through if
      # there is no proxy, otherwise it has proxy configuration
      # information pulled from the config file
      def proxy_server
        @proxy_server ||= NewRelic::Control::ProxyServer.new(Agent.config[:proxy_host],
                                                             Agent.config[:proxy_port],
                                                             Agent.config[:proxy_user],
                                                             Agent.config[:proxy_pass])
      end

      # turns a hostname into an ip address and returns a
      # NewRelic::Control::Server that contains the configuration info
      def server_from_host(hostname=nil)
        host = hostname || Agent.config[:host]

        # if the host is not an IP address, turn it into one
        NewRelic::Control::Server.new(host, Agent.config[:port],
                                      convert_to_ip_address(host))
      end

      # Check to see if we need to look up the IP address
      # If it's an IP address already, we pass it through.
      # If it's nil, or localhost, we don't bother.
      # Otherwise, use `resolve_ip_address` to find one
      def convert_to_ip_address(host)
        # here we leave it as a host name since the cert verification
        # needs it in host form
        return host if Agent.config[:ssl]
        # We won't talk directly to the host, so no need to resolve if proxy configured
        return host if Agent.config[:proxy_host]
        return nil if host.nil? || host.downcase == "localhost"
        ip = resolve_ip_address(host)

        ::NewRelic::Agent.logger.debug "Resolved #{host} to #{ip}"
        ip
      end

      # Look up the ip address of the host using the pure ruby lookup
      # to prevent blocking.  If that fails, fall back to the regular
      # IPSocket library.  Return nil if we can't find the host ip
      # address and don't have a good default.
      def resolve_ip_address(host)
        Resolv.getaddress(host)
      rescue => e
        ::NewRelic::Agent.logger.warn("DNS Error caching IP address:", e)
        begin
          ::NewRelic::Agent.logger.debug("Trying native DNS lookup since Resolv failed")
          IPSocket.getaddress(host)
        rescue => e
          ::NewRelic::Agent.logger.error("Could not look up server address: #{e}")
          nil
        end
      end
    end

    include ServerMethods
  end
end
