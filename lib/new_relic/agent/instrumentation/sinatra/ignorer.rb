# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module NewRelic
  module Agent
    module Instrumentation
      module Sinatra
        module Ignorer

          def self.registered(app)
            app.set :newrelic_ignores, Hash.new([]) unless app.respond_to?(:newrelic_ignores)
          end

          def self.should_ignore?(app, type)
            app.settings.newrelic_ignores[type].any? do |pattern|
              pattern.match(app.request.path_info)
            end
          end

          def newrelic_ignore(*routes)
            set_newrelic_ignore(:routes, *routes)
          end

          def newrelic_ignore_apdex(*routes)
            set_newrelic_ignore(:apdex, *routes)
          end

          def newrelic_ignore_enduser(*routes)
            set_newrelic_ignore(:enduser, *routes)
          end

          private

          def set_newrelic_ignore(type, *routes)
            settings.newrelic_ignores[type] += routes.map do |r|
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
