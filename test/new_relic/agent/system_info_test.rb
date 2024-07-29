# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

require_relative '../../test_helper'

class NewRelic::Agent::SystemInfoTest < Minitest::Test
  include Mocha::API
  def setup
    NewRelic::Agent.instance.stats_engine.clear_stats
    @sysinfo = ::NewRelic::Agent::SystemInfo
    @sysinfo.clear_processor_info
  end

  each_cross_agent_test :dir => 'proc_cpuinfo', :pattern => '*.txt' do |file|
    if File.basename(file) =~ /^((\d+|X)pack_(\d+|X)core_(\d+|X)logical).txt$/
      test_name = "test_#{$1}"

      num_physical_packages = $2.to_i
      num_physical_cores = $3.to_i
      num_logical_processors = $4.to_i
      num_physical_packages = nil if num_physical_packages < 1
      num_physical_cores = nil if num_physical_cores < 1
      num_logical_processors = nil if num_logical_processors < 1

      define_method(test_name) do
        cpuinfo = File.read(file)

        info = @sysinfo.parse_cpuinfo(cpuinfo)

        if num_physical_packages.nil?
          assert_nil info[:num_physical_packages]
        else
          assert_equal num_physical_packages, info[:num_physical_packages]
        end

        if num_physical_cores.nil?
          assert_nil info[:num_physical_cores]
        else
          assert_equal num_physical_cores, info[:num_physical_cores]
        end

        if num_logical_processors.nil?
          assert_nil info[:num_logical_processors]
        else
          assert_equal num_logical_processors, info[:num_logical_processors]
        end
      end
    elsif File.basename(file).include?('malformed')
      define_method("test_#{File.basename(file)}") do
        cpuinfo = File.read(file)
        info = @sysinfo.parse_cpuinfo(cpuinfo)

        assert_nil(info[:num_physical_package])
        assert_nil(info[:num_physical_cores])
        assert_nil(info[:num_logical_processors])
      end
    else
      fail "Bad filename: #{file}"
    end
  end

  # BEGIN cgroups v1
  container_id_test_dir = File.join(cross_agent_tests_dir, 'docker_container_id')
  container_id_test_cases = load_cross_agent_test(File.join('docker_container_id', 'cases'))

  container_id_test_cases.each do |test_case|
    filename = test_case['filename']
    basename = File.basename(filename, '.txt')
    test_name = "test_container_id_#{basename}"

    define_method(test_name) do
      input = File.read(File.join(container_id_test_dir, filename))
      container_id = @sysinfo.parse_docker_container_id(input)

      message = "Parsed incorrect Docker container ID from #{filename}"
      if test_case['containerId']
        assert_equal test_case['containerId'], container_id, message
      else
        assert_nil container_id, message
      end

      if test_case['expectedMetrics']
        assert_metrics_recorded test_case['expectedMetrics']
      else
        refute_metrics_recorded 'Supportability/utilization/docker/error'
      end
    end
  end
  # END cgroups v1

  # BEGIN cgroups v2
  def test_docker_container_id_is_gleaned_from_mountinfo_for_cgroups_v2
    skip_unless_minitest5_or_above
    container_id = '3145490ee377105a4d3a7abd55083c61c0c2d616d786614e755176433c648d09'
    mountinfo = "line1\nline2\n/docker/containers/#{container_id}/other/content\nline4\nline5"
    NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'linux' do
      NewRelic::Agent::SystemInfo.stub :proc_try_read, mountinfo, %w[/proc/self/mountinfo] do
        assert_equal container_id, NewRelic::Agent::SystemInfo.docker_container_id
      end
    end
  end

  def test_docker_container_id_must_match_sha_256_format
    skip_unless_minitest5_or_above
    bogus_container_ids = %w[3145490ee377105a4d3a7abd55083c61c0c2d616d786614e755176433c648d0
      3145490ee377105a4d3a7abd55083c61c0c2d616d78g614e755176433c648d09
      3145490ee377105a4d3a7abd55083C61c0c2d616d786614e755176433c648d09]
    bogus_container_ids.each do |id|
      mountinfo = "line1\nline2\n/docker/containers/#{id}/other/content\nline4\nline5"
      NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'linux' do
        NewRelic::Agent::SystemInfo.stub :proc_try_read, mountinfo, %w[/proc/self/mountinfo] do
          refute NewRelic::Agent::SystemInfo.docker_container_id
        end
      end
    end
  end
  # END cgroups v2

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
    assert_nil @sysinfo.parse_linux_meminfo_in_mib('')
  end

  def test_ram_in_mb_nil_when_proc_meminfo_unreadable
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/meminfo').returns(nil)

    assert_nil NewRelic::Agent::SystemInfo.ram_in_mib, 'Expected ram_in_mib to be nil'
  end

  def test_processor_info_returns_if_set
    info = 'Jurassic Park'
    NewRelic::Agent::SystemInfo.instance_variable_set(:@processor_info, info)

    assert_equal info, NewRelic::Agent::SystemInfo.processor_info
  end

  def test_processor_info_is_darwin
    info = 'darwin'
    info_stub = proc { NewRelic::Agent::SystemInfo.instance_variable_set(:@processor_info, info) }
    NewRelic::Agent::SystemInfo.stub(:darwin?, true) do
      NewRelic::Agent::SystemInfo.stub(:processor_info_darwin, info_stub) do
        NewRelic::Agent::SystemInfo.stub(:remove_bad_values, nil) do
          assert_equal info, NewRelic::Agent::SystemInfo.processor_info
        end
      end
    end
  end

  def test_processor_info_is_linux
    info = 'linux'
    info_stub = proc { NewRelic::Agent::SystemInfo.instance_variable_set(:@processor_info, info) }
    NewRelic::Agent::SystemInfo.stub(:darwin?, false) do
      NewRelic::Agent::SystemInfo.stub(:linux?, true) do
        NewRelic::Agent::SystemInfo.stub(:processor_info_linux, info_stub) do
          NewRelic::Agent::SystemInfo.stub(:remove_bad_values, nil) do
            assert_equal info, NewRelic::Agent::SystemInfo.processor_info
          end
        end
      end
    end
  end

  def test_processor_info_is_bsd
    info = 'bsd'
    info_stub = proc { NewRelic::Agent::SystemInfo.instance_variable_set(:@processor_info, info) }
    NewRelic::Agent::SystemInfo.stub(:darwin?, false) do
      NewRelic::Agent::SystemInfo.stub(:linux?, false) do
        NewRelic::Agent::SystemInfo.stub(:bsd?, true) do
          NewRelic::Agent::SystemInfo.stub(:processor_info_bsd, info_stub) do
            NewRelic::Agent::SystemInfo.stub(:remove_bad_values, nil) do
              assert_equal info, NewRelic::Agent::SystemInfo.processor_info
            end
          end
        end
      end
    end
  end

  def test_processor_info_darwin
    mappings = {'hw.packages' => :num_physical_packages, 'hw.physicalcpu_max' => :num_physical_cores, 'hw.logicalcpu_max' => :num_logical_processors}
    counts = {'hw.packages' => 1, 'hw.physicalcpu_max' => 2, 'hw.logicalcpu_max' => 3}
    sysctl_stub = proc { |param| counts[param] }
    NewRelic::Agent::SystemInfo.stub(:sysctl_value, sysctl_stub) do
      NewRelic::Agent::SystemInfo.processor_info_darwin
      info = NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)

      counts.each do |key, value|
        assert_equal value, info[mappings[key]]
      end
    end
  end

  def test_processor_info_darwin_fallback
    counts = {'hw.packages' => 2,
              'hw.physicalcpu_max' => 0,
              'hw.logicalcpu_max' => 0,
              'hw.physicalcpu' => 1,
              'hw.logicalcpu' => 0,
              'hw.ncpu' => 3}
    sysctl_stub = proc { |param| counts[param] }
    NewRelic::Agent::SystemInfo.stub(:sysctl_value, sysctl_stub) do
      NewRelic::Agent::SystemInfo.processor_info_darwin
      info = NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)

      assert_equal 2, info[:num_physical_packages]
      assert_equal 1, info[:num_physical_cores]
      assert_equal 3, info[:num_logical_processors]
    end
  end

  def test_processor_info_darwin_fallback_logicalcpu
    counts = {'hw.packages' => 2,
              'hw.physicalcpu_max' => 0,
              'hw.logicalcpu_max' => 0,
              'hw.physicalcpu' => 1,
              'hw.logicalcpu' => 4,
              'hw.ncpu' => 3}
    sysctl_stub = proc { |param| counts[param] }
    NewRelic::Agent::SystemInfo.stub(:sysctl_value, sysctl_stub) do
      NewRelic::Agent::SystemInfo.processor_info_darwin
      info = NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)

      assert_equal 4, info[:num_logical_processors]
    end
  end

  def test_processor_info_linux_is_cpuinfo
    NewRelic::Agent::SystemInfo.stub(:proc_try_read, 'T. Rex') do
      NewRelic::Agent::SystemInfo.stub(:parse_cpuinfo, 'Rawr') do
        NewRelic::Agent::SystemInfo.processor_info_linux

        assert_equal 'Rawr', NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)
      end
    end
  end

  def test_processor_info_linux_is_empty
    NewRelic::Agent::SystemInfo.stub(:proc_try_read, nil) do
      NewRelic::Agent::SystemInfo.stub(:parse_cpuinfo, 'Rawr') do
        NewRelic::Agent::SystemInfo.processor_info_linux

        assert_equal NewRelic::EMPTY_HASH, NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)
      end
    end
  end

  def test_processor_info_bsd
    NewRelic::Agent::SystemInfo.stub(:sysctl_value, 1) do
      NewRelic::Agent::SystemInfo.processor_info_bsd
      info = NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)

      assert_nil info[:num_physical_packages]
      assert_nil info[:num_physical_cores]
      assert_equal 1, info[:num_logical_processors]
    end
  end

  def test_sysctl_value
    NewRelic::Agent::SystemInfo.expects(:`).with(regexp_matches(/fox/)).once.returns('3')
    value = NewRelic::Agent::SystemInfo.sysctl_value('fox')

    assert_equal 3, value
    mocha_teardown
  end

  def test_processor_info_os_unknown
    NewRelic::Agent::SystemInfo.stub(:darwin?, false) do
      NewRelic::Agent::SystemInfo.stub(:linux?, false) do
        NewRelic::Agent::SystemInfo.stub(:bsd?, false) do
          NewRelic::Agent::SystemInfo.processor_info

          assert_equal NewRelic::EMPTY_HASH, NewRelic::Agent::SystemInfo.instance_variable_get(:@processor_info)
        end
      end
    end
  end

  def test_system_info_darwin_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('darwin13')

    assert_predicate NewRelic::Agent::SystemInfo, :darwin?, 'Expected OS to match darwin'

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')

    refute_predicate NewRelic::Agent::SystemInfo, :darwin?, 'Did not expect OS to match darwin'
  end

  def test_system_info_linux_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')

    assert_predicate NewRelic::Agent::SystemInfo, :linux?, 'Expected OS to match linux'

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('darwin13')

    refute_predicate NewRelic::Agent::SystemInfo, :linux?, 'Did not expect OS to match linux'
  end

  def test_system_info_bsd_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('freebsd')

    assert_predicate NewRelic::Agent::SystemInfo, :bsd?, 'Expected OS to match bsd'

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('darwin13')

    refute_predicate NewRelic::Agent::SystemInfo, :bsd?, 'Did not expect OS to match bsd'
  end

  def test_system_info_windows_predicate
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('mingw32')

    assert_predicate NewRelic::Agent::SystemInfo, :windows?, 'Expected OS to match windows'

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('darwin13')

    refute_predicate NewRelic::Agent::SystemInfo, :windows?, 'Did not expect OS to match windows'
  end

  def test_os_distribution_darwin
    NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'darwin23' do
      assert_equal :darwin, @sysinfo.os_distribution
    end
  end

  def test_os_distribution_linux
    NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'linux' do
      assert_equal :linux, @sysinfo.os_distribution
    end
  end

  def test_os_distribution_bsd
    NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'freebsd' do
      assert_equal :bsd, @sysinfo.os_distribution
    end
  end

  def test_os_distribution_windows
    NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'mingw32' do
      assert_equal :windows, @sysinfo.os_distribution
    end
  end
  
  def test_os_distribution_unknown
    NewRelic::Agent::SystemInfo.stub :ruby_os_identifier, 'unknown_os' do
      assert_equal 'unknown_os', @sysinfo.os_distribution
    end
  end
  
  def test_supportability_metric_recorded_when_docker_id_unavailable
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    cgroup_info = File.read(File.join(cross_agent_tests_dir, 'docker_container_id', 'invalid-length.txt'))
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/self/mountinfo').returns(cgroup_info)
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/self/cgroup').returns(cgroup_info)

    in_transaction('txn') do
      assert_nil NewRelic::Agent::SystemInfo.docker_container_id
    end

    assert_metrics_recorded 'Supportability/utilization/docker/error'
  end

  VALID_UUID = +'eb26a240-5535-0135-e727-745c89b5accd'

  def test_valid_boot_id
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/sys/kernel/random/boot_id').returns(VALID_UUID)

    assert_equal VALID_UUID, NewRelic::Agent::SystemInfo.boot_id
    assert_metrics_not_recorded 'Supportability/utilization/boot_id/error'
  end

  def test_invalid_length_ascii_boot_id
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    test_boot_id = VALID_UUID * 2
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/sys/kernel/random/boot_id').returns(test_boot_id)

    assert_equal test_boot_id, NewRelic::Agent::SystemInfo.boot_id
    assert_metrics_recorded 'Supportability/utilization/boot_id/error'
  end

  def test_truncated_invalid_length_ascii_boot_id
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    test_boot_id = VALID_UUID * 8
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/sys/kernel/random/boot_id').returns(test_boot_id)

    assert_equal test_boot_id[0, 128], NewRelic::Agent::SystemInfo.boot_id
    assert_metrics_recorded 'Supportability/utilization/boot_id/error'
  end

  def test_non_ascii_boot_id
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    panda = +'🐼'
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/sys/kernel/random/boot_id').returns(panda)

    assert_nil NewRelic::Agent::SystemInfo.boot_id
    assert_metrics_recorded 'Supportability/utilization/boot_id/error'
  end

  def test_empty_boot_id
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('linux')
    empty = +''
    NewRelic::Agent::SystemInfo.expects(:proc_try_read).with('/proc/sys/kernel/random/boot_id').returns(empty)

    assert_nil NewRelic::Agent::SystemInfo.boot_id
    assert_metrics_recorded 'Supportability/utilization/boot_id/error'
  end

  def test_nil_boot_id_on_not_linux
    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('darwin13')

    assert_nil NewRelic::Agent::SystemInfo.boot_id

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('freebsd')

    assert_nil NewRelic::Agent::SystemInfo.boot_id

    NewRelic::Agent::SystemInfo.stubs(:ruby_os_identifier).returns('solaris')

    assert_nil NewRelic::Agent::SystemInfo.boot_id

    assert_metrics_not_recorded 'Supportability/utilization/boot_id/error'
  end
end
