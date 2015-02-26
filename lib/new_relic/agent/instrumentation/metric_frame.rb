# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/deprecator'

module NewRelic
  module Agent
    module Instrumentation
      # This is a legacy support shim now that the +MetricFrame+ functionality
      # has moved over to the +Transaction+ class instead.
      #
      # This class is deprecated and will be removed in a future agent version.
      #
      # @api public
      # @deprecated in favor of the +Transaction+ class
      #
      class MetricFrame

        # @deprecated
        def self.recording_web_transaction?
          NewRelic::Agent::Deprecator.deprecate(
            "NewRelic::Agent::Instrumentation::MetricFrame.recording_web_transaction?",
            "NewRelic::Agent::Transaction.recording_web_transaction?")

          Transaction.recording_web_transaction?
        end

        # @deprecated
        def self.abort_transaction!
          NewRelic::Agent::Deprecator.deprecate(
            "NewRelic::Agent::Instrumentation::MetricFrame.abort_transaction!",
            "NewRelic::Agent::Transaction.abort_transaction!")
          Transaction.abort_transaction!
        end
      end
    end
  end
end
