#!/usr/bin/ruby
module NewRelic
  module VERSION #:nodoc:
    MAJOR = 2
    MINOR = 9
    TINY  = 0
    STRING = [MAJOR, MINOR, TINY].join('.')
  end
  
  # Helper class for managing version comparisons 
  class VersionNumber
    attr_reader :major_version, :minor_version, :tiny_version
    include Comparable
    def initialize(version_string)
      version_string ||= '1.0.0'
      @major_version, @minor_version, @tiny_version = (version_string.split('.') + %w[0 0 0]).map(&:to_i)
    end
    
    def <=>(other)
      self.scalar_value <=> other.scalar_value 
    end
    
    def eql?(other)
      return self.scalar_value == other.scalar_value rescue nil
    end
    
    def to_s
      "#{major_version}.#{minor_version}.#{tiny_version}"
    end
    def scalar_value
      (major_version << 16) +
      (minor_version << 8) +
      tiny_version
    end
    alias hash scalar_value
  end
end
