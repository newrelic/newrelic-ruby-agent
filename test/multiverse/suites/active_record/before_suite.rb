# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

output = `bundle exec rake db:create db:migrate`
puts output if ENV["VERBOSE"]

require 'active_record'
require 'erb'

require File.expand_path('config/database')

class Minitest::Test
  def after_teardown
    super
    User.delete_all
    Alias.delete_all
    Order.delete_all
    Shipment.delete_all
  end
end
