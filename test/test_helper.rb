# frozen_string_literal: true

# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# define special constant so DefaultSource.framework can return :test
module NewRelic; TEST = true; end unless defined? NewRelic::TEST

ENV['RAILS_ENV'] = 'test'

$: << File.expand_path('../../lib', __FILE__)
$: << File.expand_path('../../test', __FILE__)
$: << File.expand_path('../../ui/helpers', __FILE__) # TODO remove after #1493 merges
$:.uniq!

require 'rubygems'
require 'rake'

require 'minitest/autorun'
require 'mocha/setup'

require 'hometown'
Hometown.watch(::Thread)

Dir[File.expand_path('../helpers/*', __FILE__)].each {|f| require f.sub(/.*test\//,'')}

# We can speed things up in tests that don't need to load rails.
# You can also run the tests in a mode without rails.  Many tests
# will be skipped.
if ENV["NO_RAILS"]
  puts "Running tests in standalone mode without Rails."
  require 'newrelic_rpm'
else
  begin
    require './config/environment'
    require 'newrelic_rpm'
  rescue LoadError
    puts "Running tests in standalone mode."

    require 'bundler'
    Bundler.require

    require 'rails/all'
    require 'newrelic_rpm'

    # Bootstrap a basic rails environment for the agent to run in.
    class MyApp < Rails::Application
      config.active_support.deprecation = :log
      config.secret_token = "49837489qkuweoiuoqwehisuakshdjksadhaisdy78o34y138974xyqp9rmye8yrpiokeuioqwzyoiuxftoyqiuxrhm3iou1hrzmjk"
      config.after_initialize do
        NewRelic::Agent.manual_start
      end
    end
    MyApp.initialize!
  end
end

# This is the public method recommended for plugin developers to share our
# agent helpers. Use it so we don't accidentally break it.
NewRelic::Agent.require_test_helper
