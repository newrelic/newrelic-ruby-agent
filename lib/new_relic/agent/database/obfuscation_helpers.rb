# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Database
      module ObfuscationHelpers
        NUMERICS = /\b\d+\b/
        SINGLE_QUOTES = /'(?:[^']|'')*'/
        DOUBLE_QUOTES = /"(?:[^"]|"")*"/

        def remove_escaped_quotes(sql)
          sql.gsub(/\\"/, '').gsub(/\\'/, '')
        end

        def obfuscate_single_quote_literals(sql)
          sql.gsub(SINGLE_QUOTES, '?')
        end

        def obfuscate_double_quote_literals(sql)
          sql.gsub(DOUBLE_QUOTES, '?')
        end

        def obfuscate_numeric_literals(sql)
          sql.gsub(NUMERICS, "?")
        end

        def find_literals(sql)
          literals = sql.scan(NUMERICS)
          literals << sql.scan(SINGLE_QUOTES)
          literals.flatten
        end
      end
    end
  end
end
