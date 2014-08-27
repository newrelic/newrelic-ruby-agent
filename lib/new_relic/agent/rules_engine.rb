# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class RulesEngine
      SEGMENT_SEPARATOR = '/'.freeze
      LEADING_SLASH_REGEX = %r{^/}.freeze

      include Enumerable
      extend Forwardable

      def_delegators :@rules, :size, :inspect, :each, :clear

      def self.from_specs(specs)
        rules = (specs || []).map { |spec| Rule.new(spec) }
        self.new(rules)
      end

      def self.from_application_segment_term_specs(specs)
        rules = (specs || []).map { |spec| ApplicationSegmentTermsRule.new(spec) }
        self.new(rules)
      end

      def initialize(rules=[])
        @rules = rules.sort
      end

      def << rule
        @rules << rule
        @rules.sort!
        @rules
      end

      def rename(original_string)
        @rules.inject(original_string) do |string,rule|
          result, matched = rule.apply(string)
          break result if (matched && rule.terminate_chain) || result.nil?
          result
        end
      end

      class ApplicationSegmentTermsRule
        SEGMENT_PLACEHOLDER = '*'.freeze

        attr_reader :prefix, :terms, :terminate_chain

        def initialize(options)
          @prefix          = options['prefix']
          @terms           = options['terms']
          @trim_range      = (@prefix.size..-1)
          @terminate_chain = false
        end

        def apply(string)
          return [string, false] unless string.start_with?(@prefix)

          rest          = string[@trim_range]
          leading_slash = rest.slice!(LEADING_SLASH_REGEX)

          segments = rest.split(SEGMENT_SEPARATOR)
          segments.map! { |s| @terms.include?(s) ? s : SEGMENT_PLACEHOLDER }
          segments = collapse_adjacent_placeholder_segments(segments)

          result = "#{@prefix}#{leading_slash}#{segments.join(SEGMENT_SEPARATOR)}"
          [result, true]
        end

        def collapse_adjacent_placeholder_segments(segments)
          segments.reduce([]) do |collapsed, segment|
            unless (segment == SEGMENT_PLACEHOLDER && collapsed.last == SEGMENT_PLACEHOLDER)
              collapsed << segment
            end
            collapsed
          end
        end

        def <=>(other)
          0
        end
      end

      class Rule
        attr_reader(:terminate_chain, :each_segment, :ignore, :replace_all, :eval_order,
                    :match_expression, :replacement)

        def initialize(options)
          if !options['match_expression']
            raise ArgumentError.new('missing required match_expression')
          end
          if !options['replacement'] && !options['ignore']
            raise ArgumentError.new('must specify replacement when ignore is false')
          end

          @match_expression = Regexp.new(options['match_expression'], Regexp::IGNORECASE)
          @replacement      = options['replacement']
          @ignore           = options['ignore'] || false
          @eval_order       = options['eval_order'] || 0
          @replace_all      = options['replace_all'] || false
          @each_segment     = options['each_segment'] || false
          @terminate_chain  = options['terminate_chain'] || false
        end

        def apply(string)
          if @ignore
            if string.match @match_expression
              [nil, true]
            else
              [string, false]
            end
          elsif @each_segment
            apply_to_each_segment(string)
          else
            apply_replacement(string)
          end
        end

        def apply_replacement(string)
          method = @replace_all ? :gsub : :sub
          result = string.send(method, @match_expression, @replacement)
          match_found = ($~ != nil)
          [result, match_found]
        end

        def apply_to_each_segment(string)
          string        = string.dup
          leading_slash = string.slice!(LEADING_SLASH_REGEX)
          segments      = string.split(SEGMENT_SEPARATOR)

          segments, matched = map_to_list(segments)
          result = "#{leading_slash}#{segments.join(SEGMENT_SEPARATOR)}" if segments

          [result, matched]
        end

        def map_to_list(list)
          matched = false
          result = list.map do |string|
            str_result, str_match = apply_replacement(string)
            matched ||= str_match
            str_result
          end
          [result, matched]
        end

        def <=>(other)
          eval_order <=> other.eval_order
        end
      end
    end
  end
end
