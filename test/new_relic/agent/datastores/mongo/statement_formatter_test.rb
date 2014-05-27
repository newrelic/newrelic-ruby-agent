# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))
require 'new_relic/agent/datastores/mongo/statement_formatter'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        class StatementFormatterTest < Minitest::Test
          DOC_STATEMENT = { :database   => "multiverse",
                            :collection => "tribbles",
                            :operation  => :insert,
                            :fields     => ["field_name"],
                            :skip       => 1,
                            :limit      => -1,
                            :order      => :ascending,

                            :ignored    => "we're whitelisted!",
                            :documents  => [ { "name" => "soterios johnson",
                                               :_id   => "BSON::ObjectId()" } ] }.freeze


          SELECTOR_STATEMENT = { :database   => 'multiverse',
                                 :collection => 'tribbles',
                                 :selector   => { 'name'     => 'soterios johnson',
                                                  :operation => :find,
                                                  :_id       => "BSON::ObjectId('?')" } }.freeze

          def test_doesnt_modify_incoming_statement
            formatted = StatementFormatter.format(DOC_STATEMENT, :find)
            refute_same DOC_STATEMENT, formatted
          end

          def test_statement_formatter_removes_unwhitelisted_keys
            formatted = StatementFormatter.format(DOC_STATEMENT, :find)
            assert_equal_unordered(formatted.keys, StatementFormatter::PLAINTEXT_KEYS)
          end

          def test_can_disable_statement_capturing_queries
            with_config(:'mongo.capture_queries' => false) do
              formatted = StatementFormatter.format(DOC_STATEMENT, :find)
              assert_nil formatted
            end
          end

          def test_statement_formatter_obfuscates_by_default
            expected = { :database   => 'multiverse',
                         :collection => 'tribbles',
                         :operation  => :find,
                         :selector   => { 'name'     => '?',
                                          :operation => :find,
                                          :_id       => '?' } }

            result = StatementFormatter.format(SELECTOR_STATEMENT, :find)
            assert_equal expected, result
          end

          def test_statement_formatter_raw_selectors
            with_config(:'mongo.obfuscate_queries' => false) do
              result = StatementFormatter.format(SELECTOR_STATEMENT, :find)
              assert_equal SELECTOR_STATEMENT.merge(:operation => :find), result
            end
          end

        end
      end
    end
  end
end
