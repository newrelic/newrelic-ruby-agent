# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

# test_helper works without Rails, so fake a Rails class for testing
unless defined?(::ActiveRecord::Migration)
  module ActiveRecord
    module VERSION; end
    class Migration
      def self.[](version)
        version
      end
    end
  end
end

class TestHelperTest < Minitest::Test
  # BEGIN current_active_record_migration_version
  def test_use_a_version_with_ar_gte_5
    version = [7, 0, 3, 1]
    ::ActiveRecord::VERSION.stub_const(:STRING, version.join('.')) do
      assert_equal "#{version.first}.0", current_active_record_migration_version
    end
  end

  def test_do_not_use_a_version_with_ar_lt_5
    ::ActiveRecord::VERSION.stub_const(:STRING, '0.8.0') do
      assert_equal ::ActiveRecord::Migration, current_active_record_migration_version
    end
  end
  # END current_active_record_migration_version
end
