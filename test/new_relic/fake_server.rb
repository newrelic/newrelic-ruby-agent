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
      :AccessLog => [['/dev/null', '']]
    }

    CONFIG_PATH        = File.join(File.dirname(__FILE__), "..", "config")
    FAKE_SSL_CERT_PATH = File.join(CONFIG_PATH, "test.cert.crt")
    FAKE_SSL_KEY_PATH  = File.join(CONFIG_PATH, "test.cert.key")

    SSL_OPTIONS = {
      :SSLEnable       => true,
      :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
      :SSLPrivateKey   => OpenSSL::PKey::RSA.new(File.read(FAKE_SSL_KEY_PATH)),
      :SSLCertificate  => OpenSSL::X509::Certificate.new(File.read(FAKE_SSL_CERT_PATH)),
      :SSLCertName     => [["CN", "newrelic.com"]]
    }

    def initialize(port=DEFAULT_PORT)
      @port    = port
      @thread  = nil
      @sever   = nil
      @use_ssl = false
    end

    def use_ssl=(value)
      @use_ssl = value
    end

    def use_ssl?
      @use_ssl
    end

    def needs_restart?
      @started_options != build_webrick_options
    end

    def restart
      stop
      run
    end

    def running?
      @thread && @thread.alive?
    end

    def run
      return if running?

      @started_options = build_webrick_options

      @server = WEBrick::HTTPServer.new(@started_options)
      @server.mount "/", ::Rack::Handler.get(:webrick), app

      @thread = Thread.new(&self.method(:run_server))
    end

    def stop
      return unless running?
      @server.shutdown
      @server = nil
      @thread.join
      @started_options = nil
      reset
    end

    def build_webrick_options
      options = DEFAULT_OPTIONS.merge(:Port => @port)
      options.merge!(SSL_OPTIONS) if use_ssl?
      options
    end

    def run_server
      Thread.current.abort_on_exception = true
      @server.start
    end

    def ports
      @server.listeners.map { |sock| sock.addr[1] }
    end

    def port
      self.ports.first
    end
  end
end
