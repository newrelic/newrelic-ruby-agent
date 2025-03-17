# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/datastores'

class Dolce < ActiveRecord::Base
	def long_method
			puts "Running long method with dolce test"
	end
end