# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  Agent.class_eval do

    def new_infinite_tracer
      # We must start streaming in a thread or we block/deadlock the
      # entire start up process for the Agent.
      InfiniteTracing::Client.new.tap do |client| 
        Thread.new{ client.start_streaming }
      end
    end

    def infinite_tracer
      @infinite_tracer ||= new_infinite_tracer
    end
  end
end
