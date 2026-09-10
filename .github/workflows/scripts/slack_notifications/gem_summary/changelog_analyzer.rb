# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'httparty'
require 'json'
require 'yaml'

module GemSummary
  class ChangelogAnalyzer
    MAX_LENGTH = 20_000 # Cap per-changelog length sent to Claude
    GEM_CHANGELOG = YAML.safe_load_file(File.expand_path('gem_changelogs.yml', __dir__)).freeze

    # Matches a version section header in a changelog. Three alternatives:
    VERSION_HEADER = %r{
      ^[#=]{1,2}.*\d+\.\d+       # markdown or rdoc header, e.g. "# 1.2.3", "== v1.2", "## Release 1.2.3"
      |
      ^v?\d+\.\d+                # setext-style version on its own line, e.g. "1.2.3", "v2.0" (followed by === underline)
      |
      ^\d{4}-\d{2}-\d{2}\s*\(    # date-prefixed entry, e.g. "2024-01-15 (v1.2.3)"
    }x

    class << self
      def fetch_changelog(gem_name)
        config = GEM_CHANGELOG[gem_name]
        return nil if config.nil?

        case config['type']
        when 'releases' then fetch_releases(config['repo'])
        when 'blob' then fetch_blob(config['repo'], config['path'], config['branch'])
        end
      rescue StandardError => e
        puts "Warning: Failed to fetch changelog for #{gem_name}: #{e.message}"
        nil
      end

      private

      def fetch_releases(repo)
        owner, name = repo.split('/')
        url = "https://api.github.com/repos/#{owner}/#{name}/releases/latest"
        headers = {'Accept' => 'application/vnd.github.v3+json'}
        headers['Authorization'] = "token #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN']

        response = HTTParty.get(url, headers: headers, timeout: 30)
        return nil unless response.success?

        data = JSON.parse(response.body)
        return nil if data['body'].to_s.empty?

        truncate("Release #{data['tag_name']}:\n#{data['body']}")
      end

      def fetch_blob(repo, path, branch = nil)
        # 'HEAD' lets raw.githubusercontent.com resolve to the repo's default branch.
        branch ||= 'HEAD'
        url = "https://raw.githubusercontent.com/#{repo}/#{branch}/#{path}"
        response = HTTParty.get(url, timeout: 30, follow_redirects: true)
        return nil unless response.success?

        extract_latest_version(response.body)
      end

      # Walks the changelog line by line, capturing content between the first
      # and second version headers.
      def extract_latest_version(content)
        return nil if content.nil?

        result = nil
        content.lines.each do |line|
          if line.match?(VERSION_HEADER)
            break if result

            result = line
          elsif result
            result += line
          end
        end

        truncate(result)
      end

      def truncate(content)
        return nil if content.nil?

        content.length > MAX_LENGTH ? content[0...MAX_LENGTH] + "\n[truncated]" : content
      end
    end
  end
end
