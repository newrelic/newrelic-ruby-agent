# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "grape"
require "newrelic_rpm"
require 'multiverse_helpers'
require './test_api'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class GrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  if ::Grape::VERSION == '0.1.5'
    def app
      TestApi
    end

    def test_unsupported_version
      get '/grape_ape'
      get '/grape_ape/1'
      post '/grape_ape', {}
      put '/grape_ape/1', {}
      delete '/grape_ape/1'

      assert_metrics_not_recorded(['Controller/Rack/TestApi/grape_ape (GET)'])
      assert_metrics_not_recorded(['Controller/Rack/TestApi/grape_ape/:id (GET)'])
      assert_metrics_not_recorded(['Controller/Rack/TestApi/grape_ape (POST)'])
      assert_metrics_not_recorded(['Controller/Rack/TestApi/grape_ape/:id (PUT)'])
      assert_metrics_not_recorded(['Controller/Rack/TestApi/grape_ape/:id (DELETE)'])
    end
  end
end
