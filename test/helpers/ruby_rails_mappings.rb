# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'yaml'

CI_FILE = File.expand_path('../../../.github/workflows/ci.yml', __FILE__)

def ruby_rails_versions_hash
  @versions_hash ||= begin
    ci = YAML.load_file(CI_FILE)
    map_yaml = ci['jobs']['unit_tests']['steps'].detect do |hash|
      hash.key?('with') && hash['with'].key?('map')
    end['with']['map']
    versions = YAML.load(map_yaml)
  end
end

def rails_versions_for_ruby_version(ruby_version)
  (((ruby_rails_versions_hash[ruby_version] || {})['rails']) || '').split(',')
end
