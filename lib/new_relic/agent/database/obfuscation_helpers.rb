# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Database
      module ObfuscationHelpers
        NUMERICS = /\b\d+\b/

        # Note that the following two regexes are applied to a reversed version
        # of the query. This is why the backslash escape sequences (\' and \")
        # appear reversed within them.
        #
        # Note that some database adapters (notably, PostgreSQL with
        # standard_conforming_strings on and MySQL with NO_BACKSLASH_ESCAPES on)
        # do not apply special treatment to backslashes within quoted string
        # literals. We don't have an easy way of determining whether the
        # database connection from which a query was captured was operating in
        # one of these modes, but the obfuscation is done in such a way that it
        # should not matter.
        #
        # Reversing the query string before obfuscation allows us to get around
        # the fact that a \' appearing within a string may or may not terminate
        # the string, because we know that a string cannot *start* with a \'.
        REVERSE_SINGLE_QUOTES = /'(?:''|'\\|[^'])*'/
        REVERSE_ANY_QUOTES    = /'(?:''|'\\|[^'])*'|"(?:""|"\\|[^"])*"/

        PLACEHOLDER = '?'

        def obfuscate_single_quote_literals(sql)
          obfuscated = sql.reverse
          obfuscated.gsub!(REVERSE_SINGLE_QUOTES, PLACEHOLDER)
          obfuscated.reverse!
          obfuscated
        end

        def obfuscate_quoted_literals(sql)
          obfuscated = sql.reverse
          obfuscated.gsub!(REVERSE_ANY_QUOTES, PLACEHOLDER)
          obfuscated.reverse!
          obfuscated
        end

        def obfuscate_numeric_literals(sql)
          sql.gsub(NUMERICS, PLACEHOLDER)
        end

        def contains_single_quotes?(str)
          str.include?("'")
        end

        def contains_quotes?(str)
          str.include?('"') || str.include?("'")
        end
      end
    end
  end
end
