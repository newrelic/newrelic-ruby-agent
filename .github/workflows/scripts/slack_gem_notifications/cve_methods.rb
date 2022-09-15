# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'time'
require 'feedjira'
require 'httparty'

def check_for_cves
  ruby_sec_feed = 'https://rubysec.com/atom.xml'
  feed = Feedjira.parse(HTTParty.get(ruby_sec_feed).body)
  time = Time.now.utc
  cycle = 24 * 60 * 60
  feed.entries.each do |entry|
    break if time - entry.updated > cycle

    cve_send_bot(entry.title, entry.entry_id)
  end
end

def cve_bot_text(title, url)
  {text: ":rotating_light: #{title}\n<#{url}|More info here>"}.to_json
end

def cve_send_bot(title, url)
  options = {headers: {'Content-Type' => 'application/json'},
             body: cve_bot_text(title, url)}

  # Sleep guards against Slack rate limit
  sleep(rand(5))
  HTTParty.post(ENV['SLACK_GEM_NOTIFICATIONS_WEBHOOK'], options)
end
