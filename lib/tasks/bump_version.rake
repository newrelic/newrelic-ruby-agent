# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative './helpers/version_bump'
include VersionBump

namespace :newrelic do
  namespace :version do
    MAJOR = 0
    MINOR = 1
    TINY = 2
    VERSION = {major: MAJOR, minor: MINOR, tiny: TINY}
    @new_version = {}

    desc 'Returns the current version'
    task :current do
      puts "#{NewRelic::VERSION::STRING}"
    end

    desc 'Update version file and changelog to neext version'
    task :bump, [:format] => [] do |t, args|
      type = determine_bump_type
      update_version(type)

      version_string = "#{@new_version[:major]}.#{@new_version[:minor]}.#{@new_version[:tiny]}"
      update_changelog(version_string)
      puts "New version: #{version_string}"
    end
  end
end
