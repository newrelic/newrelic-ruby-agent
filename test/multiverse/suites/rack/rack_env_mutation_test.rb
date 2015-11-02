# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

if NewRelic::Agent::Instrumentation::RackHelpers.rack_version_supported?

require 'new_relic/rack/browser_monitoring'
require 'new_relic/rack/agent_hooks'
require 'new_relic/rack/error_collector'

class RackEnvMutationTest < Minitest::Test
  attr_accessor :inner_app

  include MultiverseHelpers
  include Rack::Test::Methods

  setup_and_teardown_agent

  class BadApp
    def call(env)
      Thread.new do
        100.times do
          env.each do |k, v|
            # allow main thread to run while we're still in the middle of
            # iterating
            Thread.pass
          end
        end
      end

      # Give the thread we just spawned a chance to start up
      Thread.pass

      [200, {}, ['cool story']]
    end
  end

  def app
    inner_app = BadApp.new
    Rack::Builder.app do
      use NewRelic::Rack::AgentHooks
      run inner_app
    end
  end

  def test_safe_from_iterations_over_rack_env_from_background_threads
    100.times do
      get '/'
    end
  end
end

end
