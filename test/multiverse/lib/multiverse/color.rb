module Multiverse
  module Color
    def red(string)
      "\e[0;31;49m#{string}\e[0m "
    end
    def green(string)
      "\e[0;32;49m#{string}\e[0m "
    end
    def yellow(string)
      "\e[0;33;49m#{string}\e[0m "
    end
  end
end
