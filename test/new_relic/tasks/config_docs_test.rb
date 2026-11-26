# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'tmpdir'
require_relative '../../test_helper'
require_relative '../../../lib/tasks/helpers/format'

class ConfigDocsTest < Minitest::Test
  EXPECTED_SETTINGS_SLUGS = %w[
    ruby-agent-configuration-general-settings
    ruby-agent-configuration-transaction-tracer-settings
    ruby-agent-configuration-error-collector-settings
    ruby-agent-configuration-browser-monitoring-settings
    ruby-agent-configuration-distributed-tracing-settings
    ruby-agent-configuration-logs-in-context-settings
    ruby-agent-configuration-ai-monitoring-settings
    ruby-agent-configuration-attributes-settings
    ruby-agent-configuration-other-settings
  ].freeze

  EXPECTED_REDIRECTS = %w[
    /docs/apm/agents/ruby-agent/configuration/ruby-agent-configuration
    /docs/agents/ruby-agent/configuration/ruby-agent-configuration
    /docs/ruby/ruby-agent-configuration
    /docs/agents/ruby-agent/installation-and-configuration/ruby-agent-configuration
    /docs/agents/ruby-agent/installation-configuration/ruby-agent-configuration
  ].freeze

  OVERVIEW_FILE = 'ruby-agent-configuration-overview.mdx'

  def test_write_text_file_writes_one_file_with_every_public_setting
    in_tmpdir do
      Format.write_text_file

      content = File.read('ruby-agent-configuration.mdx')

      public_keys.each { |key| assert_includes content, "\n#{key}\n" }
      refute Dir.exist?('config-docs')
    end
  end

  def test_every_config_section_is_assigned_to_a_docs_page
    unassigned = Format.unassigned_sections(Format.build_config_hash.keys)

    assert_empty unassigned, "Every config section must be assigned to a docs page.\n" \
      "Unassigned: #{unassigned.inspect}\n" \
      'Add each one to the page it belongs on in lib/tasks/helpers/format.rb.'
  end

  def test_section_descriptions_and_name_overrides_match_real_sections
    sections = Format.build_config_hash.keys

    assert_empty Format::SECTION_DESCRIPTIONS.keys - sections, 'SECTION_DESCRIPTIONS has a key that no setting uses'
    assert_empty Format::NAME_OVERRIDES.keys - sections, 'NAME_OVERRIDES has a key that no setting uses'
  end

  def test_unassigned_sections_returns_unknown_sections_sorted
    assert_equal %w[apple zebra], Format.unassigned_sections(%w[zebra general apple])
  end

  def test_no_section_is_assigned_to_two_pages
    assigned = Format::SETTINGS_PAGES.flat_map { |page| page[:sections] }
    duplicates = assigned.select { |section| assigned.count(section) > 1 }.uniq

    assert_empty duplicates
  end

  def test_other_settings_page_is_the_only_fallback_page
    fallback_slugs = Format::SETTINGS_PAGES.select { |page| page[:fallback] }.map { |page| page[:slug] }

    assert_equal ['ruby-agent-configuration-other-settings'], fallback_slugs
  end

  def test_docs_pages_returns_overview_then_nine_settings_pages
    expected = [OVERVIEW_FILE] + EXPECTED_SETTINGS_SLUGS.map { |slug| "#{slug}.mdx" }

    assert_equal expected, Format.docs_pages.keys
  end

  def test_every_public_setting_appears_on_exactly_one_page
    setting_title = /<Collapser id="[^"]+" title="([^"]+)">/
    titles = Format.docs_pages.values.flat_map { |content| content.scan(setting_title).flatten }

    assert_equal public_keys.sort, titles.sort
  end

  def test_known_sections_land_on_expected_pages
    pages = Format.docs_pages
    first_heading_on_other_page = pages['ruby-agent-configuration-other-settings.mdx'][/^## .*$/]

    assert_includes pages['ruby-agent-configuration-transaction-tracer-settings.mdx'], "\n## Slow SQL [#slow-sql]\n"
    assert_includes pages['ruby-agent-configuration-distributed-tracing-settings.mdx'], "\n## Span Events [#span-events]\n"
    assert_equal '## Transaction Events [#transaction-events]', first_heading_on_other_page
  end

  def test_unassigned_section_falls_back_to_end_of_other_page
    fake_setting = {:'zebra_feature.enabled' => {:default => true, :public => true, :type => NewRelic::Agent::Configuration::Boolean, :description => 'Fake.'}}
    defaults = NewRelic::Agent::Configuration::DEFAULTS.merge(fake_setting)
    other = Format.docs_pages(defaults)['ruby-agent-configuration-other-settings.mdx']

    assert_equal '## Zebra Feature [#zebra-feature]', other.scan(/^## .*$/).last
  end

  def test_overview_keeps_all_five_redirects
    overview = Format.docs_pages[OVERVIEW_FILE]

    EXPECTED_REDIRECTS.each { |path| assert_includes overview, "\n  - #{path}\n" }
  end

  def test_overview_table_links_every_settings_page
    overview = Format.docs_pages[OVERVIEW_FILE]

    EXPECTED_SETTINGS_SLUGS.each { |slug| assert_includes overview, "](/docs/apm/agents/ruby-agent/configuration/#{slug}) |" }
  end

  def test_overview_starts_with_its_frontmatter
    assert Format.docs_pages[OVERVIEW_FILE].start_with?("---\ntitle: Configuration overview\n")
  end

  def test_settings_pages_start_with_their_own_frontmatter
    pages = Format.docs_pages

    Format::SETTINGS_PAGES.each do |page|
      content = pages["#{page[:slug]}.mdx"]

      assert content.start_with?("---\ntitle: #{page[:title]}\n"), "#{page[:slug]} must start with its own frontmatter"
      refute_match(/^redirects:/, content, page[:slug])
      refute_match(/^translate:/, content, page[:slug])
    end
  end

  def test_every_page_has_contributor_note_and_freshness_date
    Format.docs_pages.each do |name, content|
      assert_includes content, "<CONTRIBUTOR_NOTE>\n", name
      assert_match(/^freshnessValidatedDate: /, content, name)
    end
  end

  def test_every_page_ends_with_exactly_one_newline
    Format.docs_pages.each do |name, content|
      assert content.end_with?("\n"), "#{name} must end with a newline"
      refute content.end_with?("\n\n"), "#{name} must not end with a blank line"
    end
  end

  def test_error_collector_page_ends_with_errors_inbox_section
    page = Format.docs_pages['ruby-agent-configuration-error-collector-settings.mdx']

    assert page.end_with?(Format::ERRORS_INBOX_SECTION)
  end

  def test_write_docs_pages_writes_ten_files_into_config_docs
    in_tmpdir do
      Format.write_docs_pages

      assert_equal Format.docs_pages.keys.sort, Dir.children('config-docs').sort
      refute_includes Dir.children('.'), 'ruby-agent-configuration.mdx'
    end
  end

  def test_in_page_anchor_links_resolve_on_the_same_page
    Format.docs_pages.each do |name, content|
      ids = anchor_ids(content)
      links = content.scan(/\]\(#([^)]+)\)/).flatten

      links.each { |anchor| assert_includes ids, anchor, "#{name} links to missing ##{anchor}" }
    end
  end

  def test_cross_page_anchor_links_resolve_on_their_target_page
    pages = Format.docs_pages
    slugs = [Format::OVERVIEW_SLUG] + Format::SETTINGS_PAGES.map { |page| page[:slug] }
    prefix = Regexp.escape(Format::DOCS_URL_PREFIX)
    slug_pattern = Regexp.union(slugs)
    link = %r{\]\(#{prefix}(#{slug_pattern})#([^)]+)\)}

    pages.each do |name, content|
      content.scan(link).each do |slug, anchor|
        assert_includes anchor_ids(pages["#{slug}.mdx"]), anchor, "#{name} links to missing #{slug}##{anchor}"
      end
    end
  end

  def test_no_links_to_anchors_on_the_retired_single_page
    Format.docs_pages.each { |name, content| refute_match(%r{ruby-agent-configuration/?#}, content, name) }
  end

  private

  def anchor_ids(content)
    setting_ids = content.scan(/<Collapser id="([^"]+)"/).flatten
    heading_ids = content.scan(/^## .*\[#([^\]]+)\]$/).flatten
    setting_ids + heading_ids
  end

  def public_keys
    NewRelic::Agent::Configuration::DEFAULTS.select { |_, v| v[:public] }.keys.map(&:to_s)
  end

  def in_tmpdir
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield }
    end
  end
end
