# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

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
