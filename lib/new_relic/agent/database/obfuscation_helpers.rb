# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Database
      module ObfuscationHelpers
        # Note that the following regex is applied to a reversed version
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
        REVERSE_SINGLE_QUOTES_REGEX = /'(?:''|'\\|[^'])*'/

        COMPONENTS_REGEX_MAP = {
          :single_quotes => /'(?:[^']|'')*?(?:\\'.*|'(?!'))/,
          :double_quotes => /"(?:[^"]|"")*?(?:\\".*|"(?!"))/,
          :dollar_quotes => /(\$(?!\d)[^$]*?\$).*?(?:\1|$)/,
          :comments => /(?:#|--).*?(?=\r|\n|$)/i,
          :multi_line_comments => /\/\*(?:[^\/]|\/[^*])*?(?:\*\/|\/\*.*)/i,
          :uuids => /\{?(?:[0-9a-f]\-*){32}\}?/i,
          :hexadecimal_literals => /0x[0-9a-f]+/i,
          :boolean_literals => /true|false|null/i,
          :numeric_literals => /\b-?(?:[0-9]+\.)?[0-9]+([eE][+-]?[0-9]+)?/,
          :oracle_quoted_strings => /q'\[.*?(?:\]'|$)|q'\{.*?(?:\}'|$)|q'\<.*?(?:\>'|$)|q'\(.*?(?:\)'|$)/
        }

        DIALECT_COMPONENTS = {
          :fallback   => COMPONENTS_REGEX_MAP.keys,
          :mysql      => [:single_quotes, :double_quotes, :comments, :multi_line_comments,
                          :hexadecimal_literals, :boolean_literals, :numeric_literals],
          :postgres   => [:single_quotes, :dollar_quotes, :comments, :multi_line_comments,
                          :uuids, :boolean_literals, :numeric_literals],
          :oracle     => [:single_quotes, :comments, :multi_line_comments, :numeric_literals,
                          :oracle_quoted_strings],
          :cassandra  => [:single_quotes, :comments, :multi_line_comments, :uuids,
                          :hexadecimal_literals, :boolean_literals, :numeric_literals]
        }

        # We use these to check whether the query contains any quote characters
        # after obfuscation. If so, that's a good indication that the original
        # query was malformed, and so our obfuscation can't reliably find
        # literals. In such a case, we'll replace the entire query with a
        # placeholder.
        CLEANUP_REGEX = {
          :mysql => /'|"|\/\*|\*\//,
          :postgres => /'|\/\*|\*\/|\$/,
          :cassandra => /'|\/\*|\*\//,
          :oracle => /'|\/\*|\*\//
        }

        PLACEHOLDER = '?'.freeze
        FAILED_TO_OBFUSCATE_MESSAGE = "Failed to obfuscate SQL query - quote characters remained after obfuscation".freeze

        def obfuscate_single_quote_literals(sql)
          obfuscated = sql.reverse
          obfuscated.gsub!(REVERSE_SINGLE_QUOTES_REGEX, PLACEHOLDER)
          obfuscated.reverse!
          obfuscated
        end

        def self.generate_regex(dialect)
          components = DIALECT_COMPONENTS[dialect]
          Regexp.union(components.map{|component| COMPONENTS_REGEX_MAP[component]})
        end

        MYSQL_COMPONENTS_REGEX = self.generate_regex(:mysql)
        POSTGRES_COMPONENTS_REGEX = self.generate_regex(:postgres)
        ORACLE_COMPONENTS_REGEX = self.generate_regex(:oracle)
        CASSANDRA_COMPONENTS_REGEX = self.generate_regex(:cassandra)
        FALLBACK_REGEX = self.generate_regex(:fallback)

        def obfuscate(sql, adapter)
          case adapter
          when :mysql
            regex = MYSQL_COMPONENTS_REGEX
          when :postgres
            regex = POSTGRES_COMPONENTS_REGEX
          when :oracle
            regex = ORACLE_COMPONENTS_REGEX
          when :cassandra
            regex = CASSANDRA_COMPONENTS_REGEX
          else
            regex = FALLBACK_REGEX
          end
          obfuscated = sql.gsub!(regex, PLACEHOLDER) || sql
          obfuscated = FAILED_TO_OBFUSCATE_MESSAGE if detect_unmatched_pairs(obfuscated, adapter)
          obfuscated
        end

        def detect_unmatched_pairs(obfuscated, adapter)
          if CLEANUP_REGEX[adapter]
            CLEANUP_REGEX[adapter].match(obfuscated)
          else
            CLEANUP_REGEX[:mysql].match(obfuscated)
          end
        end
      end
    end
  end
end
