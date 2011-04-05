require 'fileutils'
module NewRelic
  class DataSerialization
    
    def create_file_if_needed
      FileUtils.touch(file_path) unless File.exists?(file_path)
    end
    
    def dump(object)
      Marshal.dump(object)
    end

    def dump_to_file(object)
      create_file_if_needed
      File.open(file_path, 'a') do |f|
        f.puts(dump(object))
      end
    end

    def load(dump)
      Marshal.load(dump)
    end

    def load_from_file
      File.open(file_path, 'r') do |f|
        f.readlines.map do |line|
          load(line)
        end
      end
    rescue EOFError => e
      nil
    end

    def truncate_file
      create_file_if_needed      
      File.truncate(file_path, 0)
    end

    def should_send_data
      # TODO get configuration from main control
      (File.size(file_path) >= 10_000)
    end

    def file_path
      # TODO get configuration from main control
      './log/newrelic_agent_store.db'
    end
  end
end
