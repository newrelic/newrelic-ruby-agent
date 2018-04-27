# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_helper'

class ActiveRecordTest < Performance::TestCase

  NAME    = "Model Load"
  SQL     = "SELECT * FROM star"
  ADAPTER = "mysql2"

  def test_helper_by_name
    measure do
      NewRelic::Agent::Instrumentation::ActiveRecordHelper.product_operation_collection_for NAME, SQL, ADAPTER
    end
  end

  UNKNOWN_NAME = "Blah"

  def test_helper_by_sql
    measure do
      NewRelic::Agent::Instrumentation::ActiveRecordHelper.product_operation_collection_for UNKNOWN_NAME, SQL, ADAPTER
    end
  end
end
