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
