# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# The implementation of ::NewRelic::Agent.add_method_tracer requires
# an agent instance to exist.  If a customer loads a third-party
# library that calls add_method_tracer before they load the Ruby
# agent, we need to hang onto these pending calls until the agent is
# done starting.
#
module DeferredMethodTracing
  def self.extended(base)
    base.class_eval do
      @tracer_lock    = Mutex.new
      @tracer_queue   = []
      @agent_assigned = false
    end
  end

  def add_method_tracer(receiver, method_name, metric_name_code, options)
    @tracer_lock.synchronize do
      if @agent_assigned
        receiver.send(:_add_method_tracer_now, method_name, metric_name_code, options)
      else
        @tracer_queue << [receiver, method_name, metric_name_code, options]
      end
    end
  end

  # Called once an instance of the agent has been created and assigned
  # to the ::NewRelic::Agent.agent class-level attribute.  It is now
  # safe to drain the queue.
  #
  def after_assign
    @tracer_lock.synchronize do
      @agent_assigned = true

      @tracer_queue.each do |receiver, method_name, metric_name_code, options|
        receiver.send(:_add_method_tracer_now, method_name, metric_name_code, options)
      end

      @tracer_queue = []
    end
  end
end
