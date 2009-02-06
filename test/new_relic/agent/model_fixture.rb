# A test model object 
# Be sure and call setup and teardown
class NewRelic::Agent::ModelFixture < ActiveRecord::Base
  self.table_name = 'test_data'
  def self.setup
    connection.create_table :test_data, :force => true do |t|
      t.column :name, :string
    end
  end
  
  def self.teardown
    connection.drop_table :test_data
  end
  
end
