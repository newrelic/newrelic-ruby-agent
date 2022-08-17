# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../../../test/new_relic/multiverse_helpers'

class CreateOrdersAndShipments < current_active_record_migration_version
  def self.up
    create_table(:orders) do |t|
      t.string(:name)
    end

    create_table(:shipments, :force => true) do |t|
    end

    create_table(:order_shipments, :force => true, :id => false) do |t|
      t.integer(:order_id)
      t.integer(:shipment_id)
    end
  end

  def self.down
    drop_table(:orders)
    drop_table(:shipments)
    drop_table(:order_shipments)
  end
end
