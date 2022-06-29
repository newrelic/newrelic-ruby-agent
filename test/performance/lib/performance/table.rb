# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  class Table
    class Formatter
      attr_reader :name

      def initialize(name, format_string = nil, &blk)
        @name = name
        @format_string = format_string
        @format_proc = blk
      end

      def measure(value)
        format(value).size
      end

      def format(value, width = nil)
        formatted = if @format_string
          sprintf(@format_string, value)
        elsif @format_proc
          @format_proc.call(value)
        else
          value.to_s
        end

        formatted = justify(value, formatted, width) if width
        formatted
      end

      def justify(value, formatted, width)
        case value
        when Numeric then formatted.rjust(width)
        else formatted.ljust(width)
        end
      end
    end

    class Builder
      attr_reader :formatters

      def initialize
        @formatters = []
      end

      def column(name, format_string = nil, &blk)
        @formatters << Formatter.new(name, format_string, &blk)
      end
    end

    def initialize(rows, options, &blk)
      @rows = rows
      @options = options

      builder = Builder.new
      builder.instance_eval(&blk)
      @schema = builder.formatters
    end

    def column_widths
      widths = Array.new(@schema.size, 0)
      @schema.each_with_index do |col, idx|
        widths[idx] = col.name.to_s.size
      end
      @rows.each do |row|
        row.each_with_index do |cell, idx|
          width = @schema[idx].measure(cell)
          widths[idx] = [widths[idx], width].max
        end
      end
      widths
    end

    def render_row(parts)
      "| " + parts.join(" | ") + " |"
    end

    def left_corner
      @options[:markdown] ? '--' : '+-'
    end

    def right_corner
      @options[:markdown] ? '--' : '-+'
    end

    def delimiter
      @options[:markdown] ? '-|-' : '-+-'
    end

    def render
      widths = column_widths

      blanks = widths.map { |w| "-" * w }
      top = left_corner + blanks.join(delimiter) + right_corner
      separator = '|-' + blanks.join(delimiter) + '-|'
      bottom = left_corner + blanks.join(delimiter) + right_corner

      text_rows = []

      headers = @schema.zip(widths).map { |(c, w)| c.name.to_s.ljust(w) }
      text_rows << render_row(headers)

      @rows.each do |row|
        parts = []
        row.each_with_index do |v, i|
          parts << @schema[i].format(v, widths[i])
        end
        text_rows << render_row(parts)
      end

      if @options[:markdown]
        text_rows.insert(1, separator)
        puts text_rows.join("\n")
      else
        puts top + "\n"
        puts text_rows.join("\n" + separator + "\n")
        puts bottom + "\n"
      end
    end
  end
end
