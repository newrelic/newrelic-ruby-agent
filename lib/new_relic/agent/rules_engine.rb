module NewRelic
  module Agent
    class RulesEngine
      attr_accessor :rules

      def initialize
        @rules = []
      end

      def rename(original_string)
        @rules.sort.inject(original_string) do |string,rule|
          if rule.each_segment
            result, matched = rule.map_to_list(string.split('/'))
            result = result.join('/')
          else
            result, matched = rule.apply(string)
          end

          break result if matched && rule.terminate_chain
          result
        end
      end

      def <<(rule)
        @rules << rule
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

          @match_expression = Regexp.new(options['match_expression'])
          @replacement      = options['replacement']
          @ignore           = options['ignore'] || false
          @eval_order       = options['eval_order'] || 0
          @replace_all      = options['replace_all'] || false
          @each_segment     = options['each_segment'] || false
          @terminate_chain  = options['terminate_chain'] || false
        end

        def apply(string)
          matched = false
          result = if @replace_all
            string.gsub(@match_expression) do
              matched = true
              @replacement
            end
          else
            string.sub(@match_expression) do
              matched = true
              @replacement
            end
          end
          [result, matched]
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
