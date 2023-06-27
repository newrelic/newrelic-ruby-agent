# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Multiverse
  class Clobber
    EXECUTABLES = {mysql: %w[mysql],
                   postgresql: %w[awk dropdb psql]}
    LIST_COMMANDS = {mysql: %(echo "show databases" | mysql -u root),
                     postgresql: %(echo '\\l' |psql -d postgres|awk '{print $1}')}
    PARTIALDATABASE_NAME = 'multiverse'
    DB_NAME_PLACEHOLDER = 'DATABASE_NAME'
    DROP_COMMANDS = {mysql: %Q(echo "drop database #{DB_NAME_PLACEHOLDER} | mysql -u root),
                     postgresql: %Q(dropdb #{DB_NAME_PLACEHOLDER})}

    def remove_local_multiverse_databases(db_type)
      check_database_prerequisites(db_type)
      remove_databases(db_type)
    end

    def remove_generated_gemfiles
      puts 'Removing Multiverse Gemfile* files...'
      file_path = File.expand_path('test/multiverse/suites')
      Dir.glob(File.join(file_path, '**', 'Gemfile*')).each do |fn|
        puts "Removing #{fn.gsub(file_path, '.../suites')}"
        FileUtils.rm(fn)
      end
    end

    def remove_generated_gemfile_lockfiles
      puts 'Removing env Gemfile.lock files...'
      file_path = File.expand_path('test/environments')
      Dir.glob(File.join(file_path, '**', 'Gemfile.lock')).each do |fn|
        puts "Removing #{fn.gsub(file_path, '.../environments')}"
        FileUtils.rm(fn)
      end
    end

    private

    def check_database_prerequisites(db_type)
      seen = []
      executables = EXECUTABLES[db_type]
      puts "Checking for prerequisite executables for #{db_type} (#{EXECUTABLES[db_type]})..."
      ENV['PATH'].split(':').each do |path|
        EXECUTABLES[db_type].each do |executable|
          seen << executable if File.executable?(File.join(path, executable))
        end
      end

      missing = EXECUTABLES[db_type] - seen
      return if missing.empty?

      raise "Unable to locate the following executables in your PATH: #{missing}"
    end

    def remove_databases(db_type)
      databases_list(db_type).each { |database| drop_database(db_type, database) }
    end

    def databases_list(db_type)
      puts "Obtaining a list of #{db_type} databases..."
      `#{LIST_COMMANDS[db_type]}`.chomp!.split("\n").select { |s| s.include?(PARTIALDATABASE_NAME) }
    rescue => e
      puts "ERROR: Cannot get #{db_type} databasesi - #{e.class}: #{e.message}"
      []
    end

    def drop_database(db_type, db_name)
      puts "Dropping #{db_type} database '#{db_name}'..."
      cmd = DROP_COMMANDS[db_type].sub(DB_NAME_PLACEHOLDER, db_name)
      `#{cmd}`
    rescue
      puts "ERROR: Failed to drop #{db_type} database '#{db_name}' - #{e.class}: #{e.message}"
    end
  end
end
