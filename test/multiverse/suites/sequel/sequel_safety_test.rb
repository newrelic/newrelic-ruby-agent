# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# https://newrelic.atlassian.net/browse/RUBY-1123
# https://support.newrelic.com/tickets/42515

require File.join(File.dirname(__FILE__), 'database.rb')

class SequelSafetyTest < Minitest::Test

  def test_it_doesnt_blow_up
    require 'newrelic_rpm'

    u = User.create( :login => 'jrandom', :firstname => 'J. Random', :lastname => 'Hacquer' )
    assert u.is_a?( User ), "#{u} isn't a User"
  end

  # The oldest version of Sequel that we test against does not define a VERSION
  # constant, or the in_transaction? method, so skip this test for that version.
  if DB.respond_to?(:in_transaction?)
    def test_should_not_clobber_in_transaction
      require 'newrelic_rpm'

      DB.transaction do
        assert_equal(true, DB.in_transaction?)
      end
    end
  end
end
