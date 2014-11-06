# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

class User < ActiveRecord::Base
  include NewRelic::Agent::MethodTracer
  has_many :aliases

  add_method_tracer :save!
  add_method_tracer :persisted?
end

class Alias < ActiveRecord::Base
  include NewRelic::Agent::MethodTracer

  add_method_tracer :save!
  add_method_tracer :persisted?
  add_method_tracer :destroyed?
end

class Order < ActiveRecord::Base
  has_and_belongs_to_many :shipments, :join_table => 'order_shipments'
end

class Shipment < ActiveRecord::Base
  has_and_belongs_to_many :orders, :join_table => 'order_shipments'
end
