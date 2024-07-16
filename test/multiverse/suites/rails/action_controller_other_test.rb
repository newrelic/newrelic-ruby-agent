# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require './app'
if defined?(ActionController::Live)

  class DataController < ApplicationController
    CACHE_KEY = :the_key

    # send_file
    def send_test_file
      send_file(Rails.root + '../../../../README.md')
    end

    # send_data
    def send_test_data
      send_data('wow its a adata')
    end

    # send_stream
    def send_test_stream
      send_stream(filename: 'dinosaurs.html')
    end

    # halted_callback
    before_action :do_a_redirect, only: :halt_my_callback
    def halt_my_callback; end

    # redirect_to
    def do_a_redirect
      redirect_to('http://foo.bar/')
    end

    # unpermitted_parameters
    def not_allowed
      params.permit(:only_this)
    end

    # exist_fragment?
    def exist_fragment
      fragment_exist?(CACHE_KEY)
    end

    # expire_fragment
    def expire_test_fragment
      expire_fragment(CACHE_KEY)
    end

    # read_fragment
    def read_test_fragment
      read_fragment(CACHE_KEY)
    end

    # write_fragment
    def write_test_fragment
      write_fragment(CACHE_KEY, 'fragment')
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

    def test_send_stream
      skip unless rails_version_at_least?('7.2')
      get('/data/send_test_stream')

      assert_metrics_recorded(['Controller/data/send_test_stream', 'Ruby/ActionController/send_stream'])
    end

    def test_halted_callback
      get('/data/halt_my_callback')

      trace = last_transaction_trace
      tt_node = find_node_with_name(trace, 'Ruby/ActionController/halted_callback')

      # depending on the rails version, the value will be either
      # "do_a_redirect" OR :do_a_redirect OR ":do_a_redirect"
      assert_includes(tt_node.params[:filter].to_s, 'do_a_redirect')
      assert_metrics_recorded(['Controller/data/halt_my_callback', 'Ruby/ActionController/halted_callback'])
    end

    def test_redirect_to
      get('/data/do_a_redirect')

      # payload does not include the request in rails < 6.1
      rails61 = rails_version_at_least?('6.1')

      segment_name = if rails61
        'Ruby/ActionController/data/redirect_to'
      else
        'Ruby/ActionController/redirect_to'
      end

      trace = last_transaction_trace
      tt_node = find_node_with_name(trace, segment_name)

      assert_equal('/data/do_a_redirect', tt_node.params[:original_path]) if rails61

      assert_metrics_recorded(['Controller/data/do_a_redirect', segment_name])
    end

    def test_unpermitted_parameters
      # unpermitted parameters is only available in rails 6.0+
      skip unless rails_version_at_least?('6')

      get('/data/not_allowed', params: {this_is_a_param: 1})

      # in Rails < 7 the context key is not present in this payload, so it changes the params and name
      # because we're using context info to create the name
      rails7 = Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new('7.0.0')

      segment_name = if rails7
        'Ruby/ActionController/data/unpermitted_parameters'
      else
        'Ruby/ActionController/unpermitted_parameters'
      end

      trace = last_transaction_trace
      tt_node = find_node_with_name(trace, segment_name)

      assert_equal(['this_is_a_param'], tt_node.params[:keys])
      assert_equal('not_allowed', tt_node.params[:action]) if rails7
      assert_equal('DataController', tt_node.params[:controller]) if rails7

      assert_metrics_recorded(['Controller/data/not_allowed', segment_name])
    end

    def test_exist_fragment?
      skip unless rails_version_at_least?('6')

      get('/data/exist_fragment')

      node = find_node_with_name_matching(last_transaction_trace, /ActionController/)

      assert node, 'Could not find an >>ActionController<< metric while testing >>exist_fragment?<<'
      child_metric_partial_name = rails_version_at_least?('6.1') ? 'FileStore/exist' : 'ActiveSupport/exist?'
      child = node.children.detect { |n| n.metric_name.include?(child_metric_partial_name) }
      binding.irb unless child

      assert child, 'Could not find a >>Filestore/exist<< child of the ActionController node!'
      assert_includes child.params[:key], DataController::CACHE_KEY,
        "Expected to find the cache key >>#{DataController::CACHE_KEY}<< in the node params!"
    end

    def test_expire_fragment
      skip unless rails_version_at_least?('6')

      get('/data/expire_test_fragment')

      node = find_node_with_name_matching(last_transaction_trace, /ActionController/)

      assert node, 'Could not find an >>ActionController<< metric while testing >>expire_fragment<<'
      child_metric_partial_name = rails_version_at_least?('6.1') ? 'FileStore/delete' : 'ActiveSupport/delete'
      child = node.children.detect { |n| n.metric_name.include?(child_metric_partial_name) }
      binding.irb unless child

      assert child, 'Could not find a >>Filestore/delete<< child of the ActionController node!'
      assert_includes child.params[:key], DataController::CACHE_KEY,
        "Expected to find the cache key >>#{DataController::CACHE_KEY}<< in the node params!"
    end

    def test_read_fragment
      skip unless rails_version_at_least?('6')

      get('/data/read_test_fragment')

      node = find_node_with_name_matching(last_transaction_trace, /ActionController/)

      assert node, 'Could not find an >>ActionController<< metric while testing >>read_fragment<<'
      child_metric_partial_name = rails_version_at_least?('6.1') ? 'FileStore/read' : 'ActiveSupport/read'
      child = node.children.detect { |n| n.metric_name.include?(child_metric_partial_name) }
      binding.irb unless child

      assert child, 'Could not find a >>Filestore/read<< child of the ActionController node!'
      assert_includes child.params[:key], DataController::CACHE_KEY,
        "Expected to find the cache key >>#{DataController::CACHE_KEY}<< in the node params!"
    end

    def test_write_fragment
      skip unless rails_version_at_least?('6')

      get('/data/write_test_fragment')

      node = find_node_with_name_matching(last_transaction_trace, /ActionController/)

      assert node, 'Could not find an >>ActionController<< metric while testing >>write_fragment<<'
      child_metric_partial_name = rails_version_at_least?('6.1') ? 'FileStore/write' : 'ActiveSupport/write'
      child = node.children.detect { |n| n.metric_name.include?(child_metric_partial_name) }
      binding.irb unless child

      assert child, 'Could not find a >>Filestore/write<< child of the ActionController node!'
      assert_includes child.params[:key], DataController::CACHE_KEY,
        "Expected to find the cache key >>#{DataController::CACHE_KEY}<< in the node params!"
    end

    class TestClassActionController; end

    def test_no_metric_naming_error
      payloads = [
        {request: 'Not gonna respond to controller_class'},
        {request: Class.new do
          def controller_class
            'not gonna respond to controller_path'
          end
        end},
        {context: {}},
        {context: {controller: TestClassActionController.name}},
        {},
        nil
      ]

      payloads.each do |payload|
        # make sure no error is raised
        NewRelic::Agent::Instrumentation::ActionControllerOtherSubscriber.new.controller_name_for_metric(payload)
      end
    end

    private

    def rails_version
      @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
    end

    def rails_version_at_least?(version_string)
      rails_version >= Gem::Version.new(version_string)
    end
  end
end
