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
    abort("Nothing to see here! The 'watched_gems' array cannot be empty")
  end
end

def verify_gem(gem_name)
  gem_info = HTTParty.get("https://rubygems.org/api/v1/versions/#{gem_name}.json")

  gem_info if gem_info.success?
end

# Gem entries are ordered by release date. The break limits versions to two versions: newest and previous.
def gem_versions(gem_info)
  versions = gem_info.each_with_object([]) do |gem, arr|
    next unless gem['platform'] == 'ruby'

    # for the "new" version (first one recorded), report any and all types of
    #   versions (stable, preview, rc, beta, etc.)
    # for the "previous" version, record only the newest stable version
    if arr.size == 0 || !gem['number'].match?(/(?:rc|beta|preview)/)
      arr << gem
    end

    break arr if arr.size == 2
  end
end

def gem_updated?(versions)
  Time.now.utc - Time.parse(versions[0]['created_at']) < 24 * 60 * 60
end

def github_diff(gem_name, newest, previous)
  diff = HTTParty.get(interpolate_github_url(gem_name, newest, previous))

  diff.success?
end

def send_bot(gem_name, versions)
  abort("Expected exactly 2 version numbers in the 'versions' array") unless versions.size == 2
  path = ENV['SLACK_GEM_NOTIFICATIONS_WEBHOOK']
  options = {headers: {'Content-Type' => 'application/json'},
             body: {
              text: bot_message(gem_name, versions)}.to_json}

  HTTParty.post(path, options)
end

def interpolate_github_url(gem_name, newest, previous)
  "https://github.com/#{gem_name}/#{gem_name}/compare/v#{previous}...v#{newest}"
end

def interpolate_rubygems_url(gem_name)
  "https://rubygems.org/gems/#{gem_name}"
end

def bot_message(gem_name, versions)
  newest, previous = versions[0]['number'], versions[1]['number']
  alert_message = "A new gem version is out :sparkles: <#{interpolate_rubygems_url(gem_name)}|*#{gem_name}*>, #{previous} -> #{newest}"
  if github_diff(gem_name, newest, previous)
    action_message = "<#{interpolate_github_url(gem_name, newest, previous)}|See what's new.>"
  else
    action_message = "See what's new with gem-compare:\n`gem compare #{gem_name} #{previous} #{newest} --diff`"
  end

  alert_message + "\n\n" + action_message
end
