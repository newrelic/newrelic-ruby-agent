# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This file runs on a 24 hour cycle via slack_notifications.yml and sends Slack updates for Ruby CVEs.

require 'time'
require 'feedjira'
require 'httparty'
require_relative 'slack_notifier'

class CveNotifier < SlackNotifier
  RUBY_SEC_FEED = 'https://rubysec.com/atom.xml'

  def self.check_for_cves
    time = Time.now.utc
    feed.entries.each do |entry|
      break if time - entry.updated > CYCLE

      send_slack_message(cve_message(entry.title, entry.entry_id))
    end
    report_errors
  end

  private

  def self.feed
    Feedjira.parse(HTTParty.get(RUBY_SEC_FEED).body)
  end

  def self.cve_message(title, url)
    ":rotating_light: #{title}\n<#{url}|More info here>"
  end
end

if $PROGRAM_NAME == __FILE__
  CveNotifier.check_for_cves
end
