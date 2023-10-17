# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../lib/new_relic/agent/instrumentation/roda/instrumentation'
require_relative '../../../../lib/new_relic/agent/instrumentation/roda/roda_transaction_namer'
require_relative '../../../../lib/new_relic/agent/instrumentation/roda/ignorer'

JS_AGENT_LOADER = 'JS_AGENT_LOADER'

def assert_enduser_ignored(response)
  refute_match(/#{JS_AGENT_LOADER}/o, response.body)
end

def refute_enduser_ignored(response)
  assert_match(/#{JS_AGENT_LOADER}/o, response.body)
end

def fake_html_for_browser_timing_header
  '<html><head><title></title></head><body></body></html>'
end

class RodaIgnorerTestApp < Roda
  newrelic_ignore('/ignore_me', '/ignore_me_too')
  newrelic_ignore('no_leading_slash')
  newrelic_ignore('/ignored_erroring')

  route do |r|
    r.on('/home') { 'home' }
    r.on('/ignore_me') { 'this page is ignored' }
    r.on('/ignore_me_too') { 'this page is ignored too' }
    r.on('/ignore_me_not') { 'our regex should not capture this' }
    r.on('no_leading_slash') { 'user does not use leading slash for ignore' }
    r.on('/no_apdex') { 'no apex should be recorded' }
    r.on('/ignored_erroring') { raise 'boom' }
  end
end

class RodaIgnoreTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    RodaIgnorerTestApp
  end

  def test_seen_route
    get('/home')

    assert_metrics_recorded('Controller/Roda/RodaIgnorerTestApp/GET home')
  end

  def test_ignore_route
    get('/ignore_me')

    assert_metrics_not_recorded([
      'Controller/Roda/RodaIgnorerTestApp/GET ignore_me',
      'Apdex/Roda/RodaIgnorerTestApp/GET ignore_me'
    ])
  end

  def test_regex_ignores_intended_route
    get('/ignore_me')
    get('/ignore_me_not')

    assert_metrics_not_recorded([
      'Controller/Roda/RodaIgnorerTestApp/GET ignore_me',
      'Apdex/Roda/RodaIgnorerTestApp/GET ignore_me'
    ])

    assert_metrics_recorded([
      'Controller/Roda/RodaIgnorerTestApp/GET ignore_me_not',
      'Apdex/Roda/RodaIgnorerTestApp/GET ignore_me_not'
    ])
  end

  def test_ignores_if_route_does_not_have_leading_slash
    get('no_leading_slash')

    assert_metrics_not_recorded([
      'Controller/Roda/RodaIgnorerTestApp/GET no_leading_slash',
      'Apdex/Roda/RodaIgnorerTestApp/GET no_leading_slash'
    ])
  end

  def test_ignore_errors_in_ignored_transactions
    get('/ignored_erroring')

    assert_metrics_not_recorded(['Errors/all'])
  end
end

class RodaIgnoreAllRoutesApp < Roda
  # newrelic_ignore called without any arguments will ignore the entire app
  newrelic_ignore

  route do |r|
    r.on('home') { 'home' }
    r.on('hello') { 'hello' }
  end
end

class RodaIgnoreAllRoutesAppTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    RodaIgnoreAllRoutesApp
  end

  def test_ignores_by_splats
    get('/hello')
    get('/home')

    assert_metrics_not_recorded([
      'Controller/Roda/RodaIgnoreAllTestApp/GET hello',
      'Apdex/Roda/RodaIgnoreAllTestApp/GET hello'
    ])

    assert_metrics_not_recorded([
      'Controller/Roda/RodaIgnoreAllTestApp/GET home',
      'Apdex/Roda/RodaIgnoreAllTestApp/GET home'
    ])
  end
end

class RodaIgnoreApdexApp < Roda
  # newrelic_ignore called without any arguments will ignore the entire app
  newrelic_ignore_apdex('/no_apdex')

  route do |r|
    r.on('home') { 'home' }
    r.on('no_apdex') { 'do not record apdex' }
  end
end

class RodaIgnoreApdexAppTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  def app
    RodaIgnoreApdexApp
  end

  def test_ignores_apdex_by_route
    get('/no_apdex')

    assert_metrics_not_recorded('Apdex/Roda/RodaIgnoreApdexApp/GET no_apdex')
  end

  def test_ignores_enduser_but_not_route
    get('no_apdex')

    assert_metrics_recorded('Controller/Roda/RodaIgnoreApdexApp/GET no_apdex')
    assert_metrics_not_recorded('Apdex/Roda/RodaIgnoreApdexApp/GET no_apdex')
  end
end

class RodaIgnoreEndUserApp < Roda
  newrelic_ignore_enduser('ignore_enduser')

  route do |r|
    r.on('home') { fake_html_for_browser_timing_header }
    r.on('ignore_enduser') { fake_html_for_browser_timing_header }
  end
end

class RodaIgnoreEndUserAppTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent(:application_id => 'appId',
    :beacon => 'beacon',
    :browser_key => 'browserKey',
    :js_agent_loader => 'JS_AGENT_LOADER')

  def app
    RodaIgnoreEndUserApp
  end

  def test_ignore_enduser_should_only_apply_to_specified_route
    with_config(:application_id => 'appId',
      :beacon => 'beacon',
      :browser_key => 'browserKey',
      :js_agent_loader => 'JS_AGENT_LOADER') do
      get('home')

      refute_enduser_ignored(last_response)
      assert_metrics_recorded('Controller/Roda/RodaIgnoreEndUserApp/GET home')
    end
  end

  def test_ignores_enduser
    get('ignore_enduser')

    assert_enduser_ignored(last_response)
  end
end
