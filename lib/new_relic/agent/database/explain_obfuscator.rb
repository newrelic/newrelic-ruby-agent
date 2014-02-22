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

        # PostgreSQL supports a variety of different escape syntaxes in string
        # constants, described in detail in the manual here:
        # http://www.postgresql.org/docs/9.3/static/sql-syntax-lexical.html#SQL-SYNTAX-STRINGS-ESCAPE
        #
        # The value of the standard_conforming_strings setting controls where
        # escape sequences will be interpreted. In PostgreSQL 9.1 and later,
        # standard_conforming_strings defaults to on, meaning escape sequences
        # will only be interpreted within "escape" string constants (beginning
        # with "E'").
        #
        # It's worth noting that ActiveRecord does not appear to produce escape
        # string constants by default.
        #
        # Since our general approach is to find constants that were obfuscated
        # in the original query and then mask them out of the explain plan as
        # well, escape sequences can cause problems - they'll make the strings
        # that appear in the explain output different from the masked strings
        # from the original query (see the examples in
        # test/fixtures/cross_agent_tests/postgres_explain_obfuscation/with_escape_sequences
        # for some examples).
        #
        # For this reason, we attempt to identify queries containing escape
        # sequences, and just obfuscate away the entire explain plan when we
        # find them.
        #
        # The criteria for finding queries containing escape sequences is overly
        # loose, but the failure mode is for us to be too aggressive about
        # obfuscating the explain plan, which is better than accidentally
        # leaking sensitive data.
        #
        def contains_escape_sequences(query)
          query.match(/('.*\\|U&'.*UESCAPE)/)
        end

        # The general strategy here is to identify string and numeric constants
        # from the original query that we obfuscated, and then mask out
        # occurrences of those constants from the explain output as well.
        def obfuscate(query, explain)
          return '' if contains_escape_sequences(query)
          literals = find_literals(query)
          escaped_literals = literals.map { |literal| Regexp.escape(literal) }
          obfuscation_regex = Regexp.new(/(?:^|'|\b)(#{escaped_literals.join('|')})(?:'|\b|$)/)
          explain.gsub!(obfuscation_regex, '?')
          explain
        end
      end
    end
  end
end
