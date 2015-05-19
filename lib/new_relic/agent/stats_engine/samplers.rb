# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
module Agent
  # This module exists only for backwards-compatibility reasons.
  # Sampler functionality is now controlled by the SamplerManager class.
  # @deprecated
  class StatsEngine
    module Samplers
      def add_sampler(*args)
        NewRelic::Agent.logger.warn("Ignoring request to add periodic sampler - add_sampler is deprecated")
      end

      def add_harvest_sampler
        NewRelic::Agent.logger.warn("Ignoring request to add harvest sampler - add_harvest_sampler is deprecated")
      end
    end
  end
end
end
