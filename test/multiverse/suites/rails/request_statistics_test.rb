# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-1096

require './app'

class RequestStatsController < ApplicationController
  def stats_action
    sleep 0.01
    render :text => 'some stuff'
  end

  def cross_app_action
    NewRelic::Agent::TransactionState.tl_get.is_cross_app_caller = true
    render :text => 'some stuff'
  end

  def stats_action_with_custom_params
    ::NewRelic::Agent.add_custom_attributes('color' => 'blue', 1 => :bar, 'bad' => {})
    render :text => 'some stuff'
  end
end

class RequestStatsTest < RailsMultiverseTest
  extend Multiverse::Color

  include MultiverseHelpers
  setup_and_teardown_agent

  #
  # Tests
  #

  def test_doesnt_send_when_disabled
    with_config( :'analytics_events.enabled' => false ) do
      5.times { get '/request_stats/stats_action' }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      assert_equal 0, $collector.calls_for('analytic_event_data').length
    end
  end

  def test_request_times_should_be_reported_if_enabled
    with_config( :'analytics_events.enabled' => true ) do
      5.times { get '/request_stats/stats_action' }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').first

      refute_nil( post )
      assert_kind_of Array, post.events
      assert_kind_of Array, post.events.first

      assert_equal 3, post.events.first.length

      post.events.first.each do |event_chunk|
        assert_kind_of Hash, event_chunk
      end

      sample = post.events.first.first
      assert_equal 'Controller/request_stats/stats_action', sample['name']
      assert_encoding 'utf-8', sample['name']
      assert_equal 'Transaction', sample['type']
      assert_kind_of Float, sample['duration']
      assert_kind_of Float, sample['timestamp']

      assert_nil sample['nr.guid']
      assert_nil sample['nr.referringTransactionGuid']
    end
  end

  def test_request_should_include_guid_if_cross_app
    with_config( :'analytics_events.enabled' => true ) do
      5.times { get '/request_stats/cross_app_action' }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').first

      refute_nil( post )
      assert_kind_of Array, post.events
      assert_kind_of Array, post.events.first

      sample = post.events.first.first
      assert_kind_of Hash, sample

      assert_kind_of String, sample['nr.guid']
    end
  end

  def test_request_should_include_referring_guid_if_needed
    with_config(:'analytics_events.enabled' => true,
                :'cross_process_id' => 'boo',
                :'encoding_key' => "\0",
                :'trusted_account_ids' => [1]) do
      rack_env = {
        'HTTP_X_NEWRELIC_ID'          => Base64.encode64('1#234'),
        'HTTP_X_NEWRELIC_TRANSACTION' => Base64.encode64('["8badf00d",1]')
      }
      get '/request_stats/cross_app_action', {}, rack_env

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').first

      refute_nil( post )
      assert_kind_of Array, post.events
      assert_kind_of Array, post.events.first

      sample = post.events.first.first

      assert_kind_of Hash, sample
      assert_kind_of String, sample['nr.guid']
      assert_equal('8badf00d', sample['nr.referringTransactionGuid'])
    end
  end

  def test_custom_params_should_be_reported_with_events_and_coerced_to_safe_types
    with_config( :'analytics_events.enabled' => true ) do
      5.times { get '/request_stats/stats_action_with_custom_params' }

      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').first

      refute_nil( post )
      assert_kind_of Array, post.events
      assert_kind_of Array, post.events.first

      sample = post.events.first[0]
      assert_kind_of Hash, sample

      assert_equal 'Controller/request_stats/stats_action_with_custom_params', sample['name']
      assert_encoding 'utf-8', sample['name']
      assert_equal 'Transaction', sample['type']

      ['blue', 'bar', 'bad'].each do |key|
        assert_not_includes(sample, key)
      end

      custom_params = post.events.first[1]

      assert_equal 'blue', custom_params['color']
      assert_equal 'bar', custom_params['1']
      assert_equal '{}', custom_params['bad']
    end
  end

  def test_request_samples_should_be_preserved_upon_failure
    with_config(:'analytics_events.enabled' => true) do
      5.times { get '/request_stats/stats_action' }

      # fail once
      $collector.stub('analytic_event_data', {}, 503)
      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      # recover
      $collector.stub('analytic_event_data', {'return_value'=>nil}, 200)
      NewRelic::Agent.agent.send(:harvest_and_send_analytic_event_data)

      post = $collector.calls_for('analytic_event_data').last

      samples = post.events
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
