# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# Let ActiveSupport's auto-loading make sure the testing gateway's there.
# require complains of redefine on certain Rubies, (looking at you REE)
ActiveMerchant::Billing::BogusGateway

OPERATIONS = [:authorize, :purchase, :credit, :recurring, :capture, :update]

class ActiveMerchant::Billing::BogusGateway
  # Testing class doesn't have this, but we instrument it for other gateways
  def update(*_)
  end
end

class BadGateway < ActiveMerchant::Billing::BogusGateway
  def purchase(*args)
    super *args
    raise StandardError.new "whoops!"
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
  OPERATIONS.each do |operation|
    if ActiveMerchant::Billing::BogusGateway.new.respond_to?(operation)
      define_method("test_#{operation}") do
        assert_merchant_transaction(operation)
      end
    else
      define_method("test_#{operation}") do
        skip("operation #{operation} does not exist for the Gateway")
      end
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

  def test_noticed_error_at_segment_and_txn_on_error
    expected_error_class = "StandardError"
    txn = nil
    gateway = BadGateway.new
    begin
      in_transaction do |local_txn|
        txn = local_txn
        gateway.send(:purchase, *[100, PAYSOURCE])
      end
    rescue StandardError => e
      # NOP -- allowing span and transaction to notice error
    end
    assert_segment_noticed_error txn, /ActiveMerchant\/gateway/, expected_error_class, /whoops/i
    assert_transaction_noticed_error txn, expected_error_class
  end

  def test_noticed_error_only_at_segment_on_error
    expected_error_class = "StandardError"
    txn = nil
    gateway = BadGateway.new
    in_transaction do |local_txn|
      txn = local_txn
      begin
        gateway.send(:purchase, *[100, PAYSOURCE])
      rescue StandardError => e
        # NOP -- allowing ONLY span to notice error
      end
    end

    assert_segment_noticed_error txn, /ActiveMerchant\/gateway/, expected_error_class, /whoops/i
    refute_transaction_noticed_error txn, expected_error_class
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
    assert_metrics_recorded([
      [ "ActiveMerchant/gateway/BogusGateway/#{operation}", "txn"],
        "ActiveMerchant/gateway/BogusGateway",
        "ActiveMerchant/operation/#{operation}"
      ])
  end
end
