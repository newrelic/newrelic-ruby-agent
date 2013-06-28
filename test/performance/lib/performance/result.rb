# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Performance
  class Result
    attr_reader :test_name, :details, :timer, :artifacts

    def initialize(test_case, test_name, details={})
      @test_case = test_case
      @test_name = test_name
      @details = details
      @timer = Timer.new
      @artifacts = []
    end

    def marshal_dump
      filtered_details = @details.dup
      if filtered_details[:exception]
        exc = filtered_details[:exception]
        filtered_details[:exception] = {
          :class     => exc.class,
          :message   => exc.message,
          :backtrace => exc.backtrace
        }
      end
      [
        @test_case,
        @test_name,
        filtered_details,
        @timer,
        @artifacts
      ]
    end

    def marshal_load(array)
      @test_case = array.shift
      @test_name = array.shift
      @details   = array.shift
      @timer     = array.shift
      @artifacts = array.shift

      if @details[:exception]
        exc = @details[:exception][:class].new(@details[:exception][:message])
        exc.set_backtrace(@details[:exception][:backtrace])
        @details[:exception] = exc
      end
    end

    def exception
      @details[:exception]
    end

    def elapsed
      @timer.elapsed
    end

    def failure?
      elapsed.nil? || @details[:exception]
    end

    def merge!(hash)
      @details.merge!(hash)
    end

    def identifier
      "#{@test_case.name}##{@test_name}"
    end

    def to_h
      {
        "suite"     => @test_case.name,
        "name"      => @test_name,
        "elapsed"   => elapsed,
        "details"   => @details,
        "artifacts" => @artifacts
      }
    end

    def inspect
      "<Performance::Result #{identifier}: #{elapsed} s, details=#{@details.inspect}>"
    end
  end
end
