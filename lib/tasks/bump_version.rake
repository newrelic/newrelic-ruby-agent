

namespace :newrelic do
  namespace :version do
    MAJOR = 0
    MINOR = 1
    TINY = 2
    VERSION = {major: MAJOR, minor: MINOR, tiny: TINY}
    @new_version = {}

    desc 'Update version file and changelog to neext version'
    task :bump, [:format] => [] do |t, args|
      type = determine_bump_type
      update_version(type)

      version_string = "#{@new_version[:major]}.#{@new_version[:minor]}.#{@new_version[:tiny]}"
      update_changelog(version_string)
      puts "New version: #{version_string}"
    end

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
      lines = file.split("## ")[1].split("- **")
      return MINOR if lines.any?{ |line| line.include?("Feature:") }
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
end
