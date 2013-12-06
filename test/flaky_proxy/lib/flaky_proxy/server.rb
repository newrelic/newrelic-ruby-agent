module FlakyProxy
  class Server
    attr_reader :host, :port

    def initialize(host, port)
      @host = host
      @port = port
    end

    def open_socket
      TCPSocket.new(@host, @port)
    end

    def to_s
      "#{@host}:#{@port}"
    end
  end
end
