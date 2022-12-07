# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../test_helper'

class NewRelicRpmTest < Minitest::Test
  # This test examines the behavior of an initializer when the agent is started in a Rails context
  # The initializer used for these tests is defined in test/environments/*/config/inititalizers/test.rb

  # We have documentation recommending customers call add_method_tracer
  # in their initializers, let's make sure this works
  def test_add_method_tracer_in_initializer_gets_traced_when_agent_initialized_before_config_initializers
    skip unless defined?(Rails::VERSION)
    skip 'MySQL error for Rails 3.2' if Rails::VERSION::MAJOR == 3

    with_config(defer_rails_initialization: false) do
      assert Bloodhound.newrelic_method_exists?('sniff'),
        'Bloodhound#sniff not found by' \
        'NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer.newrelic_method_exists?'
      assert Bloodhound.method_traced?('sniff'),
        'Bloodhound#sniff not found by' \
        'NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer.method_traced?'
    end
  end

  def test_add_method_tracer_in_initializer_gets_traced_when_agent_initialized_after_config_initializers
    skip unless defined?(Rails::VERSION)
    skip 'MySQL error for Rails 3.2 if we define an initializer in config/initializers' if Rails::VERSION::MAJOR == 3

    with_config(defer_rails_initialization: true) do
      assert Bloodhound.newrelic_method_exists?('sniff'),
        'Bloodhound#sniff not found by' \
        'NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer.newrelic_method_exists?'
      assert Bloodhound.method_traced?('sniff'),
        'Bloodhound#sniff not found by' \
        'NewRelic::Agent::MethodTracer::ClassMethods::AddMethodTracer.method_traced?'
    end
  end

  # All supported Rails versions have the default value for
  # timestamped_migrations as true. Our initializer sets it to false.
  # Test to resolve: https://github.com/newrelic/newrelic-ruby-agent/issues/662

  def test_active_record_initializer_config_change_saved_when_agent_initialized_after_config_initializers
    skip unless defined?(Rails::VERSION)
    # TODO: This test passes in a Rails console in a playground app and in the customer's environment
    # but fails in this unit test context
    skip if Gem::Version.new(NewRelic::VERSION::STRING) >= Gem::Version.new('8.13.0')
    skip 'MySQL error for Rails 3.2' if Rails::VERSION::MAJOR == 3

    with_config(defer_rails_initialization: true) do
      # Verify the configuration value was set to the initializer value
      refute Rails.application.config.active_record.timestamped_migrations,
        "Rails.application.config.active_record.timestamped_migrations equals true, expected false"

      # Verify the configuration value was applied to the ActiveRecord class variable
      if Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new('7.1')
        refute ActiveRecord.timestamped_migrations, "ActiveRecord.timestamped_migrations equals true, expected false"
      else
        refute ActiveRecord::Base.timestamped_migrations,
          "ActiveRecord::Base.timestamped_migrations equals true, expected false"
      end
    end
  end

  def test_active_record_initializer_config_change_not_saved_when_agent_initialized_before_config_initializers
    skip unless defined?(Rails::VERSION)
    skip 'MySQL error for Rails 3.2' if Rails::VERSION::MAJOR == 3

    with_config(defer_rails_initialization: false) do
      # Verify the configuration value was set to the initializer value
      refute Rails.application.config.active_record.timestamped_migrations,
        "Rails.application.config.active_record.timestamped_migrations equals true, expected false"

      # Rails.application.config value should not be applied (this is the state of the original bug)
      if Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new('7.1')
        assert ActiveRecord.timestamped_migrations, "ActiveRecord.timestamped_migrations equals false, expected true"
      else
        refute ActiveRecord::Base.timestamped_migrations,
          "ActiveRecord::Base.timestamped_migrations equals false, expected true"
      end
    end
  end
end
