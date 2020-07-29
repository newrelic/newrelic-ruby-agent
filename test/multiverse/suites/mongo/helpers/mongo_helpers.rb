# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module MongoHelpers
    def mongo_logger
      if ENV["VERBOSE"]
        Mongo::Logger.Logger
      else
        filename = File.join(`pwd`.chomp, 'log', 'mongo_test.log')
        Logger.new(filename)
      end
    end
  end
end