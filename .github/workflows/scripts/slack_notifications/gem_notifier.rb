# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This file runs on a 24 hour cycle via gem_notifications.yml and sends Slack updates for new gem version releases.

require 'time'
require 'httparty'
require_relative 'slack_notifier'
require_relative '../../../../lib/new_relic/agent/configuration/default_source'

class GemNotifier < SlackNotifier
  GEM_NAME_MAPPING = {
    'active_support_broadcast_logger' => 'activesupport-broadcast_logger',
    'active_support_logger' => 'activesupport-logger',
    'async_http' => 'async-http',
    'aws_sdk_firehose' => 'aws-sdk-firehose',
    'aws_sdk_kinesis' => 'aws-sdk-kinesis',
    'aws_sdk_lambda' => 'aws-sdk-lambda',
    'ruby_kafka' => 'kafka',
    'aws_sqs' => 'aws-sdk-sqs',
    'concurrent_ruby' => 'concurrent-ruby',
    'grpc_client' => 'grpc',
    'memcache_client' => 'memcache-client',
    'net_http' => 'net-http',
    'ruby_openai' => 'ruby-openai'
  }

  NOT_A_GEM = ['grpc.host_denylist', 'puma_rack', 'puma_rack_urlmap', 'rack_urlmap', 'thread.tracing']

  def self.check_for_updates(watched_gems)
    return if verify_gem_list(watched_gems)

    watched_gems.each do |gem_name|
      gem_info = verify_gem(gem_name)
      versions = gem_versions(gem_info)
      send_slack_message(gem_message(gem_name, versions)) if gem_updated?(versions)
    end

    report_errors
  end

  private

  def self.instrumented_gems
    valid_gems = []
    NewRelic::Agent::Configuration::DEFAULTS.keys.each do |key|
      if key.start_with?('instrumentation.')
        gem_name = key.to_s.gsub('instrumentation.', '')
        gem_name = GEM_NAME_MAPPING[gem_name] if GEM_NAME_MAPPING.include?(gem_name)
        valid_gems << gem_name unless NOT_A_GEM.include?(gem_name)
      end
    end

    valid_gems
  end

  def self.verify_gem_list(watched_gems)
    abort("Nothing to see here! The 'watched_gems' array cannot be empty") if watched_gems.empty?
  end

  def self.verify_gem(gem_name)
    gem_info = HTTParty.get("https://rubygems.org/api/v1/versions/#{gem_name}.json")
    abort("Failed to obtain info for gem '#{gem_name}'.") unless gem_info.success?

    gem_info
  end

  # Gem entries are ordered by release date. The break limits versions to two versions: newest and previous.
  def self.gem_versions(gem_info)
    versions = gem_info.each_with_object([]) do |gem, arr|
      next unless gem['platform'] == 'ruby'

      # for the "new" version (first one recorded), report any and all types of
      #   versions (stable, preview, rc, beta, etc.)
      # for the "previous" version, record only the newest stable version
      if arr.length.zero? || !gem['number'].match?(/(?:rc|beta|preview)/)
        arr << gem
      end

      break arr if arr.size == 2
    end
  end

  def self.gem_updated?(versions)
    Time.now.utc - Time.parse(versions[0]['created_at']) < CYCLE
  end

  def self.gem_source_code_uri(gem_name)
    info = HTTParty.get("https://rubygems.org/api/v1/gems/#{gem_name}.json")
    raise "Response unsuccessful: #{info}" unless info.success?

    info["source_code_uri"]
  rescue StandardError => e
    abort("#{e.class}: #{e.message}")
  end

  def self.github_diff(gem_name, newest, previous)
    source_code_uri = gem_source_code_uri(gem_name)
    interpolated_url = interpolate_github_url(source_code_uri, newest, previous)

    interpolated_url if HTTParty.get(interpolated_url).success?
  end

  def self.interpolate_github_url(source_code_uri, newest, previous)
    "#{source_code_uri}/compare/v#{previous}...v#{newest}"
  end

  def self.interpolate_rubygems_url(gem_name)
    "https://rubygems.org/gems/#{gem_name}"
  end

  def self.gem_message(gem_name, versions)
    abort("Expected exactly 2 version numbers in the 'versions' array") unless versions.size == 2
    newest, previous = versions[0]['number'], versions[1]['number']
    alert_message = "A new gem version is out :sparkles: <#{interpolate_rubygems_url(gem_name)}|*#{gem_name}*>, #{previous} -> #{newest}"
    github_diff_exist = github_diff(gem_name, newest, previous)
    if github_diff_exist
      action_message = "<#{github_diff_exist}|See what's new.>"
    else
      action_message = "See what's new with gem-compare:\n`gem compare #{gem_name} #{previous} #{newest} --diff`"
    end

    alert_message + "\n\n" + action_message
  end
end

if $PROGRAM_NAME == __FILE__
  GemNotifier.check_for_updates(GemNotifier.instrumented_gems)
end
