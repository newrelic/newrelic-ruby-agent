# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/delayed_job_injection'

if !NewRelic::Agent::Samplers::DelayedJobSampler.supported_backend?
  class UnsupportedBackendTest < Minitest::Test
    include MultiverseHelpers

    setup_and_teardown_agent do
      NewRelic::DelayedJobInjection.worker_name = "delayed"
    end

    def test_unsupported_raises_on_instantiation
      assert_raises(NewRelic::Agent::Sampler::Unsupported) do
        NewRelic::Agent::Samplers::DelayedJobSampler.new
      end
    end
  end
end
