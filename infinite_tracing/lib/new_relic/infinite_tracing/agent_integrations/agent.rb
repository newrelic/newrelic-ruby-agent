# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent
  module InfiniteTracing
    require 'pry'; binding.pry

    ::NewRelic::Agent::Agent.class_eval do
      def instance
        @instance ||= self.new.tap do |agent|
          require 'pry'; binding.pry
          agent.instance_variable_set :@infinite_tracer, Client.new 
        end
      end
    end

    module AgentIntegration

      def initialize *args
        super
        require 'pry'; binding.pry
        @infinite_tracer = Client.new
      end
    end
  
    ::NewRelic::Agent::Agent.extend AgentIntegration
  end
end

DependencyDetection.defer do
  @name = :infinite_tracing

  depends_on do
    defined?(NewRelic::Agent::Agent)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Infinite Tracing'
  end

  executes do
    NewRelic::Agent::Agent::ClassMethods.class_eval do
      def initialize *args
        super
        @infinite_tracer = ::NewRelic::Agent::InfiniteTracing::Client.new
      end
    end
  end
end