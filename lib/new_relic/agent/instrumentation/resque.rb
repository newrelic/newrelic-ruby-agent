# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require_relative 'resque/instrumentation'
require_relative 'resque/chain'
require_relative 'resque/prepend'

DependencyDetection.defer do
  @name = :resque

  depends_on do
    defined?(::Resque::Job) && !NewRelic::Agent.config[:disable_resque]
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Resque instrumentation'
  end

  executes do
    if NewRelic::Agent.config[:'resque.use_ruby_dns'] && NewRelic::Agent.config[:dispatcher] == :resque
      ::NewRelic::Agent.logger.info 'Requiring resolv-replace'
      require 'resolv'
      require 'resolv-replace'
    end
  end

  executes do
    if use_prepend?
      prepend_instrument ::Resque::Job, NewRelic::Agent::Instrumentation::Resque::Prepend
    else
      chain_instrument NewRelic::Agent::Instrumentation::Resque::Chain
    end

    if NewRelic::LanguageSupport.can_fork?
      ::Resque.before_first_fork do
        NewRelic::Agent.manual_start(:dispatcher   => :resque,
                                     :sync_startup => true,
                                     :start_channel_listener => true)
      end

      ::Resque.before_fork do |job|
        if ENV['FORK_PER_JOB'] != 'false'
          NewRelic::Agent.register_report_channel(job.object_id)
        end
      end

      ::Resque.after_fork do |job|
        # Only suppress reporting Instance/Busy for forked children
        # Traced errors UI relies on having the parent process report that metric
        NewRelic::Agent.after_fork(:report_to_channel => job.object_id,
                                   :report_instance_busy => false)
      end
    end
  end
end

# call this now so it is memoized before potentially forking worker processes
NewRelic::LanguageSupport.can_fork?
