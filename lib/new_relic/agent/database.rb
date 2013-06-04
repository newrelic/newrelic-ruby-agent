# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'singleton'

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
      extend self

      def obfuscate_sql(sql)
        Obfuscator.instance.obfuscator.call(sql)
      end

      def set_sql_obfuscator(type, &block)
        Obfuscator.instance.set_sql_obfuscator(type, &block)
      end

      def record_sql_method
        case Agent.config[:'transaction_tracer.record_sql'].to_s
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

      def get_connection(config, &connector)
        ConnectionManager.instance.get_connection(config, &connector)
      end

      def close_connections
        ConnectionManager.instance.close_connections
      end

      # Perform this in the runtime environment of a managed
      # application, to explain the sql statement executed within a
      # segment of a transaction sample. Returns an array of
      # explanations (which is an array rows consisting of an array of
      # strings for each column returned by the the explain query)
      # Note this happens only for statements whose execution time
      # exceeds a threshold (e.g. 500ms) and only within the slowest
      # transaction in a report period, selected for shipment to New
      # Relic
      def explain_sql(sql, connection_config, &explainer)
        return nil unless sql && connection_config
        statement = sql.split(";\n")[0] # only explain the first
        explain_plan = explain_statement(statement, connection_config, &explainer)
        return explain_plan || []
      end

      def explain_statement(statement, config, &explainer)
        return unless is_select?(statement)

        if statement[-3,3] == '...'
          NewRelic::Agent.logger.debug('Unable to collect explain plan for truncated query.')
          return
        end

        if parameterized?(statement)
          NewRelic::Agent.logger.debug('Unable to collect explain plan for parameterized query.')
          return
        end

        handle_exception_in_explain do
          start = Time.now
          plan = explainer.call(config, statement)
          ::NewRelic::Agent.record_metric("Supportability/Database/execute_explain_plan", Time.now - start)
          return process_resultset(plan) if plan
        end
      end

      def process_resultset(items)
        # The resultset type varies for different drivers.  Only thing you can count on is
        # that it implements each.  Also: can't use select_rows because the native postgres
        # driver doesn't know that method.

        headers = []
        values = []
        if items.respond_to?(:each_hash)
          items.each_hash do |row|
            headers = row.keys
            values << headers.map{|h| row[h] }
          end
        elsif items.respond_to?(:each)
          items.each do |row|
            if row.kind_of?(Hash)
              headers = row.keys
              values << headers.map{|h| row[h] }
            else
              values << row
            end
          end
        else
          values = [items]
        end

        headers = nil if headers.empty?
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

      def is_select?(statement)
        # split the string into at most two segments on the
        # system-defined field separator character
        first_word, rest_of_statement = statement.split($;, 2)
        (first_word.upcase == 'SELECT')
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

      class Obfuscator
        include Singleton

        attr_reader :obfuscator

        def initialize
          reset
        end

        def reset
          @obfuscator = method(:default_sql_obfuscator)
        end

        # Sets the sql obfuscator used to clean up sql when sending it
        # to the server. Possible types are:
        #
        # :before => sets the block to run before the existing
        # obfuscators
        #
        # :after => sets the block to run after the existing
        # obfuscator(s)
        #
        # :replace => removes the current obfuscator and replaces it
        # with the provided block
        def set_sql_obfuscator(type, &block)
          if type == :before
            @obfuscator = NewRelic::ChainedCall.new(block, @obfuscator)
          elsif type == :after
            @obfuscator = NewRelic::ChainedCall.new(@obfuscator, block)
          elsif type == :replace
            @obfuscator = block
          else
            fail "unknown sql_obfuscator type #{type}"
          end
        end

        def default_sql_obfuscator(sql)
          if sql[-3,3] == '...'
            return "Query too large (over 16k characters) to safely obfuscate"
          end

          stmt = sql.kind_of?(Statement) ? sql : Statement.new(sql)
          adapter = stmt.adapter
          obfuscated = remove_escaped_quotes(stmt)
          obfuscated = obfuscate_single_quote_literals(obfuscated)
          if !(adapter.to_s =~ /postgres/ || adapter.to_s =~ /sqlite/)
            obfuscated = obfuscate_double_quote_literals(obfuscated)
          end
          obfuscated = obfuscate_numeric_literals(obfuscated)
          obfuscated.to_s # return back to a regular String
        end

        def remove_escaped_quotes(sql)
          sql.gsub(/\\"/, '').gsub(/\\'/, '')
        end

        def obfuscate_single_quote_literals(sql)
          sql.gsub(/'(?:[^']|'')*'/, '?')
        end

        def obfuscate_double_quote_literals(sql)
          sql.gsub(/"(?:[^"]|"")*"/, '?')
        end

        def obfuscate_numeric_literals(sql)
          sql.gsub(/\b\d+\b/, "?")
        end
      end

      class Statement < String
        attr_accessor :adapter, :config, :explainer
      end
    end
  end
end
