# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

# Agent - model class
class Agent < ApplicationRecord
  def apply_random_values
    self.name = "#{language} Agent"
    self.repository = "newrelic-#{language.downcase}-agent"
    self.stars = rand(1..2000)
    self.forks = rand(1..1000)
  end
end
