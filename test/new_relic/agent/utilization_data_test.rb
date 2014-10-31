# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','test_helper'))
require File.expand_path(File.join(File.dirname(__FILE__),'..','data_container_tests'))

module NewRelic::Agent
  class UtilizationDataTest < Minitest::Test
    # We don't behave like a normal container, but we need to match the
    # interface at least!
    include NewRelic::BasicDataContainerMethodTests

    def create_container
      UtilizationData.new
    end
  end
end
