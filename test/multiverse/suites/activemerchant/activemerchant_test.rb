# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# Let ActiveSupport's auto-loading make sure the testing gateway's there.
# require complains of redefine on certain Rubies, (looking at you REE)
ActiveMerchant::Billing::BogusGateway

class ActiveMerchant::Billing::BogusGateway
  # Testing class doesn't have this, but we instrument it for other gateways
  def update(*_)
  end
end

require 'newrelic_rpm'

class ActiveMerchantTest < Minitest::Test

  attr_reader :gateway

  include MultiverseHelpers

  setup_and_teardown_agent do
    @gateway = ActiveMerchant::Billing::BogusGateway.new
  end

  # Methods with parameters (money, paysource) can just be added to this list
  [:authorize, :purchase, :credit, :capture, :recurring, :update].each do |operation|
    define_method("test_#{operation}") do
      assert_merchant_transaction(operation)
    end
  end

  # Tests for methods that require more specific parameters should go here
  def test_void
    assert_merchant_transaction(:void, REFERENCE)
  end

  def test_store
    assert_merchant_transaction(:store, PAYSOURCE)
  end

  def test_unstore
    assert_merchant_transaction(:unstore, "1")
  end

  # Helper
  PAYSOURCE = 1
  REFERENCE = 3

  def assert_merchant_transaction(operation, *args)
    in_transaction('txn') do
      # Default arguments if not provided by test
      args = [100, PAYSOURCE] if args.empty?

      gateway.send(operation, *args)
    end
    assert_metrics_recorded([["ActiveMerchant/gateway/BogusGateway/#{operation}", "txn"],
                              "ActiveMerchant/gateway/BogusGateway",
                              "ActiveMerchant/operation/#{operation}"])
  end
end
