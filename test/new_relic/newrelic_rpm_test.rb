# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

class NewRelicRpmTest < Minitest::Test
  RAILS_32_SKIP_MESSAGE = 'MySQL error for Rails 3.2 when we add an initializer to config/initializers'
  # This test examines the behavior of an initializer when the agent is started in a Rails context
  # The initializer used for these tests is defined in test/environments/*/config/inititalizers/test.rb

  # We have documentation recommending customers call add_method_tracer
  # in their initializers, let's make sure this works
  def test_add_method_tracer_in_initializer_gets_traced_when_agent_initialized_after_config_initializers
    skip unless defined?(Rails::VERSION)
    skip RAILS_32_SKIP_MESSAGE if Rails::VERSION::MAJOR == 3

    assert Bloodhound.newrelic_method_exists?('sniff'),
      'Bloodhound#sniff not found by' \
      'NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer.newrelic_method_exists?'
    assert Bloodhound.method_traced?('sniff'),
      'Bloodhound#sniff not found by' \
      'NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer.method_traced?'
  end

  # # All supported Rails versions have the default value for
  # # timestamped_migrations as true. Our initializer sets it to false.
  # # Test to resolve: https://github.com/newrelic/newrelic-ruby-agent/issues/662

  # def test_active_record_initializer_config_change_saved_when_agent_initialized_after_config_initializers
  #   ENV['NEW_RELIC_DEFER_RAILS_INITIALIZATION'] = 'true'
  #   skip unless defined?(Rails::VERSION)
  #   skip RAILS_32_SKIP_MESSAGE if Rails::VERSION::MAJOR == 3
  #   # skip "Test passes in a Rails console on a playground app and in the customer's environment, but fails here"
  #   # Verify the configuration value was set to the initializer value
  #   refute Rails.application.config.active_record.timestamped_migrations,
  #     "Rails.application.config.active_record.timestamped_migrations equals true, expected false"

  #   # Verify the configuration value was applied to the ActiveRecord class variable
  #   if Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new('7.1')
  #     refute ActiveRecord.timestamped_migrations, "ActiveRecord.timestamped_migrations equals true, expected false"
  #   else
  #     refute ActiveRecord::Base.timestamped_migrations,
  #       "ActiveRecord::Base.timestamped_migrations equals true, expected false"
  #   end
  # end
end
