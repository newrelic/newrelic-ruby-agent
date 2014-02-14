# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module FlakyProxy
  class Sequence
    attr_reader :builder

    def initialize(&blk)
      @builder = Rule::ActionBuilder.new
      @builder.instance_eval(&blk)
    end
  end
end
