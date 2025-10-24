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
