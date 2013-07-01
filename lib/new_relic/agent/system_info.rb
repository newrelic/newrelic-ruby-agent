# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

# This module is intended to provide access to information about the host OS and
# [virtual] machine. It intentionally does no caching and maintains no state -
# caching should be handled by clients if needed. Methods should return nil if
# the requested information is unavailable.

require 'rbconfig'

module NewRelic
  module Agent
    module SystemInfo
      def self.ruby_os_identifier
        RbConfig::CONFIG['target_os']
      end

      def self.processor_count
        case ruby_os_identifier
        when /darwin/, /freebsd/
          `sysctl -n hw.ncpu`.to_i
        when /linux/
          cpuinfo = ''
          proc_file = '/proc/cpuinfo'
          File.open(proc_file) do |f|
            loop do
              begin
                cpuinfo << f.read_nonblock(4096).strip
              rescue EOFError
                break
              rescue Errno::EWOULDBLOCK, Errno::EAGAIN
                cpuinfo = ''
                break # don't select file handle, just give up
              end
            end
          end
          processors = cpuinfo.split("\n").select {|line| line =~ /^processor\s*:/ }.size
          processors == 0 ? nil : processors
        end
      rescue
        nil
      end

      def self.processor_arch
        RbConfig::CONFIG['target_cpu']
      end

      def self.os_version
        `uname -v` rescue nil
      end
    end
  end
end
