# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

require "unicorn"
require "newrelic_rpm"

# copied from test/multiverse/suites/rack/example_app.rb... could probably require_relative and include instead?

# class ExampleApp
#   def call(env)
#     req = Rack::Request.new(env)
#     body = req.params['body'] || 'A barebones rack app.'

#     status = '404' unless req.path == '/'
#     [status || '200', {'Content-Type' => 'text/html', 'ExampleApp' => '0'}, [body]]
#   end
# end

# Unicorn's docs say it specifically looks for config.ru, but we don't use
# that for any of our other tests, so perhaps we don't have to?

class UnicornTest < Minitest::Test
  # test 1:
  # finds unicorn as discovered dispatcher when installed (local_environment.rb)
  # @discovered_dispatcher assigned as unicorn

  # test 2:
  # using forking dispatcher (special_startup.rb)
  # expected message logged:
  # ::NewRelic::Agent.logger.info "Deferring startup of agent reporting thread because unicorn may fork."
end
