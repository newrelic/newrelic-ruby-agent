# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# This file is designed to bootstrap a `Bundler.require` based Ruby app (such as
# a Ruby on Rails app) so that the app can be instrumented and observed by the
# New Relic Ruby agent without the agent being added to the app as a dependency.
#
# Given a production-ready Ruby app that optionally has a pre-packaged "frozen"
# or "deployment" based gem bundle, the New Relic Ruby agent can be introduced
# to the app without modifying the app and keeping all of the app's content
# read-only.
#
# Prerequisites:
#   - Ruby (tested v2.4+)
#   - Bundler (included with Ruby, tested v1.17+)
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
#       export RUBYOPT="-r /newrelic/lib/bootstrap"
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
    lib = File.dirname(__FILE__)
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
  end

  private

  def self.check_for_require
    warn_and_exit "#{__FILE__} is meant to be required, not invoked directly" if $PROGRAM_NAME == __FILE__
  end

  def self.check_for_rubyopt
    unless ENV[RUBYOPT].to_s.match?("-r #{__FILE__.rpartition('.').first}")
      warn_and_exit "#{__FILE__} is meant to be required via the RUBYOPT env var"
    end
  end

  def self.check_for_bundler
    require_bundler

    warn_and_exit 'Required Ruby Bundler class Bundler::Runtime not defined!' unless defined?(Bundler::Runtime)

    unless Bundler::Runtime.method_defined?(:require)
      warn_and_exit "The active Ruby Bundler instance doesn't offer Bundler::Runtime#require"
    end
  end

  def self.require_bundler
    require BUNDLER
  rescue LoadError => e
    warn_and_exit "Required Ruby library '#{BUNDLER}' could not be required - #{e}"
  end

  def self.warn_and_exit(msg)
    warn "New Relic entrypoint at #{__FILE__} encountered an issue:\n\t#{msg}"

    exit 1
  end
end

NRBundlerPatcher.patch
