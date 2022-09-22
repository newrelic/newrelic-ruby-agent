# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'time'
require 'feedjira'
require 'httparty'
require_relative 'slack_notifier'

class CveNotifier < SlackNotifier
  def self.check_for_cves
    ruby_sec_feed = 'https://rubysec.com/atom.xml'
    feed = Feedjira.parse(HTTParty.get(ruby_sec_feed).body)
    time = Time.now.utc
    cycle = 24 * 60 * 60
    feed.entries.each do |entry|
      break if time - entry.updated > cycle

      SlackNotifier.send_slack_message(cve_message(entry.title, entry.entry_id))
    end
  end

  def self.cve_message(title, url)
    {text: ":rotating_light: #{title}\n<#{url}|More info here>"}.to_json
  end
end

# This file runs on a 24 hour cycle via slack_notifications.yml and sends Slack updates for Ruby CVEs.
if $PROGRAM_NAME == __FILE__
  CveNotifier.check_for_cves
end
