class CreateDolces < ActiveRecord::Migration[8.0]
  def change
    create_table :dolces do |t|
      t.timestamps
    end
  end
end
