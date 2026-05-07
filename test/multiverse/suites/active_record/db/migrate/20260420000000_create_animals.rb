# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../../../test/new_relic/multiverse_helpers'

class CreateAnimals < current_active_record_migration_version
  def self.up
    create_table(:animals) do |t|
      t.string(:type)
      t.string(:name)
      t.timestamps
    end
  end

  def self.down
    drop_table(:animals)
  end
end
