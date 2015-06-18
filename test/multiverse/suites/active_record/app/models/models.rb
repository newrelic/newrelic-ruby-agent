# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/datastores'

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

  validate :touches_another_datastore

  def touches_another_datastore
    NewRelic::Agent::Datastores.wrap("Memcached", "get") do
      # Fake hitting a cache during validation
    end
  end
end

class Shipment < ActiveRecord::Base
  has_and_belongs_to_many :orders, :join_table => 'order_shipments'
end
