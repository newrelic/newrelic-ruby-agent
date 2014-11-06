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
  end
end
