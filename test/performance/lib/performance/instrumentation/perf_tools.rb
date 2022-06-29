# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

module Performance
  module Instrumentation
    class PerfToolsProfile < Instrumentor
      platforms :mri_20, :mri_21

      def self.setup
        require 'tmpdir'
        require 'perftools'
      end

      def before(test, test_name)
        @profile_dir = Dir.mktmpdir('profile')
        @profile_path = File.join(@profile_dir, "profile")
        PerfTools::CpuProfiler.start(@profile_path)
      end

      def after(test, test_name)
        PerfTools::CpuProfiler.stop
        output_profile_path = artifact_path(test, test_name, "dot")
        system("pprof.rb --dot #{@profile_path} >#{output_profile_path}")
        @artifacts << output_profile_path
        FileUtils.remove_entry_secure(@profile_dir)
      end
    end
  end
end
