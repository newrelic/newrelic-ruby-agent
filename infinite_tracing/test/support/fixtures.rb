# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'yaml'

def fixtures_path
  @fixtures_path ||= File.expand_path(File.join(File.dirname(__FILE__), '..', 'fixtures'))
end

def span_event_fixture fixture_name
  fixture_filename = File.join(fixtures_path, "span_events", "#{fixture_name}.yml")
  assert File.exist?(fixture_filename), "Missing Span Event Fixture: #{fixture_name}. Looked for #{fixture_filename}"
  YAML::load File.read(fixture_filename)
end