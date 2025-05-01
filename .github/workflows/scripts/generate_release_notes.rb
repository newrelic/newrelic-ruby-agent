#!/usr/bin/ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'date'
require_relative '../../../lib/new_relic/version'

class GenerateReleaseNotes
  DIVIDER = '---'
  SUPPORT_STATEMENT = <<~SUPPORT_STATEMENT
  <Callout variant="important">
    We recommend updating to the latest agent version as soon as it's available. If you can't upgrade to the latest version, update your agents to a version no more than 90 days old. Read more about [keeping agents up to date](/docs/new-relic-solutions/new-relic-one/install-configure/update-new-relic-agent/).

    See the New Relic Ruby agent [EOL policy](https://docs.newrelic.com/docs/apm/agents/ruby-agent/getting-started/ruby-agent-eol-policy/) for information about agent releases and support dates.
  </Callout>
  SUPPORT_STATEMENT

  def build_metadata
    changelog = File.read('CHANGELOG.md')
    latest_entry = changelog.split('##')[1].prepend('##')
    titles = latest_entry.scan(/^- \*{2}(.*?)\*{2}$/).flatten # Match strings between sets of '**'
    metadata = Hash.new { |h, k| h[k] = [] }

    titles.each do |t|
      category = t.split(':').first
      case category
      when 'Feature'
        metadata[:features] << t.delete_prefix('Feature: ')
      when 'Bugfix'
        metadata[:bugs] << t.delete_prefix('Bugfix: ')
      when 'Security'
        metadata[:security] << t.delete_prefix('Security: ')
      end
    end

    return metadata, latest_entry
  end

  def build_release_content
    metadata, latest_entry = build_metadata
    <<~FRONTMATTER
      #{DIVIDER}
      subject: Ruby agent
      releaseDate: '#{Date.today}'
      version: #{NewRelic::VERSION::STRING}
      downloadLink: https://rubygems.org/downloads/newrelic_rpm-#{NewRelic::VERSION::STRING}.gem
      features: #{metadata[:features]}
      bugs: #{metadata[:bugs]}
      security: #{metadata[:security]}
      #{DIVIDER}

      #{SUPPORT_STATEMENT}
      #{latest_entry}
    FRONTMATTER
  end

  def hyphenated_version_string
    NewRelic::VERSION::STRING.tr('.', '-')
  end

  def write_file_name
    "ruby-agent-#{hyphenated_version_string}.mdx"
  end

  def write_output_file
    File.write(write_file_name, build_release_content)
  end

  # The following 2 methods are used for dynamic naming in release_notes.yml
  def file_name
    puts write_file_name
  end

  def branch_name
    puts "ruby_release_notes_#{hyphenated_version_string}"
  end
end
