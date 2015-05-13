# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'newrelic_rpm'
require 'fake_instance_metadata_service'

class UtilizationDataCollectionTest < Minitest::Test
  include MultiverseHelpers

  setup_and_teardown_agent do
    $collector.stub('connect',
      {
        "agent_run_id" => 42
      }
    )
  end

  def with_fake_metadata_service
    metadata_service = NewRelic::FakeInstanceMetadataService.new
    metadata_service.run

    redirect_link_local_address(metadata_service.port)

    yield metadata_service
  ensure
    metadata_service.stop if metadata_service
    unredirect_link_local_address
  end

  def redirect_link_local_address(port)
    Net::HTTP.class_exec(port) do |p|
      @dummy_port = p

      class << self
        def get_with_patch(uri)
          if uri.host == '169.254.169.254'
            uri.host = 'localhost'
            uri.port = @dummy_port
          end
          get_without_patch(uri)
        end

        alias_method :get_without_patch, :get
        alias_method :get, :get_with_patch
      end
    end
  end

  def unredirect_link_local_address
    Net::HTTP.class_eval do
      class << self
        alias_method :get, :get_without_patch
        undef_method :get_with_patch
      end
    end
  end
end
