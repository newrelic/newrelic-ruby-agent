# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative 'config_helpers'

namespace :newrelic do
  namespace :config do
    desc "Describe available New Relic configuration settings."
    task :docs, [:format] => [] do |t, args|
      require File.expand_path(File.join(File.dirname(__FILE__), "..", "new_relic", "agent", "configuration", "default_source.rb"))
      format = args[:format] || "text"
      Config.new.output(format)
    end
  end
end
