# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# this gem only works on ruby 2.4+
if RUBY_VERSION >= '2.4.0'
  require 'warning'
  Gem.path.each do |path|
    Warning.ignore(//, path)
  end

  # this is to ignore warnings that happen on the CI only
  # the site_ruby part of the path needs to be removed if it exists otherwise the CI keeps doing the warnings
  Warning.ignore(//, Gem::RUBYGEMS_DIR.gsub(/site_ruby\//, ''))
end
