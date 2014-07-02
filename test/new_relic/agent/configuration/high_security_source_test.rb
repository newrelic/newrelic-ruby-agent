# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..','..','..','test_helper'))
require 'new_relic/agent/configuration/high_security_source'

module NewRelic::Agent::Configuration
  class HighSecuritySourceTest < Minitest::Test
    def test_leaves_obfuscated_record_sql_parameters
      local_settings = {
        :'transaction_tracer.record_sql' => 'obfuscated',
        :'slow_sql.record_sql'           => 'obfuscated'
      }

      source = HighSecuritySource.new(local_settings)

      assert_equal('obfuscated', source[:'transaction_tracer.record_sql'])
      assert_equal('obfuscated', source[:'slow_sql.record_sql'])
    end

    def test_leaves_off_record_sql_parameters
      local_settings = {
        :'transaction_tracer.record_sql' => 'off',
        :'slow_sql.record_sql'           => 'off'
      }

      source = HighSecuritySource.new(local_settings)

      assert_equal('off', source[:'transaction_tracer.record_sql'])
      assert_equal('off', source[:'slow_sql.record_sql'])
    end

    def test_changes_raw_record_sql_to_obfuscated
      local_settings = {
        :'transaction_tracer.record_sql' => 'raw',
        :'slow_sql.record_sql'           => 'raw'
      }

      source = HighSecuritySource.new(local_settings)

      assert_equal('obfuscated', source[:'transaction_tracer.record_sql'])
      assert_equal('obfuscated', source[:'slow_sql.record_sql'])
    end

    def test_forces_unrecognized_values_to_off
      local_settings = {
        :'transaction_tracer.record_sql' => 'jibberish',
        :'slow_sql.record_sql'           => 'junk'
      }

      source = HighSecuritySource.new(local_settings)

      assert_equal('off', source[:'transaction_tracer.record_sql'])
      assert_equal('off', source[:'slow_sql.record_sql'])
    end
  end
end
