# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  module Agent
    module Aws
      def self.create_arn(service, resource, region)
        return unless NewRelic::Agent.config[:'aws_account_id']

        "arn:aws:#{service}:#{region}:#{NewRelic::Agent.config[:'aws_account_id']}:#{resource}"
      rescue => e
        NewRelic::Agent.logger.warn("Failed to create ARN: #{e}")
      end
    end
  end
end
