require 'fileutils'
module NewRelic
  class DataSerialization
    module ClassMethods
      def should_send_data?
        NewRelic::Control.instance.disable_serialization? || (File.size(file_path) >= max_size)
      rescue Exception => e
        # This is not what we really should do here, but the fail-safe
        # behavior is to do what the older agent did: send data every
        # time we think we might want to send data.
        true
      end
      
      def read_and_write_to_file
        with_locked_store do |f|
          result = (yield get_data_from_file(f))
          f.rewind
          f.write(dump(result)) if result
        end
      end

      private

      def open_arguments
        if defined?(Encoding)
          [file_path, File::RDWR | File::CREAT, {:internal_encoding => nil}]
        else
          [file_path, File::RDWR | File::CREAT]
        end
      end
      
      def with_locked_store
        File.open(*open_arguments) do |f|
          f.flock(File::LOCK_EX)
          begin
            yield(f)
          ensure
            f.flock(File::LOCK_UN)
          end
        end
      rescue Exception => e
        NewRelic::Control.instance.log.error("Error serializing data to disk: #{e.inspect}")
        NewRelic::Control.instance.log.debug(e.backtrace.split("\n"))
      end

      def get_data_from_file(f)
        data = f.read
        result = load(data)
        f.truncate(0)
        result
      end
      
      def max_size
        10_000
      end

      def create_file_if_needed
        FileUtils.touch(file_path) unless File.exists?(file_path)
      end

      def dump(object)
        Marshal.dump(object)
      end

      def load(dump)
        Marshal.load(dump)
      rescue ArgumentError => e
        nil
      end

      def truncate_file
        create_file_if_needed
        File.truncate(file_path, 0)
      end

      def file_path
        # TODO get configuration from main control
        './log/newrelic_agent_store.db'
      end
    end
    extend ClassMethods
  end
end

