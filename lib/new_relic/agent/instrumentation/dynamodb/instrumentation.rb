# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic::Agent::Instrumentation
  module Dynamodb

    def build_request_with_new_relic(*args)
      # add instrumentation content here
      table_name = args[1][:table_name]
      region = config.region
      access_key = config.credentials.access_key_id
      account_id = NewRelic::Agent::Aws.convert_access_key_to_account_id(access_key)
      binding.irb

      arn = "arn:aws:dynamodb:#{region}:#{account_id}:table/#{table_name}"

      yield
    end
  end
end
