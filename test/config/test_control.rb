# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/control/frameworks/rails'
require 'new_relic/control/frameworks/rails3'
require 'new_relic/control/frameworks/rails4'

if defined?(::Rails)
  parent_class = case ::Rails::VERSION::MAJOR.to_i
  when 4
    NewRelic::Control::Frameworks::Rails4
  when 3
    NewRelic::Control::Frameworks::Rails3
  end
end
parent_class ||= NewRelic::Control::Frameworks::Rails

class NewRelic::Control::Frameworks::Test < parent_class
  def env
    'test'
  end

  def app
    if defined?(::Rails) && defined?(::Rails::VERSION)
      if ::Rails::VERSION::MAJOR.to_i == 4
        :rails4
      elsif ::Rails::VERSION::MAJOR.to_i == 3
        :rails3
      else
        :rails
      end
    else
      :test
    end
  end

  # Add the default route in case it's missing.  Need it for testing.
  def install_devmode_route
    super
    ActionController::Routing::RouteSet.class_eval do
      return if defined? draw_without_test_route
      def draw_with_test_route
        draw_without_test_route do | map |
          map.connect ':controller/:action/:id'
          yield map
        end
      end
      alias_method_chain :draw, :test_route
    end
    # Force the routes to be reloaded
    ActionController::Routing::Routes.reload!
  end
end
