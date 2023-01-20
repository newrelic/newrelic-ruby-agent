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
    before_action :do_a_redirect, only: :halt_my_callback
    def halt_my_callback; end

    # redirect_to
    def do_a_redirect
      redirect_to("http://foo.bar/")
    end

    # unpermitted_parameters
    def not_allowed
      params.permit(:only_this)
    end
  end

  class ActionControllerDataTest < ActionDispatch::IntegrationTest
    include MultiverseHelpers

    def teardown
      NewRelic::Agent.drop_buffered_data
    end

    def test_send_file
      get('/data/send_test_file')

      assert_metrics_recorded(['Controller/data/send_test_file', 'Ruby/ActionController/send_file'])
    end

    def test_send_data
      get('/data/send_test_data')

      assert_metrics_recorded(['Controller/data/send_test_data', 'Ruby/ActionController/send_data'])
    end

    def test_halted_callback
      get('/data/halt_my_callback')

      trace = last_transaction_trace
      tt_node = find_node_with_name(trace, 'Ruby/ActionController/halted_callback')

      assert_equal(:do_a_redirect, tt_node.params[:filter])
      assert_metrics_recorded(['Controller/data/halt_my_callback', 'Ruby/ActionController/halted_callback'])
    end

    def test_redirect_to
      get('/data/do_a_redirect')

      trace = last_transaction_trace
      tt_node = find_node_with_name(trace, 'Ruby/ActionController/data/redirect_to')

      assert_equal('/data/do_a_redirect', tt_node.params[:original_path])
      assert_metrics_recorded(['Controller/data/do_a_redirect', 'Ruby/ActionController/data/redirect_to'])
    end

    def test_unpermitted_parameters
      get('/data/not_allowed', params: {this_is_a_param: 1})

      trace = last_transaction_trace
      tt_node = find_node_with_name(trace, 'Ruby/ActionController/data/unpermitted_parameters')

      assert_equal(['this_is_a_param'], tt_node.params[:keys])
      assert_equal('not_allowed', tt_node.params[:action])
      assert_equal('DataController', tt_node.params[:controller])
      assert_metrics_recorded(['Controller/data/not_allowed', 'Ruby/ActionController/data/unpermitted_parameters'])
    end
  end
end
