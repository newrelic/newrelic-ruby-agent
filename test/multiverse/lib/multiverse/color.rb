# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

module Multiverse
  module Color
    def colorize(color_code, content)
      STDOUT.tty? ? "\e[#{color_code}m#{content}\e[0m" : content
    end

    def red(string)
      colorize("0;31;49", string)
    end

    def green(string)
      colorize("0;32;49", string)
    end

    def yellow(string)
      colorize("0;33;49", string)
    end
  end
end
