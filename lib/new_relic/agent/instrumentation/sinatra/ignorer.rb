# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Sinatra
        module Ignorer

          def self.registered(app)
            app.set :newrelic_ignore_routes, [] unless app.respond_to?(:newrelic_ignore_routes)
          end

          def newrelic_ignore(*routes)
            settings.newrelic_ignore_routes += routes.map do |r|
              # Ugly sending to private Base#compile, but we want to mimic
              # exactly Sinatra's mapping of route text to regex
              send(:compile, r).first
            end
          end
        end
      end
    end
  end
end
