# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'minitest/autorun'

class GemspecFilesTest < Minitest::Test
  def test_the_test_agent_helper_is_shipped_in_the_gem_files
    skip if defined?(Rails::VERSION)
    skip 'Gemspec test requires a newer version of Rubygems' unless Gem.respond_to?(:open_file)

    gem_spec_file_path = File.expand_path('../../../newrelic_rpm.gemspec', __FILE__)
    gem_spec_content = Gem.open_file(gem_spec_file_path, 'r:UTF-8:-', &:read)
    gem_spec_content.gsub!('__FILE__', "'#{gem_spec_file_path}'")

    Dir.chdir(File.dirname(gem_spec_file_path)) do
      gem_spec = eval(gem_spec_content)

      assert gem_spec, "Failed to parse '#{gem_spec_file_path}'"
      assert_equal('newrelic_rpm', gem_spec.name)
      assert_includes(gem_spec.files, 'test/agent_helper.rb')
    end
  end
end
