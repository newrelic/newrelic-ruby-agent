# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'time'
require 'feedjira'
require 'httparty'

def check_for_cves
  xml = HTTParty.get('https://rubysec.com/atom.xml').body
  feed = Feedjira.parse(xml)
  feed.entries.each do |entry|
    break if Time.now.utc - entry.updated > 24 * 60 * 60
    
    cve_send_bot(entry.title, entry.entry_id)
  end
end

def cve_bot_message(title, url)
  alert_message = ":rotating_light: #{title}\n<#{url}|More info here>"
end

def cve_send_bot(title, url)
  path = ENV['SLACK_GEM_NOTIFICATIONS_WEBHOOK']
  options = {headers: {'Content-Type' => 'application/json'},
             body: {
              text: cve_bot_message(title, url)}.to_json}

  HTTParty.post(path, options)
end
