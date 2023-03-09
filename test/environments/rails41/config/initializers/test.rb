# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/method_tracer'

class Bloodhound < ActiveRecord::Base
  include ::NewRelic::Agent::MethodTracer

  def sniff
    puts 'When a bloodhound sniffs a scent article (a piece of clothing or item touched only by the subject),' \
    "air rushes through its nasal cavity and chemical vapors — or odors — lodge in the mucus and bombard the dog's scent receptors. " \
    'Source: https://www.pbs.org/wnet/nature/underdogs-the-bloodhounds-amazing-sense-of-smell/350/'
  end

  add_method_tracer :sniff
end

Rails.application.config.active_record.timestamped_migrations = false
