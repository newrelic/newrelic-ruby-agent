# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Rails4
        module Errors

          # @api public
          # @deprecated
          def newrelic_notice_error(exception, custom_params = {})
            NewRelic::Agent::Deprecator.deprecate("ActionController#newrelic_notice_error",
                                                  "NewRelic::Agent#notice_error")

            NewRelic::Agent::Transaction.notice_error(exception,
                                                      :custom_params => custom_params)
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :rails4_error

  depends_on do
    defined?(::Rails) && ::Rails::VERSION::MAJOR.to_i == 4
  end

  depends_on do
    defined?(ActionController) && defined?(ActionController::Base)
  end

  executes do
    ::NewRelic::Agent.logger.info 'Installing Rails 4 Error instrumentation'
  end

  executes do
    class ActionController::Base
      include NewRelic::Agent::Instrumentation::Rails4::Errors
    end
  end
end
