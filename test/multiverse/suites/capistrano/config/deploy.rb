# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

set :application, 'test'

# Since Capistrano 3 doesn't allow settings direct from command-line, add any
# settings we want to conditionally toggle from tests in the following manner.
ENV.keys.each do |key|
  if key.match(/NEWRELIC_CAPISTRANO_/)
    name = key.gsub('NEWRELIC_CAPISTRANO_', '').downcase
    set "newrelic_#{name}".to_sym, ENV[key]
  end
end
