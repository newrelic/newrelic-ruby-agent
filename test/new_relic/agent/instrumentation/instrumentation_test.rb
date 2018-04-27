# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'test_helper'))
class NewRelic::Agent::Instrumentation::InstrumentationTest < Minitest::Test
  def test_load_all_instrumentation_files
    # just checking for syntax errors and unguarded code
    Dir.glob('new_relic/agent/instrumentation/**/*.rb') do |f|
      require f
    end
    require 'new_relic/delayed_job_injection'
  end
end
