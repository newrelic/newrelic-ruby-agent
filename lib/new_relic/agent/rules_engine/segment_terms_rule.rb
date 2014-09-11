# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class RulesEngine
      class SegmentTermsRule
        SEGMENT_PLACEHOLDER               = '*'.freeze
        ADJACENT_PLACEHOLDERS_REGEX       = %r{((?:^|/)\*)(?:/\*)*}.freeze
        ADJACENT_PLACEHOLDERS_REPLACEMENT = '\1'.freeze

        attr_reader :prefix, :terms

        def initialize(options)
          @prefix          = options['prefix']
          @terms           = options['terms']
          @trim_range      = (@prefix.size..-1)
        end

        def terminal?
          true
        end

        def matches?(string)
          string.start_with?(@prefix)
        end

        def apply(string)
          rest          = string[@trim_range]
          leading_slash = rest.slice!(LEADING_SLASH_REGEX)

          segments = rest.split(SEGMENT_SEPARATOR)
          segments.map! { |s| @terms.include?(s) ? s : SEGMENT_PLACEHOLDER }
          transformed_suffix = collapse_adjacent_placeholder_segments(segments)

          "#{@prefix}#{leading_slash}#{transformed_suffix}"
        end

        def collapse_adjacent_placeholder_segments(segments)
          joined = segments.join(SEGMENT_SEPARATOR)
          joined.gsub!(ADJACENT_PLACEHOLDERS_REGEX, ADJACENT_PLACEHOLDERS_REPLACEMENT)
          joined
        end
      end
    end
  end
end
