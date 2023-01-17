# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require './app'

if defined?(ActionController::Live)

  class DataController < ApplicationController
    # RESPONSE_BODY = "<html><head></head><body>Brains!</body></html>"

    def send_test_file
      send_file('/Users/tmcclure/projects/ruby-agent/THIRD_PARTY_NOTICES.md')
    end

    def send_test_data
      send_data("wow its a adata")
    end

    def do_a_redirect
      # redirect_to action: "index"
      # redirect_to action: 'index', status: 303
    end

    before_action :otherthing, only: :halt_my_callback
    # before_action :set_newsletter_email, only: [:show, :edit]

    def otherthing
      puts "**1**"
      throw(:abort)
    end

    def halt_my_callback
      puts "**2**"
      # throw(:abort)
    end

    def index
      # puts "*"* 30

      NewRelic::Agent.record_metric("wow_here")
    end

    def secondthing
      # puts "*"*30
      # NewRelic::Agent.record_metric("wow_here")
    end
  end

  class ActionControllerDataTest < ActionDispatch::IntegrationTest
    include MultiverseHelpers

    def teardown
      NewRelic::Agent.drop_buffered_data
    end

    def test_send_file
      get('/data/send_test_file')

      assert_metrics_recorded(['Controller/data/send_test_file', 'Nested/Controller/data/send_test_file/send_file'])
    end

    def test_send_data
      get('/data/send_test_data')

      assert_metrics_recorded(['Controller/data/send_test_data', 'Nested/Controller/data/send_test_data/send_data'])
    end

    # TODO: add ignore tests

    # def test_redirect_to
    #   get('/data/do_a_redirect')

    #   assert_metrics_recorded(['Controller/data/do_a_redirect', 'Nested/Controller/data/do_a_redirect/redirect_to', "wow_here"])
    # end

    def test_halted_callback
      get('/data/halt_my_callback')

      assert_metrics_recorded(['Controller/data/halt_my_callback', 'Nested/Controller/data/halt_my_callback/halted_callback'])
    end
  end
end
