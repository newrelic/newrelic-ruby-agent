# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This file is designed to bootstrap a `Bundler.require`-based Ruby app (such as
# a Ruby on Rails app) so the app can be instrumented and observed by the
# New Relic Ruby agent without the agent being added to the app as a dependency.
# NOTE: introducing the agent into your application via bootstrap is in beta.
# Use at your own risk.
#
# Given a production-ready Ruby app that optionally has a pre-packaged "frozen"
# or "deployment"–gem bundle, the New Relic Ruby agent can be introduced
# to the app without modifying the app and keeping all of the app's content
# read-only.
#
# Prerequisites:
#   - Ruby (tested v2.4+)
#   - Bundler (included with Ruby, tested v1.17+)
#
# Note: The latest version of the New Relic Ruby agent will be used when
# instrumenting your application using this method.
#
# Instructions:
#   - First, make sure the New Relic Ruby agent exists on disk. For these
#     instructions, we'll assume the agent exists at `/newrelic`.
#     - The agent can be downloaded as the "newrelic_rpm" gem from RubyGems.org
#       and unpacked with "gem unpack"
#     - The agent can be cloned from the New Relic public GitHub repo:
#       https://github.com/newrelic/newrelic-ruby-agent
#   - Next, use the "RUBYOPT" environment variable to require ("-r") this
#     file (note that the ".rb" extension is dropped):
#       ```
#       export RUBYOPT="-r /newrelic/lib/boot/strap"
#       ```
#    - Add your New Relic license key as an environment variable.
#       ```
#       export NEW_RELIC_LICENSE_KEY=1a2b3c4d5e67f8g9h0i
#       ```
#   - Launch an existing Ruby app as usual. For a Ruby on Rails app, this might
#     involve running `bin/rails server`.
#   - In the Ruby app's directory, look for and inspect
#     `log/newrelic_agent.log`. If this file exists and there are no "WARN" or
#     "ERROR" entries within it, then the agent was successfully introduced to
#     the Ruby application.

module NRBundlerPatch
  NR_AGENT_GEM = 'newrelic_rpm'

  def require(*_groups)
    super

    require_newrelic
  end

  def require_newrelic
    lib = File.expand_path('../..', __FILE__)
    # $LOAD_PATH.reject! { |path| path.include?('newrelic_rpm') }
    $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
    Kernel.require NR_AGENT_GEM
  end
end

class NRBundlerPatcher
  BUNDLER = 'bundler'
  RUBYOPT = 'RUBYOPT'

  def self.patch
    check_for_require
    check_for_rubyopt
    check_for_bundler
    Bundler::Runtime.prepend(NRBundlerPatch)
  rescue StandardError => e
    Kernel.warn "New Relic entrypoint at #{__FILE__} encountered an issue:\n  #{e.message}"
  end

  private

  def self.check_for_require
    raise "#{__FILE__} is meant to be required, not invoked directly" if $PROGRAM_NAME == __FILE__
  end

  def self.check_for_rubyopt
    unless ENV[RUBYOPT].to_s.match?("-r #{__FILE__.rpartition('.').first}")
      raise "#{__FILE__} is meant to be required via the RUBYOPT env var"
    end
  end

  def self.check_for_bundler
    require_bundler

    raise 'Required Ruby Bundler class Bundler::Runtime not defined!' unless defined?(Bundler::Runtime)

    unless Bundler::Runtime.method_defined?(:require)
      raise "The active Ruby Bundler instance doesn't offer Bundler::Runtime#require"
    end
  end

  def self.require_bundler
    require BUNDLER
  rescue LoadError => e
    raise "Required Ruby library '#{BUNDLER}' could not be required - #{e}"
  end
end

NRBundlerPatcher.patch
