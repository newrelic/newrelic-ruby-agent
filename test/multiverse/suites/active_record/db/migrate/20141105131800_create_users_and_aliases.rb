# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../../../test/new_relic/multiverse_helpers'

class CreateUsersAndAliases < current_active_record_migration_version
  def self.up
    create_table(:users) do |t|
      t.string(:name, null: false)
    end
    add_index(:users, :name, unique: true)

    create_table(:aliases) do |t|
      t.integer(:user_id)
      t.string(:aka)
    end
  end

  def self.down
    drop_table(:users)
    drop_table(:aliases)
  end
end
