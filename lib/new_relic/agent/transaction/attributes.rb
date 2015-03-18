# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Attributes

        attr_reader :custom, :agent, :intrinsic

        def initialize
          @custom = {}
          @agent = {}
          @intrinsic = {}
        end

        def add_custom(key, value)
          @custom[key] = value
        end

        def add_agent(key, value)
          @agent[key] = value
        end

        def add_intrinsic(key, value)
          @intrinsic[key] = value
        end
      end
    end
  end
end