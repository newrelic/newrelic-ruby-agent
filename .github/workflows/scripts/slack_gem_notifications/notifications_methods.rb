# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'time'
require 'httparty'

def check_for_updates(watched_gems)
  return if gem_list_empty(watched_gems)
  watched_gems.each do |gem_name|
    verify_gem(gem_name) ? gem_info = verify_gem(gem_name) : return
    versions = gem_versions(gem_info)
    send_bot(gem_name, versions) if gem_updated?(versions)
  end
end

def gem_list_empty(watched_gems)
  if watched_gems.empty?
    abort "Nothing to see here! The 'watched_gems' array cannot be empty"
  end
end

def verify_gem(gem_name)
  gem_info = HTTParty.get("https://rubygems.org/api/v1/versions/#{gem_name}.json")

  gem_info if gem_info.success?
end

# Gem entries are ordered by release date. The break limits versions to two versions: newest and previous.
def gem_versions(gem_info)
  versions = gem_info.each_with_object([]) do |gem, arr|
    arr << gem if gem['platform'] == 'ruby'
    break arr if arr.size == 2
  end
end

def gem_updated?(versions)
  Time.now.utc - Time.parse(versions[0]['created_at']) < 24 * 60 * 60
end

def send_bot(gem_name, versions)
  abort "Expected exactly 2 version numbers in the 'versions' array" unless versions.size == 2
  newest, previous = versions[0]['number'], versions[1]['number']
  HTTParty.post(ENV['SLACK_GEM_NOTIFICATIONS_WEBHOOK'],
    headers: {'Content-Type' => 'application/json'},
    body: {text: "A new gem version is out! Gem: #{gem_name}, #{previous} -> #{newest}."}.to_json)
end
