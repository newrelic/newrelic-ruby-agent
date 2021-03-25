# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.

module NewRelic::Agent::Instrumentation
  module RackHelpers
    def self.version_supported?
      rack_version_supported? || puma_rack_version_supported?
    end

    def self.rack_version_supported?
      return false unless defined? ::Rack

      version = Gem::Version.new(::Rack.release)
      min_version = Gem::Version.new('1.1.0')
      version >= min_version
    end

    def self.puma_rack_version_supported?
      return false unless defined? ::Puma::Const::PUMA_VERSION

      version = Gem::Version.new(::Puma::Const::PUMA_VERSION)
      min_version = Gem::Version.new('2.12.0')
      version >= min_version
    end

    def self.middleware_instrumentation_enabled?
      version_supported? && !::NewRelic::Agent.config[:disable_middleware_instrumentation]
    end
  end
end

