# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-1096

require 'rails/test_help'
require './app'
require 'multiverse_helpers'
require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper')

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

  include MultiverseHelpers
  setup_and_teardown_agent

  #
  # Tests
  #

  def test_doesnt_send_when_disabled
    with_config( :'analytics_events.enabled' => false ) do
      20.times { get :stats_action }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      assert_equal 0, $collector.calls_for('analytic_event_data').length
    end
  end

  def test_request_times_should_be_reported_if_enabled
    with_config( :'analytics_events.enabled' => true ) do
      20.times { get :stats_action }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').first

      refute_nil( post )
      assert_kind_of Array, post.body
      assert_kind_of Array, post.body.first

      sample = post.body.first.first
      assert_kind_of Hash, sample

      assert_equal 'Controller/request_stats/stats_action', sample['name']
      assert_encoding 'utf-8', sample['name']
      assert_equal 'Transaction', sample['type']
      assert_kind_of Float, sample['duration']
      assert_kind_of Float, sample['timestamp']
    end
  end

  def test_request_samples_should_be_preserved_upon_failure
    with_config(:'analytics_events.enabled' => true) do
      5.times { get :stats_action }

      # fail once
      $collector.stub('analytic_event_data', {}, 503)
      assert_raises(NewRelic::Agent::ServerConnectionException) do
        NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)
      end

      # recover
      $collector.stub('analytic_event_data', {'return_value'=>nil}, 200)
      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').last

      samples = post.body
      assert_equal(5, samples.size)
      samples.each do |sample|
        # undo the extra layer of wrapping that the collector wants
        sample = sample.first
        assert_kind_of Hash, sample
        assert_kind_of Float, sample['duration']
        assert_kind_of Float, sample['timestamp']
      end
    end
  end


  #
  # Helpers
  #

  def assert_encoding( encname, string )
    return unless string.respond_to?( :encoding )
    expected_encoding = Encoding.find( encname ) or raise "no such encoding #{encname.dump}"
    msg = "Expected encoding of %p to be %p, but it was %p" %
      [ string, expected_encoding, string.encoding ]
    assert_equal( expected_encoding, string.encoding, msg )
  end

end
