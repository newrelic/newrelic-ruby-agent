# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class CreateDolces < ActiveRecord::Migration[8.0]
  def change
    create_table(:dolces) do |t|
      t.timestamps
    end
  end
end
