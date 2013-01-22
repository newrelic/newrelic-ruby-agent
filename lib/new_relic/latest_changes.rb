#!/usr/bin/ruby

module NewRelic
  module LatestChanges
    def self.default_changelog
      File.join(File.dirname(__FILE__), '..', '..', 'CHANGELOG')
    end

    def self.read(changelog=default_changelog)
      footer = <<'EOS'
See https://github.com/newrelic/rpm/blob/master/CHANGELOG for a full list of
changes.
EOS

      return footer unless File.exists?(changelog) 

      version_count = 0
      changes = []
      File.read(changelog).each_line do |line|
        if line.match(/##\s+v[\d.]+\s+##/)
          version_count += 1
        end
        break if version_count >= 2
        changes << line.chomp
      end

      changes << footer
      change_message =  changes.join("\n")
    end
  end
end
