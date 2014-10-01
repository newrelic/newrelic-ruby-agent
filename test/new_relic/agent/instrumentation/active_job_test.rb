# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/instrumentation/active_job'

module NewRelic::Agent::Instrumentation
  class ActiveJobHelperTest < Minitest::Test
    def test_rails_formatted_adapters_get_shortened
      name = ActiveJobHelper.clean_adapter_name("ActiveJob::QueueAdapters::InlineAdapter")
      assert_equal "ActiveJob::Inline", name
    end

    def test_unexpected_name_format
      name = ActiveJobHelper.clean_adapter_name("Not::AnExpected::Adapter")
      assert_equal "Not::AnExpected::Adapter", name
    end
  end
end
