# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path '../../../../test_helper', __FILE__

class NewRelic::Agent::Instrumentation::InstrumentationTest < Minitest::Test

  Dir.glob('lib/new_relic/agent/instrumentation/**/*.rb') do |filename| 
    sub_folder = File.dirname(filename).split("/")[-1]
    base_name = File.basename(filename).split(".")[0]

    # checking for syntax errors and unguarded code
    define_method("test_load_#{sub_folder}_#{base_name}") do
      refute_raises LoadError do
        require File.expand_path(filename)
      end
    end
  end

  def test_load_instrumentation_delayed_job_injection
    refute_raises LoadError do
      require 'new_relic/delayed_job_injection'
    end
  end
end
