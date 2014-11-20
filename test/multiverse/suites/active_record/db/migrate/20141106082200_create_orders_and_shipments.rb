# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class CreateOrdersAndShipments < ActiveRecord::Migration
  def self.up
    create_table :orders do |t|
      t.string :name
    end

    create_table :shipments, :force => true do |t|
    end

    create_table :order_shipments, :force => true, :id => false do |t|
      t.integer :order_id
      t.integer :shipment_id, :integer
    end
  end

  def self.down
    drop_table :orders
    drop_table :shipments
    drop_table :order_shipments
  end
end
