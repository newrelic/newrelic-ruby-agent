# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

def redefine_mysql_primary_key const_str
  const = Object.const_get const_str rescue return
  const[:primary_key] = "int(11) auto_increment PRIMARY KEY"
end

# MySql 5.7 and later no longer support NULL in primary keys
# This overrides the default definition mysql2 adapter emits
# to remove the NULL keyword from the PK declaration.
if defined? ::Mysql2
  require 'active_record'
  require 'active_record/connection_adapters/mysql2_adapter'

  redefine_mysql_primary_key "::ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::NATIVE_DATABASE_TYPES"
  redefine_mysql_primary_key "::ActiveRecord::ConnectionAdapters::Mysql2Adapter::NATIVE_DATABASE_TYPES"
end

begin
  load 'Rakefile'
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
    User.delete_all
    Alias.delete_all
    Order.delete_all
    Shipment.delete_all
  end
end

