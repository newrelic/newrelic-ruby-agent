# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

require './app'

class MiddlewareInstrumentationTest < ActionDispatch::IntegrationTest
  def test_rails_middleware_records_metrics
    get('/')
    assert_metrics_recorded('Nested/Controller/Rack/Rails::Rack::Logger/call')
  end
end
