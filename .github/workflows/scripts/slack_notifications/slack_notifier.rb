# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'httparty'

class SlackNotifier
  def self.send_slack_message(message)
    path = ENV['SLACK_GEM_NOTIFICATIONS_WEBHOOK']
    options = {headers: {'Content-Type' => 'application/json'},
               body: {text: message}.to_json}

    # Pause to avoid slack throttling
    sleep(1)

    HTTParty.post(path, options)
  end
end
