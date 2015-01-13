# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class Transaction
      class FrameStack
        extend Forwardable

        def_delegators :@frames, :empty?, :pop, :last, :size

        attr_reader :max_depth

        def initialize
          @frames = []
          @max_depth = 0
        end

        def push(item)
          @frames.push item
          @max_depth = @frames.size if @frames.size > @max_depth
        end
      end
    end
  end
end