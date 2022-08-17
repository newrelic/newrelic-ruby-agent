# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../../../test/new_relic/multiverse_helpers'

class AddTimestampsToOrders < current_active_record_migration_version
  def self.up
    change_table(:orders) do |t|
      t.timestamps
    end
  end

  def self.down
    remove_column(:orders, :updated_at)
    remove_column(:orders, :created_at)
  end
end
