# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class RulesEngine
      include Enumerable
      extend Forwardable

      def_delegators :@rules, :size, :inspect, :each, :clear

      def self.from_specs(specs)
        rules = (specs || []).map { |spec| Rule.new(spec) }
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
          if rule.each_segment
            segments = string.split('/')

            # If string looks like '/foo/bar', we want to
            # ignore the empty string preceding the first slash.
            add_preceding_slash = false
            if segments[0] == ''
              segments.shift
              add_preceding_slash = true
            end

            result, matched = rule.map_to_list(segments)
            result = result.join('/') if !result.nil?
            result = '/'+result if add_preceding_slash
          else
            result, matched = rule.apply(string)
          end

          break result if (matched && rule.terminate_chain) || result.nil?
          result
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
          else
            method = @replace_all ? :gsub : :sub
            result = string.send(method, @match_expression, @replacement)
            match_found = ($~ != nil)
            [result, match_found]
          end
        end

        def map_to_list(list)
          matched = false
          result = list.map do |string|
            str_result, str_match = apply(string)
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
