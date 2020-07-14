# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path('../middlewares', __FILE__)
require File.expand_path('../rails3_app/app_rails3_plus', __FILE__)

# Rails 5 deprecated support for using non-keyword arguments with the request
# helper methods(get, post, put, etc). The module below is prepended to
# ActionDispatch::Integration::Session for Rails 4 and allows us to write our
# tests with the kwarg style request helpers. This code can be removed in the
# future when / if we ever drop support for Rails 4. See:
# https://github.com/rails/rails/commit/de9542acd56f60d281465a59eac11e15ca8b3323
# for more details

module RequestHelpersCompatibility
  [:get, :post, :put, :patch, :delete, :head].each do |method_name|
    define_method method_name do |path, **args|       # def get path, **args
      super path, args[:params], args[:headers]       #   super path, args[:params], args[:headers]
    end                                               # end
  end
end

if Rails::VERSION::MAJOR.to_i < 5
  ActionDispatch::Integration::Session.send :prepend, RequestHelpersCompatibility
end

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
