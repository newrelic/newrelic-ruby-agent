# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/datastores/metric_helper'

class NewRelic::Agent::Datastores::MetricHelperTest < Minitest::Test
  def test_statement_metric_for
    product = "JonanDB"
    collection = "wiggles"
    operation = "select"

    expected = "Datastore/statement/JonanDB/wiggles/select"
    result = NewRelic::Agent::Datastores::MetricHelper.statement_metric_for(product, collection, operation)
    assert_equal expected, result
  end
end
