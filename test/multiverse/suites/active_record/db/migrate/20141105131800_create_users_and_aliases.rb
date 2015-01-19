# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class CreateUsersAndAliases < ActiveRecord::Migration
  def self.up
    create_table :users do |t|
      t.string  :name
    end

    create_table :aliases do |t|
      t.integer :user_id
      t.string :aka
    end
  end

  def self.down
    drop_table :users
    drop_table :aliases
  end
end
