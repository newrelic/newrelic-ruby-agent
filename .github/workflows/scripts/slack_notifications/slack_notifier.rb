# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'httparty'

class SlackNotifier
  CYCLE = 24 * 60 * 60 # Period in seconds to check for updates that need to be Slacked.
  @@errors = []

  def self.send_slack_message(message)
    path = ENV['SLACK_GEM_NOTIFICATIONS_WEBHOOK']
    options = {headers: {'Content-Type' => 'application/json'},
               body: {text: message}.to_json}
    begin
      HTTParty.post(path, options)
      puts "Gabbi DEBUG : path = >>#{path}<<, options = >>#{options}<<"
      sleep(1) # Pause to avoid Slack throttling
    rescue StandardError => e
      @@errors << e
      puts "Gabbi DEBUG : errors = >>#{@@errors}<<"
    end
  end

  def self.report_errors
    return if @@errors.empty?
    raise @@errors.first if @@errors.length == 1
    raise @@errors.map(&:to_s).join("\n")
  end

  def self.errors_array
    @@errors
  end
end
