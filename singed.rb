require 'singed'

Singed.output_directory = Dir.pwd

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

flamegraph { Widget::Evaluator.new.entrypoint }
