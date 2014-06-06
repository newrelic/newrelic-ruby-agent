# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..', 'test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

class NewRelic::Agent::StatsEngineTest < Minitest::Test
  def setup
    @engine = NewRelic::Agent::StatsEngine.new
  end

  def teardown
    @engine.reset!
    super
  end

  # Helpers for DataContainerTests

  def create_container
    NewRelic::Agent::StatsEngine.new
  end

  def populate_container(engine, n)
    n.times do |i|
      engine.tl_record_unscoped_metrics("metric#{i}", i)
    end
  end

  include NewRelic::DataContainerTests

end
