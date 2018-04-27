# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class CreateGroups < ActiveRecord::VERSION::STRING >= "5.0.0" ? ActiveRecord::Migration[5.0] : ActiveRecord::Migration
  def self.up
    create_table :groups do |t|
      t.string :name
    end

    create_table :groups_users, :id => false do |t|
      t.integer :group_id, :integer
      t.integer :user_id,  :integer
    end
  end

  def self.down
    drop_table :groups
    drop_table :groups_users
  end
end
