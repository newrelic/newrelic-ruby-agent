require 'socket'

module FlakyProxy
  class Proxy
    def initialize(options)
      @listen_host = options[:listen_host]
      @listen_port = options[:listen_port]
      @backend_server = Server.new(options[:target_host], options[:target_port])
      @rules = RuleSet.build('')
      @rules_path = options[:rules_path]
      @listen_socket = nil
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
    end

    def run
      FlakyProxy.logger.info("Starting FlakyProxy on #{@listen_host}:#{@listen_port} -> #{@backend_server.to_s}")
      @listen_socket = TCPServer.new(@listen_host, @listen_port)
      loop do
        client_socket = @listen_socket.accept
        reload_rules_file
        FlakyProxy.logger.info("Accepted connection from #{client_socket}")
        connection = Connection.new(client_socket, @backend_server, @rules)
        connection.service
        FlakyProxy.logger.info("Finished servicing connection from #{client_socket}")
      end
    end
  end
end
