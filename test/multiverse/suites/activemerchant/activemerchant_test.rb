# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Let ActiveSupport's auto-loading make sure the testing gateway's there.
# require complains of redefine on certain Rubies, (looking at you REE)
ActiveMerchant::Billing::BogusGateway

require 'newrelic_rpm'

require File.join(File.dirname(__FILE__), '..', '..', '..', 'agent_helper.rb')
require 'multiverse_helpers'

class ActiveMerchantTest < Minitest::Test

  attr_reader :gateway

  include MultiverseHelpers

  setup_and_teardown_agent do
    @gateway = ActiveMerchant::Billing::BogusGateway.new
  end

  # Methods with parameters (money, paysource) can just be added to this list
  [:authorize, :purchase, :credit, :capture, :recurring].each do |operation|
    define_method("test_#{operation}") do
      assert_merchant_transaction(operation)
    end
  end

  # Tests for methods that require more specific parameters should go here
  def test_void
    assert_merchant_transaction(:void) do
      gateway.void(REFERENCE)
    end
  end

  # Helper
  PAYSOURCE = 1
  REFERENCE = 3

  def assert_merchant_transaction(operation)
    in_transaction('txn') do
      if block_given?
        yield
      else
        gateway.send(operation, 100, PAYSOURCE)
      end
    end
    assert_metrics_recorded([["ActiveMerchant/gateway/BogusGateway/#{operation}", "txn"],
                              "ActiveMerchant/gateway/BogusGateway",
                              "ActiveMerchant/operation/#{operation}"])
  end
end
