# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.
# frozen_string_literal: true

module NewRelic
  PRIORITY_PRECISION = 6

  NEWRELIC_KEY = "newrelic"
  CANDIDATE_NEWRELIC_KEYS = [
    NEWRELIC_KEY,
    'NEWRELIC',
    'NewRelic',
    'Newrelic'
  ].freeze


end
