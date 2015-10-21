# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# this is a bit ugly, but Puma::Rack::Bundler isn't required by puma unless it's
# running as a webserver. This terrible hack is to install our instrumentation
# for these tests since our requests aren't served by an actual Puma webserver.
if NewRelic::Agent::Instrumentation::RackHelpers.puma_rack_version_supported?
  require 'puma/rack/builder' unless defined? Puma::Rack::Builder
  require 'puma/rack/urlmap' unless defined? Puma::Rack::URLMap
  DependencyDetection.detect!
end
