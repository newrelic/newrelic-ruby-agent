# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "grape"
require "newrelic_rpm"
require 'multiverse_helpers'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class TestApi < Grape::API
  namespace :grape_ape
    get do
      'List grape apes!'
    end

    get ':id' do
      'Show grape ape!'
    end

    post do
      'Create grape ape!'
    end

    put ':id' do
      'Update grape ape!'
    end

    delete ':id' do
      'Destroy grape ape!'
    end
end

class GrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  def app
    TestApi.new
  end

  def test_getting_a_list_of_grape_apes
    NewRelic::Agent.expects(:set_transaction_name).with('TestApi/grape_ape (GET)')
    get '/grape_ape'
  end

  def test_showing_a_grape_ape
    NewRelic::Agent.expects(:set_transaction_name).with('TestApi/grape_ape/:id (GET)')
    get '/grape_ape/1'
  end

  def test_creating_a_grape_ape
    NewRelic::Agent.expects(:set_transaction_name).with('TestApi/grape_ape (POST)')
    post '/grape_ape', {}
  end

  def test_updating_a_grape_ape
    NewRelic::Agent.expects(:set_transaction_name).with('TestApi/grape_ape/:id (PUT)')
    put '/grape_ape/1', {}
  end

  def test_deleting_a_grape_ape
    NewRelic::Agent.expects(:set_transaction_name).with('TestApi/grape_ape/:id (DELETE)')
    delete '/grape_ape/1'
  end
end
