require 'fileutils'
module NewRelic
  class DataSerialization
    module ClassMethods
      def create_file_if_needed
        FileUtils.touch(file_path) unless File.exists?(file_path)
      end

      def dump(object)
        Marshal.dump(object)
      end

      def dump_to_file(object)
        create_file_if_needed
        File.open(file_path, 'w') do |f|
          f.write(dump(object))
        end
      end

      def load(dump)
        Marshal.load(dump)
      rescue ArgumentError => e
        nil
      end

      def load_from_file
        File.open(file_path, 'r') do |f|
          load(f.read)
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
        (File.size(file_path) >= 100_000)
      end

      def file_path
        # TODO get configuration from main control
        './log/newrelic_agent_store.db'
      end
    end
    extend ClassMethods
  end
end

