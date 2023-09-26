# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

def redefine_mysql_primary_key(const_str)
  const = Object.const_get(const_str) rescue return
  const[:primary_key] = 'int(11) auto_increment PRIMARY KEY'
end

begin
  # disable the environment check that would otherwise raise
  # ActiveRecord::EnvironmentMismatchError when switching between the
  # default_env and test environments
  ENV['DISABLE_DATABASE_ENVIRONMENT_CHECK'] = 'true'

  load('Rakefile')
  Rake::Task['db:drop'].invoke
  Rake::Task['db:create'].invoke
  Rake::Task['db:migrate'].invoke
rescue => e
  puts e
  puts e.backtrace.join("\n\t")
  raise
end

class Minitest::Test
  def after_teardown
    super
    User.delete_all if defined?(User)
    Alias.delete_all if defined?(Alias)
    Order.delete_all if defined?(Order)
    Shipment.delete_all if defined?(Shipment)
  end
end
