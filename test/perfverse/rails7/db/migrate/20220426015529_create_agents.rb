# frozen_string_literal: true

class CreateAgents < ActiveRecord::Migration[7.0]
  def change
    create_table :agents do |t|
      t.string :name
      t.string :repository
      t.string :language
      t.integer :stars
      t.integer :forks

      t.timestamps
    end
  end
end
