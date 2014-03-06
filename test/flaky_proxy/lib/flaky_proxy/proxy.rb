# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'socket'

module FlakyProxy
  class Proxy
    def initialize(options)
      @listen_host = options.fetch(:listen_host)
      @listen_port = options.fetch(:listen_port)
      @backend_server = Server.new(options.fetch(:target_host), options.fetch(:target_port))
      @rules = RuleSet.build('')
      @rules_path = options[:rules_path]
      @listen_socket = nil
      reload_rules_file
    end

    def service_connection(client_socket)
      with_connection_logging(client_socket) do
        Connection.new(client_socket, @backend_server, @rules).service
      end
    rescue => e
      FlakyProxy.logger.error("Error servicing connection: #{e}, from #{e.backtrace.join("\n")}")
    end

    def reload_rules_file
      if @rules_path
        mtime = File.stat(@rules_path).mtime
        if @last_rules_mtime.nil? || mtime > @last_rules_mtime
          FlakyProxy.logger.info("Reloading rules file at #{@rules_path}")
          @rules = RuleSet.build(File.read(@rules_path))
          @last_rules_mtime = mtime
        end
      end
    rescue => e
      FlakyProxy.logger.error("Error reloading rules file at #{@rules_path}: #{e}\n#{e.backtrace.join("\n")}")
    end

    def with_connection_logging(client_socket)
      peer_info = client_socket.peeraddr(:hostname)
      client_str = "#{peer_info[2]}:#{peer_info[1]}"
      FlakyProxy.logger.info("Accepted connection from #{client_str}")
      yield
      FlakyProxy.logger.info("Finished servicing connection from #{client_str}")
    end

    def run
      FlakyProxy.logger.info("Starting FlakyProxy on #{@listen_host}:#{@listen_port} -> #{@backend_server.to_s}")
      @listen_socket = TCPServer.new(@listen_host, @listen_port)
      loop do
        client_socket = @listen_socket.accept
        service_connection(client_socket)
        reload_rules_file
      end
    end
  end
end
