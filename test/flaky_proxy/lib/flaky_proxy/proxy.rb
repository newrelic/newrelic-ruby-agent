require 'socket'

module FlakyProxy
  class Proxy
    def initialize(bind_host, bind_port, target_host, target_port)
      @bind_host = bind_host
      @bind_port = bind_port
      @listen_socket = nil
      @backend_server = Server.new(target_host, target_port)
      @rules = RuleSet.build('')
    end

    def watch_rules_file(rules_file_path)
      @rules_file_path = rules_file_path
    end

    def reload_rules_file
      if @rules_file_path
        mtime = File.stat(@rules_file_path).mtime
        if @last_rules_mtime.nil? || mtime > @last_rules_mtime
          FlakyProxy.log.info("Reloading rules file at #{@rules_file_path}")
          @rules = RuleSet.build(File.read(@rules_file_path))
          @last_rules_mtime = mtime
        end
      end
    end

    def run
      FlakyProxy.log.info("Starting FlakyProxy on #{@bind_host}:#{@bind_port} -> #{@backend_server.to_s}")
      @listen_socket = TCPServer.new(@bind_host, @bind_port)
      loop do
        client_socket = @listen_socket.accept
        reload_rules_file
        FlakyProxy.log.info("Accepted connection from #{client_socket}")
        connection = Connection.new(client_socket, @backend_server, @rules)
        connection.service
        FlakyProxy.log.info("Finished servicing connection from #{client_socket}")
      end
    end
  end
end
