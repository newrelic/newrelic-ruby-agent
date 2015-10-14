# this is a bit ugly, but Puma::Rack::Bundler isn't required by puma unless it's
# the it's running as a webserver. This terrible hack is to install our instrumentation
# for these tests since our requests aren't served by an actual Puma webserver.
if NewRelic::Agent::Instrumentation::RackHelpers.puma_rack_version_supported? &&
    !defined? Puma::Rack::Builder
  require 'puma/rack/builder'
  DependencyDetection.detect!
end
