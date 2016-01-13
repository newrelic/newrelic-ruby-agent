# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), 'nullverse_helper'))

# this test exists to ensure that default source doesn't depend on specific parts
# of the agent having been previously required when default_source is required.

class DefaultSourceRequireTest < Minitest::Test
  def test_require_default_source_doesnt_raise
    exception = nil
    begin
      require 'new_relic/agent/configuration/default_source'
    rescue => e
      exception = e
    end

    assert_nil exception, "Expected not to raise when requiring default source without the agent"
  end
end
