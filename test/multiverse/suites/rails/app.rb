# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require File.expand_path('middlewares', __dir__)
require File.expand_path('rails3_app/app_rails3_plus', __dir__)

# Rails 5 deprecated support for using non-keyword arguments with the request
# helper methods(get, post, put, etc). The module below is prepended to
# ActionDispatch::Integration::Session for Rails 4 and allows us to write our
# tests with the kwarg style request helpers. This code can be removed in the
# future when / if we ever drop support for Rails 4. See:
# https://github.com/rails/rails/commit/de9542acd56f60d281465a59eac11e15ca8b3323
# for more details

module RequestHelpersCompatibility
  %i[get post put patch delete head].each do |method_name|
    define_method method_name do |path, **args|       # def get path, **args
      super path, args[:params], args[:headers]       #   super path, args[:params], args[:headers]
    end                                               # end
  end
end

ActionDispatch::Integration::Session.prepend RequestHelpersCompatibility if Rails::VERSION::MAJOR.to_i < 5

# a basic active model compliant model we can render
class Foo
  extend ActiveModel::Naming if defined?(ActiveModel::Naming)

  def to_model
    self
  end

  def to_partial_path
    'foos/foo'
  end

  def valid?() = true

  def new_record?() = true

  def destroyed?() = true

  def raise_error
    raise 'this is an uncaught model error'
  end

  def errors
    obj = Object.new
    def [](_key) = []

    def full_messages() = []
    obj
  end
end
