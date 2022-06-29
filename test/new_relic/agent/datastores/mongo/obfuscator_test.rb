# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/datastores/mongo/obfuscator'
require_relative '../../../../test_helper'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        class ObfuscatorTest < Minitest::Test
          def test_obfuscator_removes_values_from_statement
            selector = {
              'name' => 'soterios johnson',
              :operation => :find,
              :_id => "BSON::ObjectId('?')"
            }

            expected = {
              'name' => '?',
              :operation => :find,
              :_id => '?'
            }

            obfuscated = Obfuscator.obfuscate_statement(selector)
            assert_equal expected, obfuscated
          end

          def test_obfuscate_selector_values_skips_allowed_keys
            selector = {
              :benign => 'bland data',
              :operation => :find,
              :_id => "BSON::ObjectId('?')"
            }

            expected = {
              :benign => 'bland data',
              :operation => :find,
              :_id => '?'
            }

            obfuscated = Obfuscator.obfuscate_statement(selector, [:benign, :operation])
            assert_equal expected, obfuscated
          end

          def test_obfuscate_nested_hashes
            selector = {
              "group" => {
                "ns" => "tribbles",
                "$reduce" => stub("BSON::Code"),
                "cond" => {},
                "initial" => {:count => 0},
                "key" => {"name" => 1}
              }
            }

            expected = {
              "group" => {
                "ns" => "?",
                "$reduce" => "?",
                "cond" => {},
                "initial" => {:count => "?"},
                "key" => {"name" => "?"}
              }
            }

            obfuscated = Obfuscator.obfuscate_statement(selector)
            assert_equal expected, obfuscated
          end

          def test_obfuscates_array_statement
            statement = [{"$group" => {:_id => "$says", :total => {"$sum" => 1}}}]
            expected = [{"$group" => {:_id => "?", :total => {"$sum" => "?"}}}]

            obfuscated = Obfuscator.obfuscate_statement(statement)
            assert_equal expected, obfuscated
          end

          def test_obfuscate_nested_arrays
            selector = {
              "aggregate" => "mongeese",
              "pipeline" => [{"$group" => {:_id => "$says", :total => {"$sum" => 1}}}]
            }

            expected = {
              "aggregate" => "?",
              "pipeline" => [{"$group" => {:_id => "?", :total => {"$sum" => "?"}}}]
            }

            obfuscated = Obfuscator.obfuscate_statement(selector)
            assert_equal expected, obfuscated
          end
        end
      end
    end
  end
end
