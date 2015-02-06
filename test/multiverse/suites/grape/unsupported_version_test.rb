# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "grape"
require "newrelic_rpm"
require './grape_test_api'

class UnsupportedGrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  if ::Grape::VERSION == '0.1.5'
    def app
      GrapeTestApi
    end

    def test_unsupported_version
      get '/grape_ape'
      get '/grape_ape/1'
      post '/grape_ape', {}
      put '/grape_ape/1', {}
      delete '/grape_ape/1'

      assert_no_metrics_match(/grape_ape/)
    end
  end
end
