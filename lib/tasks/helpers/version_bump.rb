# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module VersionBump
  # Updates version.rb with new version number
  def update_version(bump_type)
    file = File.read(File.expand_path('lib/new_relic/version.rb'))
    VERSION.each do |key, current|
      file.gsub!(/(#{key.to_s.upcase} = )(\d+)/) do
        match = Regexp.last_match

        @new_version[key] = if bump_type == current # bump type, increase by 1
          match[2].to_i + 1
        elsif bump_type < current # right of bump type, goes to 0
          0
        else # left of bump type, stays the same
          match[2].to_i
        end

        match[1] + @new_version[key].to_s
      end
    end

    File.write(File.expand_path('lib/new_relic/version.rb'), file)
  end

  # Determind version based on if changelog has a feature or not for version
  def determine_bump_type
    file = File.read(File.expand_path('CHANGELOG.md'))
    lines = file.split('## ')[1].split('- **')
    return MAJOR if lines.first.include?('Major version')
    return MINOR if lines.any? { |line| line.include?('Feature:') }

    TINY
  end

  # Replace dev with version number in changelog
  def update_changelog(version)
    file = File.read(File.expand_path('CHANGELOG.md'))
    file.gsub!(/## dev/, "## v#{version}")
    file.gsub!(/Version <dev>/, "Version #{version}")
    File.write(File.expand_path('CHANGELOG.md'), file)
  end
end
