# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if !NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported? && defined? ::Rack

class RackUnsupportedVersionTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent

  include Rack::Test::Methods

  class SimpleMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end

  class ExampleApp
    def call(env)
      [200, {}, [self.class.name]]
    end
  end

  def app
    Rack::Builder.app do
      use SimpleMiddleware
      run ExampleApp.new
    end
  end

  def test_no_instrumentation_when_not_supported
    get '/'
    assert_metrics_recorded_exclusive([], :ignore_filter => /^Supportability/)
  end
end

end
