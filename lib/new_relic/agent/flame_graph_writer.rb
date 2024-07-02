# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require 'fileutils'
require 'tempfile'
require 'time'

module NewRelic
  module Agent
    class FlameGraphWriter
      OUTPUT_PATH = 'flamegraphs'
      ENABLED = true
      PERL_SCRIPT = File.expand_path('../../../vendor/flamegraph.pl', __FILE__)
      WIDTH = 1200
      TITLE = 'NR Client-side Flame Graph Demo'

      def initialize
        return unless ENABLED

        FileUtils.mkdir_p(OUTPUT_PATH)
        @entries = []
        @lock = Mutex.new
      end

      def store(txn)
        return unless ENABLED

        @entries << lines(txn)
      end

      def write
        return unless ENABLED && !@entries.empty?

        temp = Tempfile.new('new_relic_flame_graph_data')

        @lock.synchronize do
          File.open(temp, 'w') { |f| f.puts @entries.join("\n") }
          @entries = []
        end

        `#{script_command(temp)}`
      rescue StandardError => e
        NewRelic::Agent.logger.error("Failed to write flame graph: #{e}")
      ensure
        temp.close
        temp.unlink
      end

      private

      def lines(txn)
        txn.segments.sort_by { |s| s.start_time }.each_with_object([]) do |segment, lines|
          next if segment.guid == txn.initial_segment.guid

          lines << "#{segment.instance_variable_get(:@stack).reverse.join(';')} #{segment.duration}"
        end
      end

      def filename
        File.join(OUTPUT_PATH, "#{Time.now.strftime('%Y-%m-%dT%H_%M_%S')}.svg")
      end

      def file_info(segment)
        "#{File.basename(segment.code_attributes['code.filepath'])}:#{segment.code_attributes['code.lineno']}"
      end

      def chopped(slash_delimited)
        slash_delimited.split('/')[2..-1].join('/')
      end

      def script_command(file)
        "cat #{file.path} | #{PERL_SCRIPT} --countname=ms --colors=aqua --inverted --width=#{WIDTH} " \
          "--title='#{TITLE}' > #{filename}"
      end

      # --colors PALETTE # set color palette. choices are: hot (default), mem,
      #         io, wakeup, chain, java, js, perl, red, green, blue,
      #         aqua, yellow, purple, orange
    end
  end
end
