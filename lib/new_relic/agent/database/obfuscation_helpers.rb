# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic
  module Agent
    module Database
      module ObfuscationHelpers
        COMPONENTS_REGEX_MAP = {
          single_quotes: /'(?:[^']|'')*?(?:\\'.*|'(?!'))/,
          double_quotes: /"(?:[^"]|"")*?(?:\\".*|"(?!"))/,
          dollar_quotes: /(\$(?!\d)[^$]*?\$).*?(?:\1|$)/,
          uuids: /\{?(?:[0-9a-fA-F]-*){32}\}?/,
          numeric_literals: /-?\b(?:[0-9]+\.)?[0-9]+([eE][+-]?[0-9]+)?\b/,
          boolean_literals: /\b(?:true|false|null)\b/i,
          hexadecimal_literals: /0x[0-9a-fA-F]+/,
          comments: /(?:#|--).*?(?=\r|\n|$)/i,
          multi_line_comments: %r{/\*(?:[^/]|/[^*])*?(?:\*/|/\*.*)},
          oracle_quoted_strings: /q'\[.*?(?:\]'|$)|q'\{.*?(?:\}'|$)|q'<.*?(?:>'|$)|q'\(.*?(?:\)'|$)/
        }

        DIALECT_COMPONENTS = {
          fallback: COMPONENTS_REGEX_MAP.keys,
          mysql: %i[single_quotes double_quotes numeric_literals boolean_literals
                    hexadecimal_literals comments multi_line_comments],
          postgres: %i[single_quotes dollar_quotes uuids numeric_literals
                       boolean_literals comments multi_line_comments],
          sqlite: %i[single_quotes numeric_literals boolean_literals hexadecimal_literals
                     comments multi_line_comments],
          oracle: %i[single_quotes oracle_quoted_strings numeric_literals comments
                     multi_line_comments],
          cassandra: %i[single_quotes uuids numeric_literals boolean_literals
                        hexadecimal_literals comments multi_line_comments]
        }

        # We use these to check whether the query contains any quote characters
        # after obfuscation. If so, that's a good indication that the original
        # query was malformed, and so our obfuscation can't reliably find
        # literals. In such a case, we'll replace the entire query with a
        # placeholder.
        CLEANUP_REGEX = {
          mysql: %r{'|"|/\*|\*/},
          mysql2: %r{'|"|/\*|\*/},
          postgres: %r{'|/\*|\*/|\$(?!\?)},
          sqlite: %r{'|/\*|\*/},
          cassandra: %r{'|/\*|\*/},
          oracle: %r{'|/\*|\*/},
          oracle_enhanced: %r{'|/\*|\*/}
        }

        PLACEHOLDER = '?'.freeze
        FAILED_TO_OBFUSCATE_MESSAGE = 'Failed to obfuscate SQL query - quote characters remained after obfuscation'.freeze

        def obfuscate_single_quote_literals(sql)
          return sql unless sql =~ COMPONENTS_REGEX_MAP[:single_quotes]

          sql.gsub(COMPONENTS_REGEX_MAP[:single_quotes], PLACEHOLDER)
        end

        def self.generate_regex(dialect)
          components = DIALECT_COMPONENTS[dialect]
          Regexp.union(components.map { |component| COMPONENTS_REGEX_MAP[component] })
        end

        MYSQL_COMPONENTS_REGEX = generate_regex(:mysql)
        POSTGRES_COMPONENTS_REGEX = generate_regex(:postgres)
        SQLITE_COMPONENTS_REGEX = generate_regex(:sqlite)
        ORACLE_COMPONENTS_REGEX = generate_regex(:oracle)
        CASSANDRA_COMPONENTS_REGEX = generate_regex(:cassandra)
        FALLBACK_REGEX = generate_regex(:fallback)

        def obfuscate(sql, adapter)
          regex = case adapter
                  when :mysql, :mysql2
                    MYSQL_COMPONENTS_REGEX
                  when :postgres
                    POSTGRES_COMPONENTS_REGEX
                  when :sqlite
                    SQLITE_COMPONENTS_REGEX
                  when :oracle, :oracle_enhanced
                    ORACLE_COMPONENTS_REGEX
                  when :cassandra
                    CASSANDRA_COMPONENTS_REGEX
                  else
                    FALLBACK_REGEX
                  end
          obfuscated = sql.gsub(regex, PLACEHOLDER)
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
