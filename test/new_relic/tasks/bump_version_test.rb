# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/tasks/helpers/version_bump'

module NewRelic
  class BumpVersionTest < Minitest::Test
    def teardown
      mocha_teardown
    end

    VERSION_FILE = 'lib/new_relic/version.rb'
    CHANGELOG_FILE = 'CHANGELOG.md'
    def test_update_version_major
      ::VersionBump.stubs(:determine_bump_type).returns(::VersionBump::MAJOR)
      ::VersionBump.stubs(:read_file).returns(version_code(3, 6, 11))
      ::VersionBump.expects(:write_file).with(VERSION_FILE, version_code(4, 0, 0))

      assert_equal '4.0.0', ::VersionBump.update_version
    end

    def test_update_version_minor
      ::VersionBump.stubs(:determine_bump_type).returns(::VersionBump::MINOR)
      ::VersionBump.stubs(:read_file).returns(version_code(3, 6, 11))
      ::VersionBump.expects(:write_file).with(VERSION_FILE, version_code(3, 7, 0))

      assert_equal '3.7.0', ::VersionBump.update_version
    end

    def test_update_version_tiny
      ::VersionBump.stubs(:determine_bump_type).returns(::VersionBump::TINY)
      ::VersionBump.stubs(:read_file).returns(version_code(3, 6, 11))
      ::VersionBump.expects(:write_file).with(VERSION_FILE, version_code(3, 6, 12))

      assert_equal '3.6.12', ::VersionBump.update_version
    end

    def test_determine_bump_type_major
      ::VersionBump.stubs(:read_file).returns(changelog(::VersionBump::MAJOR))

      assert_equal ::VersionBump::MAJOR, ::VersionBump.determine_bump_type
    end

    def test_determine_bump_type_minor
      ::VersionBump.stubs(:read_file).returns(changelog(::VersionBump::MINOR))

      assert_equal ::VersionBump::MINOR, ::VersionBump.determine_bump_type
    end

    def test_determine_bump_type_tiny
      ::VersionBump.stubs(:read_file).returns(changelog(::VersionBump::TINY))

      assert_equal ::VersionBump::TINY, ::VersionBump.determine_bump_type
    end

    def test_update_changelog
      ::VersionBump.stubs(:read_file).returns(changelog(::VersionBump::MINOR))

      expected_version = '5.3.1'
      expected_changelog = <<~CHANGELOG
        # New Relic Ruby Agent Release Notes

        ## v#{expected_version}
        
        Version #{expected_version} of the agent does a bunch of stuff
        
        - **Feature: feature or bugfix?**
        
          what a description

        ## v4.5.6
      CHANGELOG

      ::VersionBump.expects(:write_file).with('CHANGELOG.md', expected_changelog)
      ::VersionBump.update_changelog(expected_version)
    end

    private

    def version_code(major, minor, tiny)
      <<~VERSION
        #!/usr/bin/ruby
        # This file is distributed under New Relic's license terms.
        # See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
        # frozen_string_literal: true

        module NewRelic
          module VERSION # :nodoc:
            MAJOR = #{major}
            MINOR = #{minor}
            TINY = #{tiny}
        
            STRING = "\#{MAJOR}.\#{MINOR}.\#{TINY}"
          end
        end
      VERSION
    end

    def changelog(version)
      feature_bugfix = if version == ::VersionBump::MINOR
        'Feature:'
      elsif version == ::VersionBump::TINY
        'Bugfix:'
      end

      <<~CHANGELOG
        # New Relic Ruby Agent Release Notes

        ## dev
        
        #{version == ::VersionBump::MAJOR ? 'Major v' : 'V'}ersion <dev> of the agent does a bunch of stuff
        
        - **#{feature_bugfix} feature or bugfix?**
        
          what a description

        ## v4.5.6
      CHANGELOG
    end
  end
end
