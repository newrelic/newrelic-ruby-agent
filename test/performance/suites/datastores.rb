# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class DatastoresPerfTest < Performance::TestCase
  class FauxDB
    def self.query
      "foo"
    end
  end

  def test_instrumentation_via_trace
    db_class = Class.new do
      def query
        "foo"
      end
    end

    NewRelic::Agent::Datastores.trace(db_class, "query", "FakeDB")
    db = db_class.new

    measure do
      in_transaction do
        db.query
      end
    end
  end

  def test_wrap
    product = "FauxDB".freeze
    operation = "query".freeze
    collection = "collection".freeze

    measure do
      in_transaction do
        NewRelic::Agent::Datastores.wrap product, operation, collection do
          FauxDB.query
        end
      end
    end
  end
end
