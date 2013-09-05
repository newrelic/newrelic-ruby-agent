# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

# Mongrel is only supported on older versions, so don't check for queue depth
if Rails::VERSION::MAJOR.to_i < 4

require 'rails/test_help'
require './app'
require 'multiverse_helpers'
require 'ostruct'

class MongrelController < ApplicationController
  include Rails.application.routes.url_helpers

  def deep
    respond_to do |format|
      format.html { render :text => "<html><head></head><body>Deep</body></html>" }
    end
  end
end

class MongrelQueueDepthTest < ActionDispatch::IntegrationTest

  include MultiverseHelpers

  setup_and_teardown_agent(:beacon => "beacon", :browser_key => "key")

  def test_mongrel_queue
    mongrel = OpenStruct.new(:workers => OpenStruct.new(:list => OpenStruct.new(:length => "10")))
    NewRelic::Control.instance.local_env.mongrel = mongrel

    get('/mongrel/deep')

    assert_metrics_recorded(['HttpDispatcher'])
    assert_metrics_recorded('Mongrel/Queue Length' => {:call_count => 1, :total_call_time => 9.0})
    assert_metrics_not_recorded(['WebFrontend/Mongrel/Average Queue Time'])
  end

end

end
