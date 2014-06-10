# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

require './app'

if Rails::VERSION::MAJOR.to_i >= 3

class MiddlewareInstrumentationTest < RailsMultiverseTest
  def test_rails_middleware_records_metrics
    get('/')
    assert_metrics_recorded(
      ['Middleware/all', 'Middleware/Rack/Rails::Rack::Logger/call']
    )
  end

  def test_rails_routeset_is_instrumented
    get('/')
    assert_metrics_recorded(
      'Middleware/Rack/ActionDispatch::Routing::RouteSet/call'
    )
  end

  if Rails::VERSION::MAJOR >= 4
    def test_rails_middlewares_constructed_by_name
      get('/')
      assert response.headers['NamedMiddleware'], "NamedMiddleware should have been called, but wasn't"
      assert_metrics_recorded('Middleware/Rack/NamedMiddleware/call')
    end

    def test_rails_middlewares_passed_as_instances
      get('/')
      assert response.headers['InstanceMiddleware'], "InstanceMiddleware should have been called, but wasn't"
      assert_metrics_recorded('Middleware/Rack/InstanceMiddleware/call')
    end
  end
end

end
