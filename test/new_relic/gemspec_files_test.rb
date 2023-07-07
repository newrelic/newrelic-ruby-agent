# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'

class GemspecFilesTest < Minitest::Test
  def test_the_test_agent_helper_is_shipped_in_the_gem_files
    skip if defined?(Rails::VERSION)

    agent_helper_file = 'test/agent_helper.rb'

    gem_spec_file_path = File.expand_path('../../../newrelic_rpm.gemspec', __FILE__)

    gem_spec = Gem::Specification.load(gem_spec_file_path)

    assert_equal('newrelic_rpm', gem_spec.name)
    assert_includes(gem_spec.files, agent_helper_file)
  end
end
