# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class AddTimestampsToOrders < ActiveRecord::Migration
  def self.up
    change_table(:orders) do |t|
      t.timestamps
    end
  end

  def self.down
    remove_column :orders, :updated_at
    remove_column :orders, :created_at
  end
end
