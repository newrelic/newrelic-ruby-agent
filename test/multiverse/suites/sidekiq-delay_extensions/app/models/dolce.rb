# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'new_relic/agent/datastores'
require 'active_record'

class Dolce < ActiveRecord::Base
	COMPLETION_VAR = :@@nr_job_complete

  def long_running_task
    #NOOP
	ensure
		@@nr_job_complete = true
  end
end
