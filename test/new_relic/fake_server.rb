# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'webrick'
require 'webrick/https'
require 'rack'
require 'rack/handler'
require 'timeout'

require 'json' if RUBY_VERSION >= '1.9'

module NewRelic
  class FakeServer

    # Use ephemeral ports by default
    DEFAULT_PORT = 0

    # Default server options
    DEFAULT_OPTIONS = {
      :Logger    => ::WEBrick::Log.new('/dev/null'),
      :AccessLog => [ ['/dev/null', ''] ]
    }

    CONFIG_PATH = File.join(File.dirname(__FILE__), "..", "config")

    SSL_OPTIONS = {
      :SSLEnable => true,
      :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
      :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.open(File.join(CONFIG_PATH, "test.cert.key")).read),
      :SSLCertificate => OpenSSL::X509::Certificate.new(File.open(File.join(CONFIG_PATH, "test.cert.crt")).read),
      :SSLCertName => [["CN", "newrelic.com"]]
    }

    def initialize( port=DEFAULT_PORT, ssl=false )
      @thread = nil

      defaults = $DEBUG ? {} : DEFAULT_OPTIONS
      @options = defaults.merge( :Port => port )

      @options.merge!(SSL_OPTIONS) if ssl

      @server = WEBrick::HTTPServer.new( @options )
      @server.mount "/", ::Rack::Handler.get( :webrick ), app
    end


    attr_reader :server

    # Run the server, returning the Thread it is running in.
    def run( port=nil )
      return if @thread && @thread.alive?
      @server.listen( @options[:BindAddress], port ) if port
      @thread = Thread.new( &self.method(:run_server) )
      return @thread
    end


    # Thread routine for running the server.
    def run_server
      Thread.current.abort_on_exception = true
      @server.start
    end


    def stop
      return unless @thread.alive?
      @server.shutdown
      @server = nil
      @thread.join
      reset
    end


    def ports
      @server.listeners.map {|sock| sock.addr[1] }
    end

    def port
      self.ports.first
    end
    alias_method :determine_port, :port

  end
end
