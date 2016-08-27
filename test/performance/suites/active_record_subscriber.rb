# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation/active_record_subscriber'

# Note: This test was cobbled together from the AR Subscriber Unit Test and
# by cut & paste of ActiveSupport::Notifcations::Event from Rails source.
# This test is here because it's useful, not because it's well written.
# If you have a desire to improve this test, do it!

unless defined?(ActiveSupport::Notifications::Event)
  module ActiveSupport
    module Notifications
      class Event
        attr_reader :name, :time, :transaction_id, :payload, :children
        attr_accessor :end

        def initialize(name, start, ending, transaction_id, payload)
          @name           = name
          @payload        = payload.dup
          @time           = start
          @transaction_id = transaction_id
          @end            = ending
          @children       = []
          @duration       = nil
        end

        # Returns the difference in milliseconds between when the execution of the
        # event started and when it ended.
        #
        #   ActiveSupport::Notifications.subscribe('wait') do |*args|
        #     @event = ActiveSupport::Notifications::Event.new(*args)
        #   end
        #
        #   ActiveSupport::Notifications.instrument('wait') do
        #     sleep 1
        #   end
        #
        #   @event.duration # => 1000.138
        def duration
          @duration ||= 1000.0 * (self.end - time)
        end

        def <<(event)
          @children << event
        end

        def parent_of?(event)
          @children.include? event
        end
      end
    end
  end
end

class ActiveRecordSubscriberTest < Performance::TestCase
  def setup
    @config = { :adapter => 'mysql', :host => 'server' }
    @connection = Object.new
    @connection.instance_variable_set(:@config, @config)


    @params = {
      :name => 'NewRelic::Agent::Instrumentation::ActiveRecordSubscriberTest::Order Load',
      :sql => 'SELECT * FROM sandwiches',
      :connection_id => @connection.object_id
    }

    @subscriber = NewRelic::Agent::Instrumentation::ActiveRecordSubscriber.new
    if @subscriber.respond_to? :active_record_config_for_event
      @subscriber.class.send(:remove_method, :active_record_config_for_event)
      @subscriber.class.send(:define_method, :active_record_config_for_event) do |args|
        @config
      end
    else
      @subscriber.class.send(:remove_method, :active_record_config)
      @subscriber.class.send(:define_method, :active_record_config) do |args|
        @config
      end
    end
  end


  def test_subscriber_in_txn
    measure do
      in_transaction do
        simulate_query
      end
    end
  end

  EVENT_NAME = 'sql.active_record'.freeze

  def simulate_query(duration=nil)
    @subscriber.start(EVENT_NAME, :id, @params)
    advance_time(duration) if duration
    @subscriber.finish(EVENT_NAME, :id, @params)
  end
end
