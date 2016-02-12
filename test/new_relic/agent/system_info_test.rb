# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper'))

class NewRelic::Agent::SystemInfoTest < Minitest::Test
  def setup
    NewRelic::Agent.instance.stats_engine.clear_stats
    @sysinfo = ::NewRelic::Agent::SystemInfo
    @sysinfo.clear_processor_info
  end

  each_cross_agent_test :dir => 'proc_cpuinfo', :pattern => "*.txt" do |file|
    if File.basename(file) =~ /^((\d+|X)pack_(\d+|X)core_(\d+|X)logical).txt$/
      test_name = "test_#{$1}"

      num_physical_packages  = $2.to_i
      num_physical_cores     = $3.to_i
      num_logical_processors = $4.to_i
      num_physical_packages  = nil if num_physical_packages  < 1
      num_physical_cores     = nil if num_physical_cores     < 1
      num_logical_processors = nil if num_logical_processors < 1

      define_method(test_name) do
        cpuinfo = File.read(file)

        info = @sysinfo.parse_cpuinfo(cpuinfo)

        assert_equal(num_physical_packages , info[:num_physical_packages ])
        assert_equal(num_physical_cores    , info[:num_physical_cores    ])
        assert_equal(num_logical_processors, info[:num_logical_processors])
      end
    elsif File.basename(file) =~ /malformed/
      define_method("test_#{File.basename(file)}") do
        cpuinfo = File.read(file)
        info = @sysinfo.parse_cpuinfo(cpuinfo)
        assert_equal(nil, info[:num_physical_package])
        assert_equal(nil, info[:num_physical_cores])
        assert_equal(nil, info[:num_logical_processors])
      end
    else
      fail "Bad filename: #{file}"
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

      if test_case['expectedMetrics']
        assert_metrics_recorded test_case['expectedMetrics']
      else
        refute_metrics_recorded "Supportability/utilization/docker/error"
      end
    end
  end


  each_cross_agent_test :dir => 'proc_meminfo', :pattern => '*.txt' do |file|
    if File.basename(file) =~ /^meminfo_(\d+)MB.txt$/
      test_name = "test_#{file}"

      mem_total_expected = $1.to_f

      define_method(test_name) do
        meminfo = File.read(file)

        mem_total_actual = @sysinfo.parse_linux_meminfo_in_mib(meminfo)

        assert_equal(mem_total_expected, mem_total_actual)
      end
    else
      fail "Bad filename: cross_agent_tests/proc_meminfo/#{file}"
    end
  end

  def test_proc_meminfo_unparsable
    assert_nil @sysinfo.parse_linux_meminfo_in_mib("")
  end

  def test_ram_in_mb_nil_when_proc_meminfo_unreadable
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("linux")
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/meminfo').returns(nil)
    assert_nil NewRelic::Agent::SystemInfo.ram_in_mib, "Expected ram_in_mib to be nil"
  end

  def test_system_info_darwin_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("darwin13")
    assert NewRelic::Agent::SystemInfo.darwin?, "Expected OS to match darwin"

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("linux")
    refute NewRelic::Agent::SystemInfo.darwin?, "Did not expect OS to match darwin"
  end

  def test_system_info_linux_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("linux")
    assert NewRelic::Agent::SystemInfo.linux?, "Expected OS to match linux"

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("darwin13")
    refute NewRelic::Agent::SystemInfo.linux?, "Did not expect OS to match linux"
  end

  def test_system_info_bsd_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("freebsd")
    assert NewRelic::Agent::SystemInfo.bsd?, "Expected OS to match bsd"

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("darwin13")
    refute NewRelic::Agent::SystemInfo.bsd?, "Did not expect OS to match bsd"
  end

  def test_supportability_metric_recorded_when_docker_id_unavailable
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns("linux")
    cgroup_info = File.read File.join(cross_agent_tests_dir, 'docker_container_id', 'invalid-length.txt')
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/self/cgroup').returns(cgroup_info)
    in_transaction('txn') do
      assert_nil NewRelic::Agent::SystemInfo.docker_container_id
    end
    assert_metrics_recorded "Supportability/utilization/docker/error"
  end
end

