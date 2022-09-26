# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../../../../../test/new_relic/multiverse_helpers'

class CreateGroups < current_active_record_migration_version
  def self.up
    create_table(:groups) do |t|
      t.string(:name)
    end

    create_table(:groups_users, :id => false) do |t|
      t.integer(:group_id)
      t.integer(:user_id)
    end
  end

  def self.down
    drop_table(:groups)
    drop_table(:groups_users)
  end
end
