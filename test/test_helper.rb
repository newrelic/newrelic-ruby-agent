# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

# define special constant so DefaultSource.framework can return :test
module NewRelic; TEST = true; end unless defined? NewRelic::TEST

ENV['RAILS_ENV'] = 'test'

$: << File.expand_path('../../lib', __FILE__)
$: << File.expand_path('../../test', __FILE__)
$:.uniq!

require 'rubygems'
require 'rake'

require 'minitest/autorun'
require 'minitest/pride' unless ENV['CI']
require 'minitest/stub_const'
require 'mocha/setup'

Dir[File.expand_path('../helpers/*', __FILE__)].each { |f| require f.sub(/.*test\//, '') }

# We can speed things up in tests that don't need to load rails.
# You can also run the tests in a mode without rails.  Many tests
# will be skipped.

if ENV['NO_RAILS']
  puts "Running tests in standalone mode without Rails."
  require 'newrelic_rpm'
else
  begin
    # try loading rails via attempted loading of config/environment.rb
    require './config/environment'
    require 'newrelic_rpm'
    puts "Running in standalone mode with Rails"
  rescue LoadError
    # if there was not a file at config/environment.rb fall back to running without it
    require 'newrelic_rpm'
    puts "Running in standalone mode without Rails"
  end
end

# This is the public method recommended for plugin developers to share our
# agent helpers. Use it so we don't accidentally break it.
NewRelic::Agent.require_test_helper

# If these are set, many tests fail. We delete them from this process.
# This is an example of a test fail: unexpected invocation: #<Mock:0x28438>.sync=(true) (MiniTest::Assertion)
ENV.delete('NEW_RELIC_LICENSE_KEY')
ENV.delete('NEW_RELIC_HOST')
