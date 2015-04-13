# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class User < ActiveRecord::Base
  has_many :aliases, :dependent => :destroy
  has_and_belongs_to_many :groups
end

class Alias < ActiveRecord::Base
  belongs_to :user
end

class Group < ActiveRecord::Base
  has_and_belongs_to_many :users
end

class Order < ActiveRecord::Base
  has_and_belongs_to_many :shipments, :join_table => 'order_shipments'
end

class Shipment < ActiveRecord::Base
  has_and_belongs_to_many :orders, :join_table => 'order_shipments'
end
