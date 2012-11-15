module Multiverse
  module Runner
    extend self
    extend Color

    def exit_status
      @exit_status ||= 0
    end

    def notice_exit_status(i)
      exit_status # initialize it
      # we don't want to return exit statuses > 256 since these get converted
      # to 0
      if i != 0
        puts red("FAIL! Exited #{i}")
        @exit_status = 1
      else
        puts green("PASS. Exited #{i}")
      end
      @exit_status
    end

    def run(filter="")
      Dir.new(SUITES_DIRECTORY).entries.each do |dir|
        next if dir =~ /\A\./
        next unless dir.include? filter
        full_path = File.join(SUITES_DIRECTORY, dir)
        begin
          suite = Suite.new full_path
          suite.execute
        rescue => e
          puts red("Error when trying to run suite in #{full_path.inspect}")
          puts
          puts "#{e.class}: #{e}"
          puts *e.backtrace
          notice_exit_status 1
        end
      end

      OutputCollector.report
      exit exit_status
    end
  end
end
