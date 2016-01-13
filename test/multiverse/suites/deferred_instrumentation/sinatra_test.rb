# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'
require 'sinatra'

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'sinatra', 'sinatra_test_cases'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'helpers', 'exceptions'))

class DeferredSinatraTestApp < Sinatra::Base
  include NewRelic::Agent::Instrumentation::Rack
  include NewRelic::TestHelpers::Exceptions

  configure do
    # display exceptions so we see what's going on
    disable :show_exceptions

    # create a condition (sintra's version of a before_filter) that returns the
    # value that was passed into it.
    set :my_condition do |boolean|
      condition do
        halt 404 unless boolean
      end
    end
  end

  get '/' do
    "root path"
  end

  get '/user/login' do
    "please log in"
  end

  # this action will always return 404 because of the condition.
  get '/user/:id', :my_condition => false do |id|
    "Welcome #{id}"
  end

  get '/raise' do
    raise "Uh-oh"
  end

  # check that pass works properly
  condition { pass { halt 418, "I'm a teapot." } }
  get('/pass') { }

  get '/pass' do
    "I'm not a teapot."
  end

  error(NewRelic::TestHelpers::Exceptions::TestError) { halt 200, 'nothing happened' }
  condition { raise NewRelic::TestHelpers::Exceptions::TestError }
  get('/error') { }

  condition do
    raise "Boo" if $precondition_already_checked
    $precondition_already_checked = true
  end
  get('/precondition') { 'precondition only happened once' }

  get '/route/:name' do |name|
    # usually this would be a db test or something
    pass if name != 'match'
    'first route'
  end

  get '/route/no_match' do
    'second route'
  end

  before '/filtered' do
    @filtered = true
  end

  get '/filtered' do
    @filtered ? 'got filtered' : 'nope'
  end

  get(/\/regex.*/) do
    "Yeah, regex's!"
  end

  post '/files' do
    "file uploaded"
  end
end

class DeferredSinatraTest < Minitest::Test
  include SinatraTestCases

  def app
    Rack::Builder.new( DeferredSinatraTestApp ).to_app
  end


  def test_ignores_route_metrics
    # Can't use 'newrelic_ignore' if newrelic was loaded before sinatra, as the
    # instrumentation doesn't load until Rack is building the app to run it.
  end


  # (RUBY-1169)
  def test_only_tries_deferred_detection_once
    Rack::Builder.new( DeferredSinatraTestApp ).to_app
    ::DependencyDetection.expects( :detect! ).never
    Rack::Builder.new( DeferredSinatraTestApp ).to_app
  end

end
