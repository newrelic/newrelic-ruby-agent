# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

# look through the source code to enforce some simple rules that help us keep
# our license data up to date.
class LicenseTest < Minitest::Test
  PROJECT_ROOT = File.expand_path('../../..', __FILE__).freeze
  LICENSE_LINE1 = Regexp.escape(%q(# This file is distributed under New Relic's license terms.)).freeze
  LICENSE_LINE2 = Regexp.escape(%q(# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.)).freeze
  LICENSE_HEADER_REGEX = %r{^#{LICENSE_LINE1}\n#{LICENSE_LINE2}$}.freeze

  def ruby_files
    Dir.glob(File.join(PROJECT_ROOT, '**', '*.{rb,rake}')).reject { |path| path =~ %r{/(?:vendor|tmp|db|rails_app)/} }
  end

  def test_all_files_have_license_header
    ruby_files.each do |file|
      lines = []
      File.open(file, 'r') do |f|
        f.each_line do |line|
          break unless line.start_with?('#')

          lines << line
        end
      end

      assert_match(LICENSE_HEADER_REGEX, lines.join, "#{file} does not contain the proper license header.")
    end
  end
end
