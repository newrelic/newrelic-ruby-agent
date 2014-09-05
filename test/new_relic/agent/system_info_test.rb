# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper'))

class NewRelic::Agent::SystemInfoTest < Minitest::Test

  def setup
    @sysinfo = ::NewRelic::Agent::SystemInfo
    @sysinfo.clear_processor_info
  end

  test_dir = File.expand_path(File.join(File.dirname(__FILE__),
                                        '..',
                                        '..',
                                        'fixtures',
                                        'cross_agent_tests',
                                        'proc_cpuinfo'))
  Dir.chdir(test_dir) do
    Dir.glob("*.txt") do |file|
      if file =~ /^((\d+)pack_(\d+)core(_hyper)?).txt$/
        test_name = "test_#{$1}"
        test_path = File.join(test_dir, file)
        is_hyperthreaded = !!$4

        num_physical_packages  = $2.to_i
        num_physical_cores     = $3.to_i * num_physical_packages
        num_logical_processors = num_physical_cores * (is_hyperthreaded ? 2 : 1)

        define_method(test_name) do
          cpuinfo = File.read(test_path)

          info = @sysinfo.parse_cpuinfo(cpuinfo)

          assert_equal(num_physical_packages , info[:num_physical_packages ])
          assert_equal(num_physical_cores    , info[:num_physical_cores    ])
          assert_equal(num_logical_processors, info[:num_logical_processors])
        end
      else
        fail "Bad filename: cross_agent_tests/proc_cpuinfo/#{file}"
      end
    end
  end

end

