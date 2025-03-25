# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'webrick'
require 'webrick/https'
require 'rack'
require 'rackup/handler' unless /^1|^2/.match?(Rack.release)
require 'timeout'
require 'json'

module NewRelic
  class FakeServer
    # Use ephemeral ports by default
    DEFAULT_PORT = 0

    # Ignore all WEBrick output by default. Set ENV['DEBUG'] to enable it
    WEBRICK_OUTPUT_DEVICE = ENV['DEBUG'] ? STDOUT : '/dev/null'

    # Default server options
    DEFAULT_OPTIONS = {
      :Logger => ::WEBrick::Log.new((WEBRICK_OUTPUT_DEVICE)),
      :AccessLog => [[WEBRICK_OUTPUT_DEVICE, '']]
    }

    CONFIG_PATH = String.new(File.join(File.dirname(__FILE__), '..', 'config'))
    FAKE_SSL_CERT_PATH = File.join(CONFIG_PATH, (+'test.cert.crt'))
    FAKE_SSL_KEY_PATH = File.join(CONFIG_PATH, (+'test.cert.key'))

    SSL_OPTIONS = {
      :SSLEnable => true,
      :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
      :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.read(FAKE_SSL_KEY_PATH)),
      :SSLCertificate => OpenSSL::X509::Certificate.new(File.read(FAKE_SSL_CERT_PATH)),
      :SSLCertName => [[+'CN', +'newrelic.com']]
    }

    def initialize(port = DEFAULT_PORT)
      @port = port
      @thread = nil
      @server = nil
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
      @thread&.alive?
    end

    def run
      return if running?

      @started_options = build_webrick_options

      @server = WEBrick::HTTPServer.new(@started_options)
      @server.mount((+'/'), webrick_handler, app)

      @thread = Thread.new(&self.method(:run_server)).tap { |t| t.abort_on_exception = true }
    end

    def stop
      return unless running?

      @server.shutdown
      @server = nil
      @thread.join if running?
      @started_options = nil
      reset
    end

    def webrick_handler
      handler = defined?(::Rackup) ? ::Rackup::Handler : ::Rack::Handler
      handler.get(:webrick)
    end

    def build_webrick_options
      options = DEFAULT_OPTIONS.merge(:Port => @port)
      options.merge!(SSL_OPTIONS) if use_ssl?
      options
    end

    def run_server
      @server.start
    end

    def ports
      @server.listeners.map { |sock| sock.addr[1] }
    end

    def port
      self.ports.first
    end
  end

  class FakeForbiddenServer < FakeServer
    def reset
      # NOP
    end

    def call(env)
      req = ::Rack::Request.new(env)
      res = ::Rack::Response.new
      res.status = 403
      res.body = [+"Forbidden\n"]
      res.finish
    end

    def app
      inner_app = NewRelic::Rack::AgentHooks.new(self)
      proc { |env| inner_app.call(env) }
    end
  end

  class FakeInternalErrorServer < FakeServer
    def reset
      # NOP
    end

    def call(env)
      raise (+'something went wrong!')
    end

    def app
      inner_app = NewRelic::Rack::AgentHooks.new(self)
      proc { |env| inner_app.call(env) }
    end
  end
end
