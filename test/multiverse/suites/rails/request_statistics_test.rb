# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-927

require 'rails/test_help'
require './app'

class RequestStatsController < ApplicationController
  include Rails.application.routes.url_helpers

  def stats_action
    sleep 0.01
    render :text => 'some stuff'
  end
end

class RequestStatsTest < ActionController::TestCase
  tests RequestStatsController
  extend Multiverse::Color

  def setup
    $collector ||= NewRelic::FakeCollector.new
    $collector.reset
    setup_collector
    $collector.run

    NewRelic::Agent.reset_config
    NewRelic::Agent.instance_variable_set(:@agent, nil)
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)
    NewRelic::Agent.manual_start
    NewRelic::Agent::TransactionInfo.reset
  end

  def teardown
    NewRelic::Agent::Agent.instance.shutdown if NewRelic::Agent::Agent.instance
    NewRelic::Agent::Agent.instance_variable_set(:@instance, nil)
  end


  #
  # Tests
  #

  def test_is_disabled_by_default
    200.times { get :stats_action }

    NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

    assert_nil $collector.agent_data.find {|post| post.action == 'analytic_event_data' }
  end

  def test_request_times_should_be_reported_if_enabled
    with_config( :'request_sampler.enabled' => true ) do
      200.times { get :stats_action }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.agent_data.find {|post| post.action == 'analytic_event_data' }

      assert_not_nil( post )
      assert_kind_of Array, post.body
      assert_kind_of Array, post.body.first

      sample = post.body.first.first
      assert_kind_of Hash, sample

      assert_equal 'Controller/request_stats/stats_action', sample['name']
      assert_encoding 'utf-8', sample['name']
      assert_equal 'Transaction', sample['type']
      assert_kind_of Float, sample['duration']
      assert_valid_time sample['timestamp']
    end
  end



  #
  # Helpers
  #

  def setup_collector
    $collector.mock['connect'] = [200, {'return_value' => {"agent_run_id" => 666 }}]
  end

  def assert_encoding( encname, string )
    skip("no encoding support") unless string.respond_to?( :encoding )
    expected_encoding = Encoding.find( encname ) or raise "no such encoding #{encname.dump}"
    msg = "Expected encoding of %p to be %p, but it was %p" %
      [ string, expected_encoding, string.encoding ]
    assert_equal( expected_encoding, string.encoding, msg )
  end

  def assert_valid_time( object )
    return pass if object.is_a?( Time )
    assert_kind_of Time, Time.parse(object.to_s) rescue object
  end

end

