# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Datastores
      module Redis
        def self.is_supported_version?
          ::NewRelic::VersionNumber.new(::Redis::VERSION) >= ::NewRelic::VersionNumber.new("3.0.0")
        end
      end
    end
  end
end
