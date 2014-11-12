# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "grape"
require "newrelic_rpm"
require 'multiverse_helpers'
require './grape_test_api'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class GrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  setup_and_teardown_agent

  unless ::Grape::VERSION == '0.1.5'
    def app
      Rack::Builder.app { run GrapeTestApi.new }
    end

    def test_nonexistent_route
      get '/not_grape_ape'
      assert_no_metrics_match(/grape_ape/)
    end

    def test_route_raises_an_error
      assert_raises(GrapeTestApiError) do
        get '/self_destruct'
      end
      assert_metrics_recorded(['Errors/Controller/Rack/GrapeTestApi/self_destruct (GET)'])
    end

    def test_getting_a_list_of_grape_apes
      get '/grape_ape'
      assert_metrics_recorded(['Controller/Rack/GrapeTestApi/grape_ape (GET)'])
    end

    def test_showing_a_grape_ape
      get '/grape_ape/1'
      assert_metrics_recorded(['Controller/Rack/GrapeTestApi/grape_ape/:id (GET)'])
    end

    def test_creating_a_grape_ape
      post '/grape_ape', {}
      assert_metrics_recorded(['Controller/Rack/GrapeTestApi/grape_ape (POST)'])
    end

    def test_updating_a_grape_ape
      put '/grape_ape/1', {}
      assert_metrics_recorded(['Controller/Rack/GrapeTestApi/grape_ape/:id (PUT)'])
    end

    def test_deleting_a_grape_ape
      delete '/grape_ape/1'
      assert_metrics_recorded(['Controller/Rack/GrapeTestApi/grape_ape/:id (DELETE)'])
    end
  end
end
