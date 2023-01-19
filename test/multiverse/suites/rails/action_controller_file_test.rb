# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require './app'

if defined?(ActionController::Live)

  class DataController < ApplicationController
    # send_file
    def send_test_file
      send_file(Rails.root + "../../../../README.md")
    end

    # send_data
    def send_test_data
      send_data("wow its a adata")
    end

    # halted_callback
    before_action :halter, only: :halt_my_callback

    def halt_my_callback
    end

    def halter
      redirect_to("http://foo.bar/")
    end
  end

  class ActionControllerDataTest < ActionDispatch::IntegrationTest
    include MultiverseHelpers

    def teardown
      NewRelic::Agent.drop_buffered_data
    end

    def test_send_file
      get('/data/send_test_file')

      assert_metrics_recorded(['Controller/data/send_test_file', 'Controller/send_file'])
    end

    def test_send_data
      get('/data/send_test_data')

      assert_metrics_recorded(['Controller/data/send_test_data', 'Controller/send_data'])
    end

    def test_halted_callback
      get('/data/halt_my_callback')

      assert_metrics_recorded(['Controller/data/halt_my_callback', 'Controller/halted_callback'])
    end

    # TODO: add ignore tests
    # def test_redirect_to
    #   get('/data/do_a_redirect')
    #   assert_metrics_recorded(['Controller/data/do_a_redirect', 'Nested/Controller/data/do_a_redirect/redirect_to', "wow_here"])
    # end

    # unpermitted_parameters
  end
end
