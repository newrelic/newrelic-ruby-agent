# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module FlakyProxy
  class RuleSet
    class Builder
      attr_reader :rules

      def initialize(ruleset, &blk)
        @ruleset = ruleset
        @rules = []
      end

      def match(criteria, sequence=nil, &blk)
        if blk
          @ruleset.rules << Rule.new(criteria, &blk)
        else
          @ruleset.rules << Rule.new(criteria, sequence.builder)
        end
      end

      def sequence(&blk)
        Sequence.new(&blk)
      end
    end

    def self.build(text=nil, &blk)
      ruleset = self.new
      Builder.new(ruleset).instance_eval(text, &blk)
      ruleset
    end

    attr_accessor :rules

    def initialize
      @rules = []
      @default_rule = Rule.new { pass }
    end

    def match(request)
      @rules.detect { |rule| rule.match?(request) } || @default_rule
    end
  end
end
