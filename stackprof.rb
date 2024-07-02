#!/usr/bin/env ruby
# frozen_string_literal: true

require 'stackprof'
require 'fileutils'

FileUtils.rm_f('stack_prof.dump')
FileUtils.rm_f('stack_prof.flame')

module Widget
  class Evaluator
    def entrypoint
      numbercrunch
      hotwire
      permutate
    end

    def numbercrunch
      loopdeloop
      sleep "0.#{rand(100..200)}".to_f
    end

    def loopdeloop
      sleep "0.#{rand(100..200)}".to_f
    end

    def hotwire
      sleep "0.#{rand(100..200)}".to_f
    end

    def permutate
      reverse
      sleep "0.#{rand(100..200)}".to_f
    end

    def reverse
      flip
      steer
      sleep "0.#{rand(100..200)}".to_f
    end

    def flip
      sleep "0.#{rand(100..200)}".to_f
    end

    def steer
      sleep "0.#{rand(100..200)}".to_f
    end
  end
end

StackProf.run(mode: :wall, out: 'stackprof.dump', raw: true) { Widget::Evaluator.new.entrypoint }

# `bundle exec stackprof --flamegraph stackprof.dump > stackprof.flame`
`bundle exec stackprof --d3-flamegraph stackprof.dump > stackprof.html`
`bundle exec open stackprof.html`
