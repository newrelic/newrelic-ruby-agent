# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class Result
    attr_reader :test_name, :measurements, :tags, :timer, :artifacts
    attr_accessor :exception

    def initialize(test_case, test_name)
      @test_case = test_case
      @test_name = test_name
      @measurements   = {}
      @tags           = {}
      @timer = Timer.new
      @artifacts = []
    end

    def exception_to_hash(e)
      return nil if e.nil?
      {
        :class     => e.class,
        :message   => e.message,
        :backtrace => e.backtrace
      }
    end

    def exception_from_hash(h)
      return nil if h.nil?
      e = h[:class].new(h[:message])
      e.set_backtrace(h[:backtrace])
      e
    end

    def marshal_dump
      [
        @test_case,
        @test_name,
        @measurements,
        @tags,
        exception_to_hash(@exception),
        @timer,
        @artifacts
      ]
    end

    def marshal_load(array)
      @test_case    = array.shift
      @test_name    = array.shift
      @measurements = array.shift
      @tags         = array.shift
      @exception    = exception_from_hash(array.shift)
      @timer        = array.shift
      @artifacts    = array.shift
    end

    def elapsed=(elapsed)
      @elapsed = elapsed
    end

    def elapsed
      @elapsed || @timer.elapsed
    end

    def failure?
      elapsed.nil? || !@exception.nil?
    end

    def suite_name
      @test_case.is_a?(String) ? @test_case : @test_case.name
    end

    def identifier
      "#{suite_name}##{@test_name}"
    end

    def measurements_hash
      @measurements.merge(:elapsed => elapsed)
    end

    def to_h
      {
        "suite"     => suite_name,
        "name"      => @test_name,
        "measurements" => measurements_hash,
        "tags"         => @tags,
        "exception"    => exception_to_hash(@exception),
        "artifacts"    => @artifacts
      }
    end

    def self.from_hash(hash)
      elapsed = hash['measurements'].delete('elapsed')
      result = self.new(hash['suite'], hash['name'])
      result.measurements.merge! hash['measurements']
      result.tags.merge! hash['tags']
      result.exception = result.exception_from_hash(hash['exception']) if hash['exception']
      result.elapsed = elapsed
      result
    end

    def inspect
      "<Performance::Result #{identifier}: #{elapsed} s, results=#{@results.inspect}>"
    end
  end
end
