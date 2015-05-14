# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper'))

class NewRelic::Agent::SystemInfoTest < Minitest::Test

  def setup
    @sysinfo = ::NewRelic::Agent::SystemInfo
    @sysinfo.clear_processor_info
  end

  cpuinfo_test_dir = File.join(cross_agent_tests_dir, 'proc_cpuinfo')

  Dir.chdir(cpuinfo_test_dir) do
    Dir.glob("*.txt") do |file|
      if file =~ /^((\d+|X)pack_(\d+|X)core_(\d+|X)logical).txt$/
        test_name = "test_#{$1}"
        test_path = File.join(cpuinfo_test_dir, file)

        num_physical_packages  = $2.to_i
        num_physical_cores     = $3.to_i
        num_logical_processors = $4.to_i
        num_physical_packages  = nil if num_physical_packages  < 1
        num_physical_cores     = nil if num_physical_cores     < 1
        num_logical_processors = nil if num_logical_processors < 1

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

  container_id_test_dir   = File.join(cross_agent_tests_dir, 'docker_container_id')
  container_id_test_cases = load_cross_agent_test(File.join('docker_container_id', 'cases'))

  container_id_test_cases.each do |test_case|
    filename = test_case['filename']
    basename = File.basename(filename, '.txt')
    test_name = "test_container_id_#{basename}"

    define_method(test_name) do
      input = File.read(File.join(container_id_test_dir, filename))
      container_id = @sysinfo.parse_docker_container_id(input)

      message = "Parsed incorrect Docker container ID from #{filename}"
      assert_equal(test_case['containerId'], container_id, message)
    end
  end

  meminfo_test_dir = File.join(cross_agent_tests_dir, 'proc_meminfo')

  Dir.chdir(meminfo_test_dir) do
    Dir.glob("*.txt") do |file|
      if file =~ /^meminfo_(\d+)MB.txt$/
        test_name = "test_#{file}"
        test_path = File.join(meminfo_test_dir, file)

        mem_total_expected = $1.to_f

        define_method(test_name) do
          meminfo = File.read(test_path)

          mem_total_actual = @sysinfo.parse_linux_meminfo_in_mb(meminfo)

          assert_equal(mem_total_expected, mem_total_actual)
        end
      else
        fail "Bad filename: cross_agent_tests/proc_meminfo/#{file}"
      end
    end
  end

  def test_proc_meminfo_unparsable
    assert_nil @sysinfo.parse_linux_meminfo_in_mb("")
  end
end

