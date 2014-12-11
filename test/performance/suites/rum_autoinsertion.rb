# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class RumAutoInsertion < Performance::TestCase
  attr_reader :browser_monitor, :html, :html_with_meta, :html_with_meta_after

  def setup
    # Don't require until we're actually running tests to avoid weirdness in
    # the parent runner process...
    require 'new_relic/agent'
    require 'new_relic/rack/browser_monitoring'

    NewRelic::Agent.manual_start
    @config = {
      :beacon                 => 'beacon',
      :browser_key            => 'browserKey',
      :application_id         => '5, 6', # collector can return app multiple ids
      :'rum.enabled'          => true,
      :license_key            => 'a' * 40,
      :js_agent_loader        => 'loader'
    }
    NewRelic::Agent.config.add_config_for_testing(@config)

    @app = Class.new do
      attr_accessor :text

      def call(*_)
        [200, { "Content-Type" => "text/html" }, [text]]
      end
    end.new

    @browser_monitor = NewRelic::Rack::BrowserMonitoring.new(@app)

    @html = "<html><head>#{'<script>alert("boo");</script>' * 1_000}</head><body></body></html>"
    @html_with_meta = "<html><head><meta http-equiv='X-UA-Compatible' content='IE=7'/>#{'<script>alert("boo");</script>' * 1_000}</head><body></body></html>"
    @html_with_meta_after = "<html><head>#{'<script>alert("boo");</script>' * 1_000}<meta http-equiv='X-UA-Compatible' content='IE=7'/></head><body></body></html>"

    host_class = Class.new do
      include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

      def run
        yield
      end
      add_transaction_tracer :run
    end

    @host = host_class.new
  end

  def teardown
    NewRelic::Agent.shutdown
  end

  def test_rum_autoinsertion
    run_autoinstrument_source(html)
  end

  def test_rum_autoinsertion_with_x_ua_compatible
    run_autoinstrument_source(html_with_meta)
  end

  def test_rum_autoinsertion_with_x_ua_compatible_after
    run_autoinstrument_source(html_with_meta_after)
  end

  def run_autoinstrument_source(text)
    @app.text = text
    @host.run do
      measure do
        browser_monitor.call({})
      end
    end
  end
end
