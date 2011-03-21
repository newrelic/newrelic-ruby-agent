module NewRelic
  class DataSerialization
    def dump(object)
      Marshal.dump(object)
    end

    def dump_to_file(object)
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
      File.truncate(file_path, 0)
    end

    def should_send_data
      (File.size(file_path) >= 10_000)
    end

    def file_path
      './log/newrelic_agent_store.db'
    end
  end
end
