# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/database'
require 'new_relic/agent/database/obfuscation_helpers'

module NewRelic
  module Agent
    module Database
      module ExplainObfuscator
        extend self

        extend ObfuscationHelpers

        SINGLE_QUOTE_REGEX = /'([^']|'')*'/.freeze
        LABEL_LINE_REGEX   = /^([^:\n]*:\s+).*$/.freeze

        # The general strategy here is to identify string and numeric constants
        # from the original query that we obfuscated, and then mask out
        # occurrences of those constants from the explain output as well.
        def obfuscate(explain)
          explain = explain.gsub(SINGLE_QUOTE_REGEX, '?')
          explain = explain.gsub(LABEL_LINE_REGEX,   '\1?')
          explain
        end
      end
    end
  end
end
