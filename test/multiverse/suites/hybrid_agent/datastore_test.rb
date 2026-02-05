# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    class DatastoreTest < Minitest::Test
      class TestClass
        include NewRelic::Agent::OpenTelemetry::Segments::Datastore
      end

      def setup
        @test_instance = TestClass.new
      end

      def test_parse_operation_returns_db_operation_when_present
        attributes = {'db.operation' => 'SELECT'}
        result = @test_instance.parse_operation('some_name', attributes)

        assert_equal 'SELECT', result
      end

      def test_parse_operation_prefers_db_operation_over_name
        attributes = {'db.operation' => 'insert', 'db.statement' => 'SELECT * FROM users'}
        result = @test_instance.parse_operation('SELECT', attributes)

        assert_equal 'insert', result
      end

      def test_parse_operation_returns_downcased_name_for_select
        attributes = {}
        result = @test_instance.parse_operation('SELECT', attributes)

        assert_equal 'select', result
      end

      def test_parse_operation_returns_downcased_name_for_insert
        attributes = {}
        result = @test_instance.parse_operation('INSERT', attributes)

        assert_equal 'insert', result
      end

      def test_parse_operation_handles_mixed_case_known_operation
        attributes = {}
        result = @test_instance.parse_operation('CrEaTe', attributes)

        assert_equal 'create', result
      end

      def test_parse_operation_handles_already_lowercase_known_operation
        attributes = {}
        result = @test_instance.parse_operation('select', attributes)

        assert_equal 'select', result
      end

      def test_parse_operation_parses_from_db_statement_for_unknown_name
        attributes = {'db.statement' => 'SELECT * FROM users WHERE id = 1'}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_equal 'select', result
      end

      def test_parse_operation_parses_from_db_statement_when_name_has_more_than_operation
        attributes = {'db.statement' => 'SELECT * FROM users WHERE id = 1'}
        result = @test_instance.parse_operation('INSERT users', attributes)

        assert_equal 'select', result
      end

      def test_parse_operation_returns_nil_when_name_has_more_than_operation_and_missing_attributes
        attributes = {}
        result = @test_instance.parse_operation('INSERT users', attributes)

        assert_nil result
      end

      def test_parse_operation_parses_from_db_statement_returns_other_for_unknown_operation
        attributes = {'db.statement' => 'UNKNOWN_OPERATION FROM users'}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_equal 'other', result
      end

      def test_parse_operation_parses_from_db_statement_with_update
        attributes = {'db.statement' => 'UPDATE users SET name = ? WHERE id = ?'}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_equal 'update', result
      end

      def test_parse_operation_parses_from_db_statement_with_delete
        attributes = {'db.statement' => 'DELETE FROM users WHERE id = ?'}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_equal 'delete', result
      end

      def test_parse_operation_parses_from_db_statement_with_comments
        attributes = {'db.statement' => '/* comment */ SELECT * FROM users'}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_equal 'select', result
      end

      def test_parse_operation_parses_from_db_statement_with_multiline_comments
        attributes = {'db.statement' => "/* multi\nline\ncomment */ INSERT INTO users VALUES (?)"}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_equal 'insert', result
      end

      def test_parse_operation_returns_nil_when_db_statement_is_empty
        attributes = {'db.statement' => ''}
        result = @test_instance.parse_operation('unknown', attributes)

        assert_nil result
      end
    end
  end
end
