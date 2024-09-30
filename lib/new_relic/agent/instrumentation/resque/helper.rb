# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Instrumentation
      module Resque
        module Helper
          extend self

          def resque_fork_per_job?
            NewRelic::Agent.logger.debug('PAISLEY: resque_fork_per_job?')
            NewRelic::Agent.logger.debug("PAISLEY: ENV['FORK_PER_JOB'] value => #{ENV['FORK_PER_JOB']}")
            NewRelic::Agent.logger.debug("PAISLEY: NewRelic::LanguageSupport.can_fork? value => #{NewRelic::LanguageSupport.can_fork?}")
            ENV['FORK_PER_JOB'] != 'false' && NewRelic::LanguageSupport.can_fork?
          end
        end
      end
    end
  end
end
