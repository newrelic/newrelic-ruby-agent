#!/usr/bin/ruby
# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.


module NewRelic
  module VERSION #:nodoc:
    def self.build_version_string(*parts)
      parts.compact.join('.')
    end

    MAJOR = 3
    MINOR = 7
    TINY  = 4

    begin
      require File.join(File.dirname(__FILE__), 'build')
    rescue LoadError => e
      BUILD = nil
    end

    STRING = build_version_string(MAJOR, MINOR, TINY, BUILD)
  end

  # Helper class for managing version comparisons
  class VersionNumber
    attr_reader :parts
    include Comparable
    def initialize(version_string)
      version_string ||= '1.0.0'
      @parts = version_string.split('.').map{|n| n =~ /^\d+$/ ? n.to_i : n}
    end
    def major_version; @parts[0]; end
    def minor_version; @parts[1]; end
    def tiny_version; @parts[2]; end

    def <=>(other)
      other = self.class.new(other) if other.is_a? String
      self.class.compare(self.parts, other.parts)
    end

    def to_s
      @parts.join(".")
    end

    def hash
      @parts.hash
    end

    def eql? other
      (self <=> other) == 0
    end

    private
    def self.compare(parts1, parts2)
      a, b = parts1.first, parts2.first
      case
        when a.nil? && b.nil? then 0
        when a.nil? then b.is_a?(Fixnum) ?  -1 : 1
        when b.nil? then -compare(parts2, parts1)
        when a.to_s == b.to_s then compare(parts1[1..-1], parts2[1..-1])
        when a.is_a?(String) then b.is_a?(Fixnum) ?  -1 : (a <=> b)
        when b.is_a?(String) then -compare(parts2, parts1)
        else # they are both fixnums, not nil
          a <=> b
      end
    end
  end
end
