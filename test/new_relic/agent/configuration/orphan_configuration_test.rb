# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))

class OrphanedConfigTest < Test::Unit::TestCase
  include NewRelic::TestHelpers::FileSearching

  def setup
    @default_keys = ::NewRelic::Agent::Configuration::DEFAULTS.keys
  end

  def test_all_agent_config_keys_are_declared_in_default_source
    non_test_files = all_rb_files.reject { |filename| filename.include? 'test.rb' }

    non_test_files.each do |file|
      lines = File.read(file).split("\n")

      lines.each_with_index do |line, index|
        config_match = line.match(/Agent\.config\[:([a-z\._]+)\]/)
        next unless config_match

        config_keys = config_match.captures.map do |key|
          key.gsub("'", "").to_sym
        end

        config_keys.each do |key|
          msg = "#{file}:#{index} - Configuration key #{key} is not described in default_source.rb.\n"
          assert @default_keys.include?(key), msg
        end
      end
    end
  end

  def test_all_default_source_config_keys_are_used_in_the_agent
    non_test_files = all_rb_files.reject { |filename| filename.include? 'test.rb' }

    non_test_files.each do |file|
      lines = File.read(file).split("\n")

      lines.each_with_index do |line, index|
        config_match = line.match(/Agent\.config\[:([a-z\._]+)\]/)
        next unless config_match

        config_match.captures.map do |key|
          @default_keys.delete key.gsub("'", "").to_sym
        end
      end
    end

    assert_empty @default_keys
  end
end
