# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class Attributes

        attr_reader :custom, :agent, :intrinsic

        def initialize(filter)
          @filter = filter
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

        def custom_for_destination(destination)
          filter_attrs_by_destination(custom, destination)
        end

        def agent_for_destination(destination)
          filter_attrs_by_destination(agent, destination)
        end

        def intrinsic_for_destination(destination)
          filter_attrs_by_destination(intrinsic, destination)
        end

        private

        def filter_attrs_by_destination(attrs, destination)
          attrs.inject({}) do |memo, (key, value)|
            memo[key] = value if @filter.apply(key, destination) == destination
            memo
          end
        end
      end
    end
  end
end