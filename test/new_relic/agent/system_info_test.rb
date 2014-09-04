# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require File.expand_path(File.join(File.dirname(__FILE__),'..', '..','test_helper'))

class NewRelic::Agent::SystemInfoTest < Minitest::Test

  def setup
    @sysinfo = ::NewRelic::Agent::SystemInfo
    @sysinfo.clear_processor_info
  end

  def test_1pack_1core
    cpuinfo = <<-EOS
      processor   : 0
      model name  : AMD Duron(tm) processor
      cache size  : 64 KB
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal(1, info[:num_physical_packages ])
    assert_equal(1, info[:num_physical_cores    ])
    assert_equal(1, info[:num_logical_processors])
  end

  def test_1pack_1core_hyper
    cpuinfo = <<-EOS
      processor   : 0
      model name  : Intel(R) Pentium(R) 4 CPU 2.80GHz
      cache size  : 1024 KB
      physical id : 0
      siblings    : 2
      core id     : 0
      cpu cores   : 1
      processor   : 1
      model name  : Intel(R) Pentium(R) 4 CPU 2.80GHz
      cache size  : 1024 KB
      physical id : 0
      siblings    : 2
      core id     : 0
      cpu cores   : 1
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal(1, info[:num_physical_packages ])
    assert_equal(1, info[:num_physical_cores    ])
    assert_equal(2, info[:num_logical_processors])
  end

  def test_1pack_4core
    cpuinfo = <<-EOS
      processor   : 0
      model name  : Intel(R) Xeon(R) CPU           E5410  @ 2.33GHz
      cache size  : 6144 KB
      physical id : 0
      siblings    : 4
      core id     : 0
      cpu cores   : 4
      processor   : 1
      model name  : Intel(R) Xeon(R) CPU           E5410  @ 2.33GHz
      cache size  : 6144 KB
      physical id : 0
      siblings    : 4
      core id     : 1
      cpu cores   : 4
      processor   : 2
      model name  : Intel(R) Xeon(R) CPU           E5410  @ 2.33GHz
      cache size  : 6144 KB
      physical id : 0
      siblings    : 4
      core id     : 2
      cpu cores   : 4
      processor   : 3
      model name  : Intel(R) Xeon(R) CPU           E5410  @ 2.33GHz
      cache size  : 6144 KB
      physical id : 0
      siblings    : 4
      core id     : 3
      cpu cores   : 4
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal(1, info[:num_physical_packages ])
    assert_equal(4, info[:num_physical_cores    ])
    assert_equal(4, info[:num_logical_processors])
  end

  def test_1pack_2core
    cpuinfo = <<-EOS
      processor   : 0
      model name  : Intel(R) Pentium(R) D CPU 3.00GHz
      cache size  : 2048 KB
      physical id : 0
      siblings    : 2
      core id     : 0
      cpu cores   : 2
      processor   : 1
      model name  : Intel(R) Pentium(R) D CPU 3.00GHz
      cache size  : 2048 KB
      physical id : 0
      siblings    : 2
      core id     : 1
      cpu cores   : 2
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal(1, info[:num_physical_packages ])
    assert_equal(2, info[:num_physical_cores    ])
    assert_equal(2, info[:num_logical_processors])
  end

  def test_2pack_1core_hyper
    cpuinfo = <<-EOS
      processor   : 0
      model name  : Intel(R) Xeon(TM) CPU 3.60GHz
      cache size  : 1024 KB
      physical id : 0
      siblings    : 2
      core id     : 0
      cpu cores   : 1
      processor   : 1
      model name  : Intel(R) Xeon(TM) CPU 3.60GHz
      cache size  : 1024 KB
      physical id : 3
      siblings    : 2
      core id     : 0
      cpu cores   : 1
      processor   : 2
      model name  : Intel(R) Xeon(TM) CPU 3.60GHz
      cache size  : 1024 KB
      physical id : 0
      siblings    : 2
      core id     : 0
      cpu cores   : 1
      processor   : 3
      model name  : Intel(R) Xeon(TM) CPU 3.60GHz
      cache size  : 1024 KB
      physical id : 3
      siblings    : 2
      core id     : 0
      cpu cores   : 1
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal(2, info[:num_physical_packages ])
    assert_equal(2, info[:num_physical_cores    ])
    assert_equal(4, info[:num_logical_processors])
  end

  def test_2pack_2core
    cpuinfo = <<-EOS
      processor : 0
      model name  : Intel(R) Xeon(R) CPU            5160  @ 3.00GHz
      cache size  : 4096 KB
      physical id : 0
      siblings    : 2
      core id     : 0
      cpu cores   : 2
      processor   : 1
      model name  : Intel(R) Xeon(R) CPU            5160  @ 3.00GHz
      cache size  : 4096 KB
      physical id : 0
      siblings    : 2
      core id     : 1
      cpu cores   : 2
      processor   : 2
      model name  : Intel(R) Xeon(R) CPU            5160  @ 3.00GHz
      cache size  : 4096 KB
      physical id : 3
      siblings    : 2
      core id     : 0
      cpu cores   : 2
      processor   : 3
      model name  : Intel(R) Xeon(R) CPU            5160  @ 3.00GHz
      cache size  : 4096 KB
      physical id : 3
      siblings    : 2
      core id     : 1
      cpu cores   : 2
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal(2, info[:num_physical_packages ])
    assert_equal(4, info[:num_physical_cores    ])
    assert_equal(4, info[:num_logical_processors])
  end

end

