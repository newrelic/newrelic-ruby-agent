# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'time'

module Performance
  class Result
    attr_reader :test_name, :measurements, :tags, :timer, :artifacts
    attr_accessor :exception, :iterations

    def initialize(test_case, test_name)
      @test_case = test_case
      @test_name = test_name
      @measurements   = {}
      @tags           = {}
      @timer = Timer.new
      @iterations = 0
      @artifacts  = []
    end

    def exception=(e)
      if e.is_a?(Exception)
        @exception = {
          'class'     => e.class.name,
          'message'   => e.message,
          'backtrace' => e.backtrace
        }
      else
        @exception = e
      end
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

    def format_timestamp(t)
      t.utc.iso8601
    end

    def ips
      @iterations.to_f / elapsed
    end

    def time_per_iteration
      elapsed / @iterations.to_f
    end

    def to_h
      h = {
        "suite"        => suite_name,
        "name"         => @test_name,
        "measurements" => measurements_hash,
        "tags"         => @tags,
        "iterations"   => @iterations
      }
      h['exception'] = @exception if @exception
      h['artifacts'] = @artifacts if @artifacts && !@artifacts.empty?
      h['started_at']  = format_timestamp(@timer.start_timestamp) if @timer.start_timestamp
      h['finished_at'] = format_timestamp(@timer.stop_timestamp) if @timer.stop_timestamp
      h
    end

    def self.from_hash(hash)
      elapsed = hash['measurements'].delete('elapsed')
      result = self.new(hash['suite'], hash['name'])
      hash['measurements'].each do |key, value|
        result.measurements[key.to_sym] = value
      end
      result.tags.merge! hash['tags']
      result.exception = hash['exception']
      result.elapsed = elapsed
      result.iterations = hash['iterations']
      result.timer.start_timestamp = Time.iso8601(hash['started_at']) if hash['started_at']
      result.timer.stop_timestamp = Time.iso8601(hash['finished_at']) if hash['finished_at']
      result
    end

    def inspect
      "<Performance::Result #{identifier}: #{elapsed} s, results=#{@results.inspect}>"
    end
  end
end
