# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# The unit test class defined herein will verify the health of all URLs found
# in the project source code.
#
# To run the URL health tests by themselves:
#   TEST=test/new_relic/healthy_urls_test bundle exec rake test
#
# A file will be scanned for URLs if the file's basename is found in the
# FILENAMES array OR the file's extension is found in the EXTENSIONS array
# unless the file's absolute path matches the IGNORED_FILE_PATTERN regex.
#
# NOTE that CHANGELOG.md is handled with special logic so that only the most
# recent 2 versions mentioned in the changelog are scannned for URLs.
#
# See TIMEOUT for the number of seconds permitted for a GET request to a given
# URL to be completed.
#
# Enable DEBUG for additional verbosity

require 'httparty'
require_relative '../test_helper'

class HealthyUrlsTest < Minitest::Test
  ROOT = File.expand_path('../../..', __FILE__).freeze
  FILENAMES = %w[
    baselines
    Brewfile
    Capfile
    Dockerfile
    Envfile
    Gemfile
    Guardfile
    install_mysql55
    LICENSE
    mega-runner
    newrelic
    newrelic_cmd
    nrdebug
    Rakefile
    run_tests
    runner
    Thorfile
  ].freeze
  EXTENSIONS = %w[
    css
    erb
    gemspec
    haml
    html
    js
    json
    md
    proto
    rake
    readme
    rb
    sh
    txt
    thor
    tt
    yml
  ].freeze
  FILE_PATTERN = /(?:^(?:#{FILENAMES.join('|')})$)|\.(?:#{EXTENSIONS.join('|')})$/.freeze
  IGNORED_FILE_PATTERN = %r{/(?:coverage|test)/}.freeze
  URL_PATTERN = %r{(https?://.*?)[^a-zA-Z0-9/\.\-_#]}.freeze
  IGNORED_URL_PATTERN = %r{(?:\{|\(|\$|169\.254|\.\.\.|metadata\.google)}
  TIMEOUT = 5
  DEBUG = false

  def test_all_urls
    skip_unless_ci_cron
    skip_unless_newest_ruby

    urls = gather_urls
    errors = urls.each_with_object({}) do |(url, _files), hash|
      error = verify_url(url)
      hash[url] = error if error
    end

    msg = "#{errors.keys.size} URLs were unreachable!\n\n"
    msg += errors.map { |url, error| "  #{url} - #{error}\n    files: #{urls[url].join(',')}" }.join("\n")

    assert_empty errors, msg
  end

  private

  def real_url?(url)
    return false if url.match?(IGNORED_URL_PATTERN)

    true
  end

  def gather_urls
    Dir.glob(File.join(ROOT, '**', '*')).each_with_object({}) do |file, urls|
      next unless File.file?(file) && File.basename(file).match?(FILE_PATTERN) && !file.match?(IGNORED_FILE_PATTERN)

      catch :done_with_file do
        changelog_entries_seen = 0
        File.open(file).each do |line|
          changelog_entries_seen += 1 if File.basename(file).eql?('CHANGELOG.md') && line.start_with?('##')
          throw :done_with_file if changelog_entries_seen > 2
          next unless line =~ URL_PATTERN

          url = Regexp.last_match(1).sub(%r{(?:/|\.)$}, '')
          if real_url?(url)
            urls[url] ||= []
            urls[url] << file
          end
        end
      end
    end
  end

  def verify_url(url)
    puts "Testing '#{url}'..." if DEBUG
    res = HTTParty.get(url, timeout: TIMEOUT)
    if res.success?
      puts '  OK.' if DEBUG
      return
    end

    msg = "HTTP #{res.code}: #{res.message}"
    puts "  FAILED. #{msg}" if DEBUG
    msg
  rescue StandardError => e
    msg = "#{e.class}: #{e.message}"
    puts "  FAILED. #{msg}" if DEBUG
    msg
  end
end
