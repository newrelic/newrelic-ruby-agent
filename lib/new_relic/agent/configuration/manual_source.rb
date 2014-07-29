# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/configuration/dotted_hash'

module NewRelic
  module Agent
    module Configuration
      class ManualSource < DottedHash
        def initialize(hash)
          super(hash, true)
        end
      end
    end
  end
end
