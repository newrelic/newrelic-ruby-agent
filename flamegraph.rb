#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

FileUtils.rm_rf('flamegraphs')
FileUtils.rm_rf('log')
ENV['NRCONFIG'] = "#{ENV['HOME']}/scratch/flamegraph/newrelic.yml"

require 'new_relic/agent'
require 'tasks/newrelic'


module Widget
  class Evaluator
    include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
    include ::NewRelic::Agent::MethodTracer

    def entrypoint
      2.times { numbercrunch }
      3.times { hotwire }
      2.times { permutate }
    end
    add_transaction_tracer :entrypoint, category: :web

    def numbercrunch
      2.times { loopdeloop }
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :numbercrunch

    def loopdeloop
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :loopdeloop

    def hotwire
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :hotwire

    def permutate
      5.times { reverse }
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :permutate

    def reverse
      4.times { flip }
      2.times { steer }
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :reverse

    def flip
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :flip

    def steer
      sleep "0.#{rand(100..200)}".to_f
    end
    add_method_tracer :steer

    def randomly
      rand(1..10).times { yield }
    end
  end
end

NewRelic::Agent.manual_start

puts 'Observing Ruby...'
Widget::Evaluator.new.entrypoint

puts 'Flame graphing...'
NewRelic::Agent.shutdown

svg = Dir.glob(File.join('flamegraphs', '*.svg')).first
`open #{svg}`
