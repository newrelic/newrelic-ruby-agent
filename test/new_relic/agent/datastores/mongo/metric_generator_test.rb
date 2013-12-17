# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))
require 'new_relic/agent/datastores/mongo/metric_generator'

class NewRelic::Agent::Datastores::Mongo::MetricGeneratorTest < Test::Unit::TestCase
  include ::NewRelic::TestHelpers::MongoMetricBuilder

  def setup
    @payload = { :collection => 'tribbles' }
  end

  def test_generate_metrics_for_includes_all_web_for_web_requests
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(:insert, @payload)

    assert_includes metrics, 'Datastore/allWeb'
  end

  def test_generate_metrics_for_does_not_include_all_other_for_web_requests
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(true)
    metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(:insert, @payload)

    refute metrics.include? 'Datastore/allOther'
  end

  def test_generate_metrics_for_includes_all_other_for_other_requests
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
    metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(:insert, @payload)

    assert_includes metrics, 'Datastore/allOther'
  end

  def test_generate_metrics_for_does_not_include_all_web_for_other_requests
    NewRelic::Agent::Transaction.stubs(:recording_web_transaction?).returns(false)
    metrics = NewRelic::Agent::Datastores::Mongo::MetricGenerator.generate_metrics_for(:insert, @payload)

    refute metrics.include? 'Datastore/allWeb'
  end

end
