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
      @parts = version_string.split('.').map{|n| n.to_i }
      @major_version, @minor_version, @tiny_version = (version_string.split('.') + %w[0 0 0]).map(&:to_i)
    end
    def major_version; @parts[0]; end
    def minor_version; @parts[1]; end
    def tiny_version; @parts[2]; end
    
    def <=>(other)
      self.scalar_value <=> other.scalar_value 
    end
    
    def eql?(other)
      return self.scalar_value == other.scalar_value rescue nil
    end
    
    def to_s
      @parts.join(".")
    end
    def scalar_value
      if !@scalar_value
        bits = 24
        @scalar_value = @parts.inject(0) do | value, part |
          bits -= 6
          value + (part << bits)
        end
      end
      @scalar_value
    end
    alias hash scalar_value
  end
end