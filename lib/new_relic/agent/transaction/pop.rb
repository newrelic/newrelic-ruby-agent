# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/instrumentation'
module NewRelic
  module Agent
    class Transaction
      module Pop
        def log_underflow
          ::NewRelic::Agent.logger.error "Underflow in transaction: #{caller.join("\n   ")}"
        end

        def record_transaction_cpu
          burn = cpu_burn
          transaction_sampler.notice_transaction_cpu_time(burn) if burn
        end

        def normal_cpu_burn
          return unless @process_cpu_start
          process_cpu - @process_cpu_start
        end

        def jruby_cpu_burn
          return unless @jruby_cpu_start
          burn = (jruby_cpu_time - @jruby_cpu_start)
          # record_jruby_cpu_burn(burn)
          burn
        end

        # we need to do this here because the normal cpu sampler
        # process doesn't work on JRuby. See the cpu_sampler.rb file
        # to understand where cpu is recorded for non-jruby processes
        def record_jruby_cpu_burn(burn)
          NewRelic::Agent.record_metric(NewRelic::Metrics::USER_TIME, burn)
        end

        def cpu_burn
          normal_cpu_burn || jruby_cpu_burn
        end

        def traced?
          NewRelic::Agent.is_execution_traced?
        end

        def current_stack_metric
          metric_name
        end
      end
    end
  end
end
