# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path('../middlewares', __FILE__)
require File.expand_path('../rails3_app/app_rails3_plus', __FILE__)
class RailsMultiverseTest < ActionDispatch::IntegrationTest; end

# a basic active model compliant model we can render
class Foo
  extend ActiveModel::Naming if defined?(ActiveModel::Naming)

  def to_model
    self
  end

  def to_partial_path
    'foos/foo'
  end

  def valid?()      true end
  def new_record?() true end
  def destroyed?()  true end

  def raise_error
    raise 'this is an uncaught model error'
  end

  def errors
    obj = Object.new
    def obj.[](key)         [] end
    def obj.full_messages() [] end
    obj
  end
end
