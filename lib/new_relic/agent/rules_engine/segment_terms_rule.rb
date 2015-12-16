# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    class RulesEngine
      class SegmentTermsRule
        PREFIX_KEY                        = 'prefix'.freeze
        TERMS_KEY                         = 'terms'.freeze
        SEGMENT_PLACEHOLDER               = '*'.freeze
        ADJACENT_PLACEHOLDERS_REGEX       = %r{((?:^|/)\*)(?:/\*)*}.freeze
        ADJACENT_PLACEHOLDERS_REPLACEMENT = '\1'.freeze
        VALID_PREFIX_SEGMENT_COUNT        = 2

        attr_reader :prefix, :terms

        def initialize(options)
          if options[PREFIX_KEY].kind_of?(String) &&
             options[PREFIX_KEY].split(SEGMENT_SEPARATOR, VALID_PREFIX_SEGMENT_COUNT + 1).count == VALID_PREFIX_SEGMENT_COUNT
            @prefix          = options[PREFIX_KEY]
            @terms           = options[TERMS_KEY]
            @trim_range      = (@prefix.size..-1)
          end
        end

        def terminal?
          true
        end

        def matches?(string)
          return false unless valid?
          string.start_with?(@prefix)
        end

        def valid?
          @prefix && @terms
        end

        def apply(string)
          return string unless valid?

          rest          = string[@trim_range]
          leading_slash = rest.slice!(LEADING_SLASH_REGEX)
          segments = rest.split(SEGMENT_SEPARATOR, -1)
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
