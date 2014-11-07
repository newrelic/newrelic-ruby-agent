# encoding: utf-8
# This file is distributed under New Relic"s license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require "grape"
require "newrelic_rpm"
require 'multiverse_helpers'

require File.join(File.dirname(__FILE__), "..", "..", "..", "agent_helper")

class TestAPI < Grape::API
  get :test do
    'Test!'
  end
end

class GrapeTest < Minitest::Test
  include Rack::Test::Methods
  include MultiverseHelpers

  def app
    TestAPI.new
  end

  def test_truthiness
    get '/test'
  end
end
