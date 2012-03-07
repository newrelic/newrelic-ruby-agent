require 'fileutils'
require 'new_relic/language_support'

module NewRelic
  # Handles serialization of data to disk, to save on contacting the
  # server. Lowers both server and client overhead, if the disk is not overloaded
  class DataSerialization
    include NewRelic::LanguageSupport::DataSerialization
    
    module ClassMethods
      # Check whether the store is too large, too old, or the
      # pid file is too old. If so, we should send the data
      # right away. If not, we presumably store it for later sending
      # (handled elsewhere)
      def should_send_data?
        NewRelic::Control.instance.disable_serialization? || store_too_large? ||
          store_too_old? || pid_too_old? ||
          NewRelic::LanguageSupport.using_version?('1.8.6')
      rescue => e
        NewRelic::Control.instance.disable_serialization = true
        NewRelic::Control.instance.log.warn("Disabling serialization: #{e.message}")
        true
      end

      # A combined locked read/write from the store file - reduces
      # contention by not acquiring the lock and file handle twice
      def read_and_write_to_file
        with_locked_store do |f|
          result = (yield get_data_from_file(f))
          f.rewind
          f.truncate(0)
          write_contents_nonblockingly(f, dump(result)) if result
        end
      rescue Errno::ENOENT => e
        NewRelic::Control.instance.log.warn(e.message)
      end
      
      # touches the age file that determines whether we should send
      # data now or not
      def update_last_sent!
        FileUtils.touch(pid_file_path)
      end
      
      def pid_too_old?
        return true unless File.exists?(pid_file_path)
        age = (Time.now.to_i - File.mtime(pid_file_path).to_i)
        NewRelic::Control.instance.log.debug("Pid was #{age} seconds old, sending data") if age > 60
        age > 60
      end
      
      def store_too_old?
        return true unless File.exists?(file_path)
        age = (Time.now.to_i - File.mtime(file_path).to_i)
        NewRelic::Control.instance.log.debug("Store was #{age} seconds old, sending data") if age > 60
        age > 50
      end      
    
      def store_too_large?
        return true unless File.exists?(file_path)
        size = File.size(file_path) > max_size
        NewRelic::Control.instance.log.debug("Store was oversize, sending data") if size
        size
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
      rescue => e
        NewRelic::Control.instance.log.error("Error serializing data to disk: #{e.inspect}")
        NewRelic::Control.instance.log.debug(e.backtrace.split("\n"))
        # re-raise so that serialization will be disabled higher up the stack
        raise e
      end

      def get_data_from_file(f)
        data = read_until_eof_error(f)
        result = load(data)
        f.truncate(0)
        result
      end

      def write_contents_nonblockingly(f, string)
        result = 0
        while (result < string.length)
          result += f.write_nonblock(string)
        end
      rescue Errno::EAGAIN, Errno::EINTR
        IO.select(nil, [f])
        retry
      end

      def read_until_eof_error(f)
        accumulator = ""
        while(true)
          accumulator << f.read_nonblock(10_000)
        end
      rescue Errno::EAGAIN, Errno::EINTR
        IO.select([f])
        retry
      rescue EOFError
        accumulator
      end
      
      def max_size
        10_000
      end

      def dump(object)
        Marshal.dump(object.clone)
      end
      
      def load(dump)
        if dump.respond_to?(:size) && dump.size == 0
          NewRelic::Control.instance.log.debug("Spool file empty.")
          return nil
        end
        Marshal.load(dump)
      rescue ArgumentError, TypeError => e
        NewRelic::Control.instance.log.error("Error loading data from newrelic_agent_store.db: #{e.inspect}")
        NewRelic::Control.instance.log.debug(e.backtrace.inspect)
        nil
      end
            
      def file_path
        "#{NewRelic::Control.instance.log_path}/newrelic_agent_store.db"
      end

      def pid_file_path
        "#{NewRelic::Control.instance.log_path}/newrelic_agent_store.pid"
      end
    end
    extend ClassMethods
  end
end

