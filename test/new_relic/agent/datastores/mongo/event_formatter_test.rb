# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../test_helper'
require 'new_relic/agent/datastores/mongo/event_formatter'

module NewRelic
  module Agent
    module Datastores
      module Mongo
        class EventFormatterTest < Minitest::Test
          DATABASE = 'multiverse'.freeze

          FIND_COMMAND = {
            "find" => "tribbles",
            "filter" => {"_id" => {"$gt" => 1}, "name" => "joe"},
            "sort" => {"_id" => 1},
            "limit" => 2,
            "skip" => 2,
            "comment" => "test",
            "hint" => {"_id" => 1},
            "max" => {"_id" => 6},
            "maxScan" => 5000,
            "maxTimeMS" => 6000,
            "min" => {"_id" => 0},
            "readPreference" => {"mode" => "secondaryPreferred"},
            "returnKey" => false,
            "showRecordId" => false,
            "snapshot" => false
          }.freeze

          INSERT_COMMAND = {
            "insert" => "tribbles",
            "ordered" => true,
            "documents" => [{:name => "test"}]
          }.freeze

          UPDATE_COMMAND = {
            "update" => "tribbles",
            "ordered" => true,
            "updates" => [
              {
                :q => {:_id => {"$gt" => 1}},
                :u => {"$inc" => {:x => 1}},
                :multi => false,
                :upsert => false
              }
            ]
          }.freeze

          DELETE_COMMAND = {
            "delete" => "tribbles",
            "ordered" => true,
            "deletes" => [{:q => {:_id => {"$gt" => 1}}, :limit => 1}]
          }.freeze

          AGGREGATE_COMMAND = {
            "aggregate" => "tribbles",
            "pipeline" => [
              {"$group" => {"_id" => "name", "max" => {"$max" => "$count"}}},
              {"$match" => {"max" => {"$gte" => 1}}}
            ]
          }

          def test_doesnt_modify_incoming_statement
            formatted = EventFormatter.format('find', DATABASE, FIND_COMMAND)
            refute_same FIND_COMMAND, formatted
          end

          def test_can_disable_statement_capturing_queries
            with_config(:'mongo.capture_queries' => false) do
              formatted = EventFormatter.format('find', DATABASE, FIND_COMMAND)
              assert_nil formatted
            end
          end

          def test_event_formatter_obfuscates_by_default
            expected = {
              :operation => :find,
              :database => DATABASE,
              :collection => "tribbles",
              "find" => "tribbles",
              "filter" => {"_id" => {"$gt" => "?"}, "name" => "?"},
              "sort" => {"_id" => 1},
              "limit" => 2,
              "skip" => 2,
              "comment" => "test",
              "hint" => {"_id" => 1},
              "max" => {"_id" => 6},
              "maxScan" => 5000,
              "maxTimeMS" => 6000,
              "min" => {"_id" => 0},
              "readPreference" => {"mode" => "secondaryPreferred"},
              "returnKey" => false,
              "showRecordId" => false,
              "snapshot" => false
            }

            formatted = EventFormatter.format(:find, DATABASE, FIND_COMMAND)
            assert_equal expected, formatted
          end

          def test_event_formatter_raw_selectors
            with_config(:'mongo.obfuscate_queries' => false) do
              formatted = EventFormatter.format(:find, DATABASE, FIND_COMMAND)
              expected = FIND_COMMAND.merge(
                :operation => :find,
                :database => DATABASE,
                :collection => 'tribbles'
              )
              assert_equal expected, formatted
            end
          end

          def test_event_formatter_whitelists_inserts
            expected = {
              :operation => :insert,
              :database => DATABASE,
              :collection => "tribbles",
              "insert" => "tribbles",
              "ordered" => true
            }

            formatted = EventFormatter.format(:insert, DATABASE, INSERT_COMMAND)
            assert_equal expected, formatted
          end

          def test_event_formatter_whitelists_updates
            expected = {
              :operation => :update,
              :database => DATABASE,
              :collection => "tribbles",
              "update" => "tribbles",
              "ordered" => true
            }

            formatted = EventFormatter.format(:update, DATABASE, UPDATE_COMMAND)
            assert_equal expected, formatted
          end

          def test_event_formatter_obfuscates_pipeline
            expected = {
              :operation => :aggregate,
              :database => DATABASE,
              :collection => "tribbles",
              "aggregate" => "tribbles",
              "pipeline" => [
                {"$group" => {"_id" => "?", "max" => {"$max" => "?"}}},
                {"$match" => {"max" => {"$gte" => "?"}}}
              ]
            }

            formatted = EventFormatter.format(:aggregate, DATABASE, AGGREGATE_COMMAND)
            assert_equal expected, formatted
          end

          def test_event_formatter_whitelists_deletes
            expected = {
              :operation => :delete,
              :database => DATABASE,
              :collection => "tribbles",
              "delete" => "tribbles",
              "ordered" => true
            }

            formatted = EventFormatter.format(:delete, DATABASE, DELETE_COMMAND)
            assert_equal expected, formatted
          end
        end
      end
    end
  end
end
