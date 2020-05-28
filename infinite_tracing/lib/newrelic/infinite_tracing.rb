# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

unless defined? NewRelic::Agent::InfiniteTracing
  require_relative '../infinite_tracing'
end