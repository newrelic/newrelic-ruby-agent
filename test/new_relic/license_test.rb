# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','test_helper'))

# look through the source code to enforce some simple rules that help us keep
# our license data up to date.
class LicenseTest < Minitest::Test
  include NewRelic::TestHelpers::FileSearching

  # A list of regexs that will likely match license info
  LICENSE_TERMS = {
    'GPL' => /GPL/i,
    '(c)' => /\(c\)/i,
    'Copyright' => /copyright/i,
    'BSD' => /\bBSD\b/i,
    'MIT' => /\bMIT\b/i,
    'Apache' => /\bapache\b/i,
    'rights reserved' => /rights reserved/i,
  }

  # Known occurrences of the above license terms
  # format is:
  # [ file, term ] => expected_number_of_occurances
  # unless listed here the expectation is that these terms will not occur in
  # the source code.
  EXPECTED_LICENSE_OCCURRENCES = {
    ['/LICENSE', '(c)'] => 1,
    ['/LICENSE', 'Copyright'] => 1,
    ['/LICENSE', 'rights reserved'] => 1,
    ['/lib/new_relic/agent/system_info.rb', 'BSD'] => 4, # reference to BSD the operating system, not BSD the license
    ['/test/new_relic/agent/system_info_test.rb', 'BSD'] => 2 # reference to BSD the operating system, not BSD the license
  }

  def frozen_string_literal
    /^# frozen_string_literal: true/
  end

  def empty_line
    /^/
  end

  def shebang
    /^#!/
  end

  def encoding
    /^# ?(en)?coding: utf-8/
  end

  def syntax_mark
    /^# -\*- ruby -\*-/
  end

  def should_skip?(path)
    (
      # skip directories
      !File.file?(path) ||
      # skip binary files
      %w| .sqlite3 .log .png .ico .gif .pdf .gem |.include?(File.extname(path)) ||
      # skip this file
      File.expand_path(__FILE__) == path ||
      # skip rpm_test_app and other stuff that ends up in tmp
      path.include?(gem_root + '/tmp/') ||
      # skip vendor/bundle
      path.include?(gem_root + '/vendor/bundle') ||
      # skip the auto-generated build.rb file
      path =~ %r{lib/new_relic/build\.rb} ||
      # skip tags file
      path =~ %r{/tags$}i ||
      # skip multiverse auto-generated gemfiles
      path =~ %r{/test/multiverse/suites/.*/Gemfile\.\d+(\.lock)?$} ||
      # skip multiverse auto-generated db/schema
      path =~ %r{/test/multiverse/suites/.*/db/schema.rb$} ||
      # skip the artifacts directory
      path =~ %r{/artifacts/}
    )
  end

  def test_all_rb_and_js_files_have_license_header
    all_rb_and_js_files.each do |filename|
      next if should_skip?(filename)

      first_thousand_bytes = File.read(filename, 1000)
      refute_nil first_thousand_bytes, "#{filename} is shorter than 1000 bytes."

      lines = first_thousand_bytes.split("\n")

      if lines.first =~ frozen_string_literal
        lines = lines[1..5]
        [empty_line, shebang, frozen_string_literal, empty_line, syntax_mark, encoding].each do |discard|
          if lines.first =~ discard
            lines.shift # discard it
          end
        end
      else
        [shebang, frozen_string_literal, empty_line, syntax_mark, encoding].each do |discard|
          if lines.first =~ discard
            lines.shift # discard it
          end
        end
      end

      assert_match(/This file is distributed under .+ license terms\./, lines[0], "#{filename} does not contain the proper license header.")
      assert_match(%r"See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.", lines[1])
    end
  end

  def test_for_scary_license_terms
    files_to_check = all_files.reject { |f| should_skip?(f) }
    files_to_check.each do |filename|
      LICENSE_TERMS.each do |key, pattern|
        begin
          # we're checking this one.  We'll update the count of checked files below.
          occurrences = File.readlines(filename).grep(pattern).size
          expected = (EXPECTED_LICENSE_OCCURRENCES[[filename.sub(gem_root, ''), key]] || 0)
          assert_equal expected, occurrences, "#{filename} contains #{key} #{occurrences} times. Should be #{expected}"
        rescue => e
          raise "Error when checking file #{filename}: #{e}"
        end
      end
    end
    # sanity check that we are not skipping all the files.
    checked_files = files_to_check.size
    assert checked_files >= 390, "Somethings off. We only scanned #{checked_files} files for license info.  There should be more."
  end
end
