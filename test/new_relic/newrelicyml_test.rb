# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/tasks/helpers/newrelicyml'

class NewRelicYMLTest < Minitest::Test
  FAKE_CONFIGS = {
    :begonia => {
      :default => nil,
      :documentation_default => nil,
      :public => true,
      :description => 'If `true`, green with white polka dots.'
    },
    :lily => {
      :default => 1,
      :documentation_default => 2,
      :public => true,
      :description => <<~DESCRIPTION
        <Callout variant="caution">
          White flowers.
        </Callout>
      DESCRIPTION
    },
    :monstera => {
      :default => '',
      :public => true,
      :description => 'Leafy and [pretty](/pretty/plants).'
    },
    :pothos => {
      :default => '',
      :public => false,
      :description => 'Low <InlinePopover type="maintenance" />.'
    }
  }

  def final_config_hash
    config_hash = {
      :begonia => {
        :description => '  # If true, green with white polka dots.',
        :default => 'nil'
      },
      :lily => {
        :description => '  # White flowers.',
        :default => 2
      },
      :monstera => {
        :description => '  # Leafy and pretty.',
        :default => '""'
      }
    }

    config_hash
  end

  def test_public_config_true
    assert NewRelicYML.public_config?(FAKE_CONFIGS[:begonia])
  end

  def test_public_config_false
    refute NewRelicYML.public_config?(FAKE_CONFIGS[:pothos])
  end

  def test_sanitize_default_use_documentation_default
    assert_equal 2, NewRelicYML.sanitize_default(FAKE_CONFIGS[:lily])
  end

  def test_sanitize_default_string
    assert_equal '""', NewRelicYML.sanitize_default(FAKE_CONFIGS[:monstera])
  end

  def test_sanitize_default_nil
    assert_equal 'nil', NewRelicYML.sanitize_default(FAKE_CONFIGS[:begonia])
  end

  def test_sanitize_description_from_callouts
    assert_equal '  White flowers.', NewRelicYML.sanitize_description(FAKE_CONFIGS[:lily][:description])
  end

  def test_sanitize_description_from_backticks
    assert_equal 'If true, green with white polka dots.', NewRelicYML.sanitize_description(FAKE_CONFIGS[:begonia][:description])
  end

  def test_sanitize_description_from_hyperlinks
    assert_equal 'Leafy and pretty.', NewRelicYML.sanitize_description(FAKE_CONFIGS[:monstera][:description])
  end

  def test_sanitize_description_from_popovers
    assert_equal 'Low maintenance.', NewRelicYML.sanitize_description(FAKE_CONFIGS[:pothos][:description])
  end

  def test_format_description
    assert_equal '  # White flowers.', NewRelicYML.format_description('White flowers.')
  end

  def test_get_configs
    assert_equal final_config_hash, NewRelicYML.get_configs(FAKE_CONFIGS)
  end
end
