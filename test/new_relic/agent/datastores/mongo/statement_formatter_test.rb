# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','..','test_helper'))
require 'new_relic/agent/datastores/mongo/statement_formatter'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        class StatementFormatterTest < Test::Unit::TestCase
          DOC_STATEMENT = { :database   => "multiverse",
                            :collection =>"tribbles",
                            :operation  => :insert,
                            :documents  => [ { "name" => "soterios johnson",
                                               :_id   => "BSON::ObjectId()" } ] }.freeze


          SELECTOR_STATEMENT = { :database   => 'multiverse',
                                 :collection => 'tribbles',
                                 :selector   => { 'name'     => 'soterios johnson',
                                                  :operation => :find,
                                                  :_id       => "BSON::ObjectId('?')" } }.freeze

          def test_doesnt_modify_incoming_statement
            formatted = StatementFormatter.format(DOC_STATEMENT)
            assert_not_same DOC_STATEMENT, formatted
          end

          def test_statement_formatter_removes_documents
            formatted = StatementFormatter.format(DOC_STATEMENT)
            assert_not_includes(formatted.keys, :documents,
                                "Formatted statement should not include documents: #{formatted}")
          end

          def test_statement_formatter_obfuscates_selectors
            expected = { :database   => 'multiverse',
                         :collection => 'tribbles',
                         :selector   => { 'name'      => '?',
                                          :operation => :find,
                                          :_id       => '?' } }

            with_config(:'transaction_tracer.record_sql' => "obfuscated") do
              result = StatementFormatter.format(SELECTOR_STATEMENT)
              assert_equal expected, result
            end
          end

          def test_statement_formatter_raw_selectors
            with_config(:'transaction_tracer.record_sql' => "raw") do
              result = StatementFormatter.format(SELECTOR_STATEMENT)
              assert_equal SELECTOR_STATEMENT, result
            end
          end

          def test_statement_formatter_recording_off
            expected = { :database   => 'multiverse',
                         :collection => 'tribbles' }

            with_config(:'transaction_tracer.record_sql' => "off") do
              result = StatementFormatter.format(SELECTOR_STATEMENT)
              assert_equal expected, result
            end
          end
        end
      end
    end
  end
end
