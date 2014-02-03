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
          cpuinfo = proc_try_read('/proc/cpuinfo')
          return unless cpuinfo
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
        proc_try_read('/proc/version')
      end

      # A File.read against /(proc|sysfs)/* can hang with some older Linuxes.
      # See https://bugzilla.redhat.com/show_bug.cgi?id=604887, RUBY-736, and
      # https://github.com/opscode/ohai/commit/518d56a6cb7d021b47ed3d691ecf7fba7f74a6a7
      # for details on why we do it this way.
      def self.proc_try_read(path)
        return nil unless File.exist?(path)
        content = ''
        File.open(path) do |f|
          loop do
            begin
              content << f.read_nonblock(4096)
            rescue EOFError
              break
            rescue Errno::EWOULDBLOCK, Errno::EAGAIN
              content = nil
              break # don't select file handle, just give up
            end
          end
        end
        content
      end
    end
  end
end
