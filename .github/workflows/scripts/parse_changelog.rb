#!/usr/bin/ruby
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'date'
require_relative '../../../lib/new_relic/version'

DIVIDER = '---'
SUPPRORT_STATEMENT = "<Callout variant=\"important\">
We recommend updating to the latest agent version as soon as it's available. If you can't upgrade to the latest version, update your agents to a version at most 90 days old. Read more about [keeping agent up to date](/docs/new-relic-solutions/new-relic-one/install-configure/update-new-relic-agent/).

See the New Relic Ruby agent [EOL policy](https://docs.newrelic.com/docs/apm/agents/ruby-agent/getting-started/ruby-agent-eol-policy/) for information about agent releases and support dates.
</Callout>"

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

frontmatter = [
  DIVIDER,
  'subject: Ruby agent',
  "date: #{Date.today}",
  "version: #{NewRelic::VERSION::STRING}",
  "downloadLink: https://rubygems.org/downloads/newrelic_rpm-#{NewRelic::VERSION::STRING}.gem",
  "features: #{metadata[:feature]}",
  "bugs: #{metadata[:bugs]}",
  "security: #{metadata[:security]}",
  DIVIDER,
  '',
  SUPPRORT_STATEMENT,
  '',
  latest_entry
]

File.write("ruby-agent-#{NewRelic::VERSION::STRING.tr('.', '-')}.mdx", frontmatter.join("\n"))
