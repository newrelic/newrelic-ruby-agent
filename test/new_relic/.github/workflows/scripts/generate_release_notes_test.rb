require 'tmpdir'
require_relative '../test_helper'
require_relative '../../.github/workflows/scripts/generate_release_notes'

module NewRelic
  class GenerateReleaseNotesTest < MiniTest::Test
    def setup
      @fake_changelog_content = <<~CHANGELOG
        # New Relic Ruby Agent Release Notes

        ## v9.8.0

        - **Feature: Add support for new framework**

          New framework support has been added.
            - Support for new framework X
            - Support for new framework Y

        - **Bugfix: Fix memory leak in instrumentation**

          Memory leak issue has been resolved.

        - **Security: Address potential XSS vulnerability**

          Security vulnerability has been addressed.

        ## v9.7.1

        Version 9.7.1 includes changes.

        - **Bugfix: Fix issue with database connections**

          Issue with database connections has been resolved.

        ## v9.7.0

        Version 9.7.0 includes some changes.

        - **Feature: New distributed tracing capabilities**

          Distributed tracing capabilities have been added.

        - **Bugfix: Resolve threading issues**

          Threading issues have been resolved.

        - Performance improvements

        - **Documentation: Improvements to config formatting**

          Config formatting improvements have been made.
      CHANGELOG

      @fake_changelog_file = File.join(Dir.tmpdir, 'test_changelog.md')
      File.write(@fake_changelog_file, @fake_changelog_content)
    end

    def teardown
      File.delete(@fake_changelog_file) if @fake_changelog_file && File.exist?(@fake_changelog_file)
    end

    def test_initialize_with_default_changelog
      generator = GenerateReleaseNotes.new

      assert_instance_of GenerateReleaseNotes, generator
      assert_instance_of Array, generator.instance_variable_get(:@split_changelog)
    end

    def test_initialize_with_custom_changelog
      generator = GenerateReleaseNotes.new(@fake_changelog_file)
      split_changelog = generator.instance_variable_get(:@split_changelog)

      assert_includes split_changelog[1], 'v9.8.0'
      assert_includes split_changelog[2], 'v9.7.1'
    end

    def test_build_metadata_extracts_features_bugs_security
      generator = GenerateReleaseNotes.new(@fake_changelog_file)
      metadata, latest_entry = generator.build_metadata

      assert_equal ['Add support for new framework'], metadata[:features]
      assert_equal ['Fix memory leak in instrumentation'], metadata[:bugs]
      assert_equal ['Address potential XSS vulnerability'], metadata[:security]
      assert_includes latest_entry, '## v9.8.0'
    end

    def test_build_metadata_handles_empty_categories
      changelog_content = <<~CHANGELOG
        # New Relic Ruby Agent Release Notes

        ## v9.8.0

        - General improvements
        - Documentation updates
      CHANGELOG

      changelog_file = File.join(Dir.tmpdir, 'empty_categories_changelog.md')
      File.write(changelog_file, changelog_content)

      generator = GenerateReleaseNotes.new(changelog_file)
      metadata, _latest_entry = generator.build_metadata

      assert_empty metadata[:features]
      assert_empty metadata[:bugs]
      assert_empty metadata[:security]

      File.delete(changelog_file)
    end

    def test_build_release_content_structure
      generator = GenerateReleaseNotes.new(@fake_changelog_file)
      content = generator.build_release_content

      assert_includes content, '---'
      assert_includes content, 'subject: Ruby agent'
      assert_includes content, "releaseDate: '#{Date.today}'"
      assert_includes content, "version: #{NewRelic::VERSION::STRING}"
      assert_includes content, "downloadLink: https://rubygems.org/downloads/newrelic_rpm-#{NewRelic::VERSION::STRING}.gem"
      assert_includes content, 'features: ["Add support for new framework"]'
      assert_includes content, 'bugs: ["Fix memory leak in instrumentation"]'
      assert_includes content, 'security: ["Address potential XSS vulnerability"]'
      assert_includes content, GenerateReleaseNotes::SUPPORT_STATEMENT
      assert_includes content, '## v9.8.0'
    end

    def test_major_bump_detection_true
      # Create changelog with major version bump
      major_bump_changelog = <<~CHANGELOG
        # New Relic Ruby Agent Release Notes

        ## v10.0.0

        - **Feature: Breaking changes**

          Breaking changes have been introduced.

        ## v9.8.0

        This version fixes a bug.

        - **Bugfix: Previous version fix**

          Previous version problem has been resolved.
      CHANGELOG

      changelog_file = File.join(Dir.tmpdir, 'major_bump_changelog.md')
      File.write(changelog_file, major_bump_changelog)

      generator = GenerateReleaseNotes.new(changelog_file)

      # Mock the current version to be 10.0.0
      NewRelic::VERSION.stub_const(:MAJOR, 10) do
        assert generator.major_bump?
      end

      File.delete(changelog_file)
    end

    def test_major_bump_detection_false
      generator = GenerateReleaseNotes.new(@fake_changelog_file)

      # Mock the current version to be same major version
      NewRelic::VERSION.stub_const(:MAJOR, 9) do
        refute generator.major_bump?
      end
    end

    def test_major_version_banner
      generator = GenerateReleaseNotes.new(@fake_changelog_file)
      banner = generator.major_version_banner

      assert_includes banner, "Major Version Update"
      assert_includes banner, "SemVer MAJOR update"
      assert_includes banner, "breaking changes"
      assert_includes banner, "migration guide"
    end

    def test_build_release_content_includes_major_banner_when_major_bump
      major_bump_changelog = <<~CHANGELOG
        # New Relic Ruby Agent Release Notes

        ## v10.0.0

        - **Feature: Breaking changes**

          Breaking changes have been introduced.

        ## v9.8.0

        This version fixes a bug.

        - **Bugfix: Previous version fix**

          Previous version fix has been resolved.
      CHANGELOG

      changelog_file = File.join(Dir.tmpdir, 'major_bump_changelog.md')
      File.write(changelog_file, major_bump_changelog)

      generator = GenerateReleaseNotes.new(changelog_file)

      NewRelic::VERSION.stub_const(:MAJOR, 10) do
        content = generator.build_release_content
        assert_includes content, "Major Version Update"
      end

      File.delete(changelog_file)
    end

    def test_hyphenated_version_string
      generator = GenerateReleaseNotes.new(@fake_changelog_file)

      NewRelic::VERSION.stub_const(:STRING, '9.8.0') do
        assert_equal '9-8-0', generator.hyphenated_version_string
      end
    end

    def test_write_file_name
      generator = GenerateReleaseNotes.new(@fake_changelog_file)

      NewRelic::VERSION.stub_const(:STRING, '9.8.0') do
        assert_equal 'ruby-agent-9-8-0.mdx', generator.write_file_name
      end
    end

    def test_write_output_file
      generator = GenerateReleaseNotes.new(@fake_changelog_file)

      NewRelic::VERSION.stub_const(:STRING, '9.8.0') do
        generator.write_output_file

        expected_filename = 'ruby-agent-9-8-0.mdx'
        assert File.exist?(expected_filename)

        content = File.read(expected_filename)
        assert_includes content, 'subject: Ruby agent'
        assert_includes content, 'version: 9.8.0'

        File.delete(expected_filename)
      end
    end

    def test_file_name_output
      generator = GenerateReleaseNotes.new(@fake_changelog_file)

      NewRelic::VERSION.stub_const(:STRING, '9.8.0') do
        assert_output("ruby-agent-9-8-0.mdx\n") do
          generator.file_name
        end
      end
    end

    def test_branch_name_output
      generator = GenerateReleaseNotes.new(@fake_changelog_file)

      NewRelic::VERSION.stub_const(:STRING, '9.8.0') do
        assert_output("ruby_release_notes_9-8-0\n") do
          generator.branch_name
        end
      end
    end
  end
end