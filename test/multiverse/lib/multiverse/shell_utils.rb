# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Multiverse
  module ShellUtils
    module_function

    def try_command_n_times(cmd, n)
      count = 0
      loop do
        count += 1
        result = `#{cmd}`
        if $?.success?
          return result
        elsif count < n
          redo
        else
          puts "System command: #{cmd} failed #{n} times. Giving up..."
          return result
        end
      end
    end

  end
end
