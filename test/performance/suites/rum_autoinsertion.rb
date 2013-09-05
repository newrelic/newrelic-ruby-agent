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
      :disable_mobile_headers => false,
      :browser_key            => 'browserKey',
      :application_id         => '5, 6', # collector can return app multiple ids
      :'rum.enabled'          => true,
      :episodes_file          => 'this_is_my_file',
      :'rum.jsonp'            => true,
      :license_key            => 'a' * 40
    }
    NewRelic::Agent.config.apply_config(@config)
    NewRelic::Agent.instance.instance_eval do
      @beacon_configuration = NewRelic::Agent::BeaconConfiguration.new
    end

    @browser_monitor = NewRelic::Rack::BrowserMonitoring.new(nil)
    @html = "<html><head>#{'<script>alert("boo");</script>' * 1_000}</head><body></body></html>"
    @html_with_meta = "<html><head><meta http-equiv='X-UA-Compatible' content='IE=7'/>#{'<script>alert("boo");</script>' * 1_000}</head><body></body></html>"
    @html_with_meta_after = "<html><head>#{'<script>alert("boo");</script>' * 1_000}<meta http-equiv='X-UA-Compatible' content='IE=7'/></head><body></body></html>"
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
    iterations.times do
      browser_monitor.autoinstrument_source([text], {})
    end
  end
end
