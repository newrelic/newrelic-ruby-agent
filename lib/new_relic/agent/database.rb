# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'singleton'
require 'new_relic/agent/database/obfuscation_helpers'
require 'new_relic/agent/database/obfuscator'
require 'new_relic/agent/database/postgres_explain_obfuscator'

module NewRelic
  # columns for a mysql explain plan
  MYSQL_EXPLAIN_COLUMNS = [
                           "Id",
                           "Select Type",
                           "Table",
                           "Type",
                           "Possible Keys",
                           "Key",
                           "Key Length",
                           "Ref",
                           "Rows",
                           "Extra"
                          ].freeze

  module Agent
    module Database
      MAX_QUERY_LENGTH = 16384

      extend self

      def capture_query(query)
        Helper.correctly_encoded(truncate_query(query))
      end

      def truncate_query(query)
        if query.length > (MAX_QUERY_LENGTH - 4)
          query[0..MAX_QUERY_LENGTH - 4] + '...'
        else
          query
        end
      end

      def obfuscate_sql(sql)
        Obfuscator.instance.obfuscator.call(sql)
      end

      def set_sql_obfuscator(type, &block)
        Obfuscator.instance.set_sql_obfuscator(type, &block)
      end

      def record_sql_method(config_section=:transaction_tracer)
        key = record_sql_method_key(config_section)

        case Agent.config[key].to_s
        when 'off'
          :off
        when 'none'
          :off
        when 'false'
          :off
        when 'raw'
          :raw
        else
          :obfuscated
        end
      end

      def record_sql_method_key(config_section)
        case config_section
        when :transaction_tracer
          :'transaction_tracer.record_sql'
        when :slow_sql
          :'slow_sql.record_sql'
        else
          "#{config_section}.record_sql".to_sym
        end
      end

      RECORD_FOR = [:raw, :obfuscated].freeze

      def should_record_sql?(config_section=:transaction_tracer)
        RECORD_FOR.include?(record_sql_method(config_section))
      end

      def should_collect_explain_plans?(config_section=:transaction_tracer)
        should_record_sql?(config_section) &&
          Agent.config["#{config_section}.explain_enabled".to_sym]
      end

      def get_connection(config, &connector)
        ConnectionManager.instance.get_connection(config, &connector)
      end

      def close_connections
        ConnectionManager.instance.close_connections
      end

      # This takes a connection config hash from ActiveRecord or Sequel and
      # returns a string describing the associated database adapter
      def adapter_from_config(config)
        if config[:adapter]
          return config[:adapter].to_s
        elsif config[:uri] && config[:uri].to_s =~ /^jdbc:([^:]+):/
          # This case is for Sequel with the jdbc-mysql, jdbc-postgres, or
          # jdbc-sqlite3 gems.
          return $1
        end
      end

      # Perform this in the runtime environment of a managed
      # application, to explain the sql statement executed within a
      # node of a transaction sample. Returns an array of
      # explanations (which is an array rows consisting of an array of
      # strings for each column returned by the the explain query)
      # Note this happens only for statements whose execution time
      # exceeds a threshold (e.g. 500ms) and only within the slowest
      # transaction in a report period, selected for shipment to New
      # Relic
      def explain_sql(sql, connection_config, explainer=nil)
        return nil unless sql && explainer && connection_config
        statement = sql.split(";\n")[0] # only explain the first
        explain_plan = explain_statement(statement, connection_config, explainer)
        return explain_plan || []
      end

      SUPPORTED_ADAPTERS_FOR_EXPLAIN = %w[postgres postgresql mysql2 mysql sqlite].freeze

      def explain_statement(statement, config, explainer)
        return unless explainer && is_select?(statement)

        if statement[-3,3] == '...'
          NewRelic::Agent.logger.debug('Unable to collect explain plan for truncated query.')
          return
        end

        if parameterized?(statement)
          NewRelic::Agent.logger.debug('Unable to collect explain plan for parameterized query.')
          return
        end

        adapter = adapter_from_config(config)
        if !SUPPORTED_ADAPTERS_FOR_EXPLAIN.include?(adapter)
          NewRelic::Agent.logger.debug("Not collecting explain plan because an unknown connection adapter ('#{adapter}') was used.")
          return
        end

        handle_exception_in_explain do
          start = Time.now
          plan = explainer.call(config, statement)
          ::NewRelic::Agent.record_metric("Supportability/Database/execute_explain_plan", Time.now - start)
          return process_resultset(plan, adapter) if plan
        end
      end

      def process_resultset(results, adapter)
        case adapter.to_s
        when 'postgres', 'postgresql'
          process_explain_results_postgres(results)
        when 'mysql2'
          process_explain_results_mysql2(results)
        when 'mysql'
          process_explain_results_mysql(results)
        when 'sqlite'
          process_explain_results_sqlite(results)
        end
      end

      QUERY_PLAN = 'QUERY PLAN'.freeze

      def process_explain_results_postgres(results)
        if results.is_a?(String)
          query_plan_string = results
        else
          lines = []
          results.each { |row| lines << row[QUERY_PLAN] }
          query_plan_string = lines.join("\n")
        end

        unless record_sql_method == :raw
          query_plan_string = NewRelic::Agent::Database::PostgresExplainObfuscator.obfuscate(query_plan_string)
        end
        values = query_plan_string.split("\n").map { |line| [line] }

        [[QUERY_PLAN], values]
      end

      # Sequel returns explain plans as just one big pre-formatted String
      # In that case, we send a nil headers array, and the single string
      # wrapped in an array for the values.
      # Note that we don't use this method for Postgres explain plans, since
      # they need to be passed through the explain plan obfuscator first.
      def string_explain_plan_results(results)
        [nil, [results]]
      end

      def process_explain_results_mysql(results)
        return string_explain_plan_results(results) if results.is_a?(String)
        headers = []
        values  = []
        if results.is_a?(Array)
          # We're probably using the jdbc-mysql gem for JRuby, which will give
          # us an array of hashes.
          headers = results.first.keys
          results.each do |row|
            values << headers.map { |h| row[h] }
          end
        else
          # We're probably using the native mysql driver gem, which will give us
          # a Mysql::Result object that responds to each_hash
          results.each_hash do |row|
            headers = row.keys
            values << headers.map { |h| row[h] }
          end
        end
        [headers, values]
      end

      def process_explain_results_mysql2(results)
        return string_explain_plan_results(results) if results.is_a?(String)
        headers = results.fields
        values  = []
        results.each { |row| values << row }
        [headers, values]
      end

      SQLITE_EXPLAIN_COLUMNS = %w[addr opcode p1 p2 p3 p4 p5 comment]

      def process_explain_results_sqlite(results)
        return string_explain_plan_results(results) if results.is_a?(String)
        headers = SQLITE_EXPLAIN_COLUMNS
        values  = []
        results.each do |row|
          values << headers.map { |h| row[h] }
        end
        [headers, values]
      end

      def handle_exception_in_explain
        yield
      rescue => e
        begin
          # guarantees no throw from explain_sql
          ::NewRelic::Agent.logger.error("Error getting query plan:", e)
          nil
        rescue
          # double exception. throw up your hands
          nil
        end
      end

      KNOWN_OPERATIONS = [
        'alter',
        'select',
        'update',
        'delete',
        'insert',
        'create',
        'show',
        'set',
        'exec',
        'execute',
        'call'
      ]

      SQL_COMMENT_REGEX = Regexp.new('/\*.*?\*/', Regexp::MULTILINE).freeze
      EMPTY_STRING      = ''.freeze

      def parse_operation_from_query(sql)
        sql = sql.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') # avoid ArgumentError "invalid byte sequence in UTF-8" if the SQL expression contains invalid UTF-8 characters
        sql = sql.gsub(SQL_COMMENT_REGEX, EMPTY_STRING)
        if sql =~ /(\w+)/
          op = $1.downcase
          return op if KNOWN_OPERATIONS.include?(op)
        end
      end

      def is_select?(statement)
        parse_operation_from_query(statement) == 'select'
      end

      def parameterized?(statement)
        Obfuscator.instance.obfuscate_single_quote_literals(statement) =~ /\$\d+/
      end

      class ConnectionManager
        include Singleton

        # Returns a cached connection for a given ActiveRecord
        # configuration - these are stored or reopened as needed, and if
        # we cannot get one, we ignore it and move on without explaining
        # the sql
        def get_connection(config, &connector)
          @connections ||= {}

          connection = @connections[config]

          return connection if connection

          begin
            @connections[config] = connector.call(config)
          rescue => e
            ::NewRelic::Agent.logger.error("Caught exception trying to get connection to DB for explain.", e)
            nil
          end
        end

        # Closes all the connections in the internal connection cache
        def close_connections
          @connections ||= {}
          @connections.values.each do |connection|
            begin
              connection.disconnect!
            rescue
            end
          end

          @connections = {}
        end
      end

      class Statement
        attr_accessor :sql, :config, :explainer

        def initialize(sql, config={}, explainer=nil)
          @sql = Database.capture_query(sql)
          @config = config
          @explainer = explainer
        end

        def adapter
          config && config[:adapter]
        end
      end
    end
  end
end
