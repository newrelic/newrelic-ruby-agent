# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Defining a test controller class with a superclass, used to
# verify correct attribute inheritence
class NewRelic::Agent::SuperclassController <  ActionController::Base
  def base_action
    render :text => 'none'
  end
end
# This is a controller class used in testing controller instrumentation
class NewRelic::Agent::AgentTestController < NewRelic::Agent::SuperclassController
  include NewRelic::TestHelpers::Exceptions
  # filter_parameter_logging :social_security_number

  @@headers_to_add = nil

  def index
    sleep params['wait'].to_f if params['wait']
    render :text => params.inspect
  end
  def _filter_parameters(params)
    filter_parameters params
  end
  def action_inline
    render(:inline => "<%= 'foo' %>fah")
  end

  def action_to_render
    render :text => params.inspect
  end
  def action_to_ignore
    render :text => 'unmeasured'
  end
  def action_to_ignore_apdex
    render :text => 'unmeasured'
  end
  before_filter :oops, :only => :action_with_before_filter_error
  def action_with_before_filter_error
    render :text => 'nothing'
  end
  def oops
    raise "error in before filter"
  end

  def rescue_action_locally(exception)
    if exception.is_a? TestException
      raise "error in the handler"
    end
  end
  def action_with_error
    raise "error in action"
  end
  def entry_action
    perform_action_with_newrelic_trace(:name => 'internal_action') do
      internal_action
    end
  end

  def self.set_some_headers(hash_of_headers)
    if ::Rails::VERSION::MAJOR.to_i == 4
      NewRelic::Agent.instance.events.notify(:before_call, hash_of_headers)
    else
      @@headers_to_add ||= {}
      @@headers_to_add.merge!(hash_of_headers)
    end
  end

  def self.clear_headers
    @@headers_to_add = nil
  end

  def newrelic_request_headers(_)
    @@headers_to_add ||= {}
  end

  private
  def internal_action
    perform_action_with_newrelic_trace(:name => 'internal_traced_action', :force => true) do
      render :text => 'internal action'
    end
  end
end
