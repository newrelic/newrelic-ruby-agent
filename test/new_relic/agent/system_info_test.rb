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

  def test_2pack_10core_hyper
    cpuinfo = <<-EOS
      processor : 0
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 0
      cpu cores : 10
      apicid    : 0
      initial apicid  : 0
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 1
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 1
      cpu cores : 10
      apicid    : 2
      initial apicid  : 2
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 2
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 2
      cpu cores : 10
      apicid    : 4
      initial apicid  : 4
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 3
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 3
      cpu cores : 10
      apicid    : 6
      initial apicid  : 6
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 4
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 4
      cpu cores : 10
      apicid    : 8
      initial apicid  : 8
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 5
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 8
      cpu cores : 10
      apicid    : 16
      initial apicid  : 16
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 6
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 9
      cpu cores : 10
      apicid    : 18
      initial apicid  : 18
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 7
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 10
      cpu cores : 10
      apicid    : 20
      initial apicid  : 20
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 8
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 11
      cpu cores : 10
      apicid    : 22
      initial apicid  : 22
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 9
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 12
      cpu cores : 10
      apicid    : 24
      initial apicid  : 24
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 10
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 0
      cpu cores : 10
      apicid    : 32
      initial apicid  : 32
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 11
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 1
      cpu cores : 10
      apicid    : 34
      initial apicid  : 34
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 12
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 2
      cpu cores : 10
      apicid    : 36
      initial apicid  : 36
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 13
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 3
      cpu cores : 10
      apicid    : 38
      initial apicid  : 38
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 14
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 4
      cpu cores : 10
      apicid    : 40
      initial apicid  : 40
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 15
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 8
      cpu cores : 10
      apicid    : 48
      initial apicid  : 48
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 16
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 9
      cpu cores : 10
      apicid    : 50
      initial apicid  : 50
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 17
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 10
      cpu cores : 10
      apicid    : 52
      initial apicid  : 52
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 18
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 11
      cpu cores : 10
      apicid    : 54
      initial apicid  : 54
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 19
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 2801.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 12
      cpu cores : 10
      apicid    : 56
      initial apicid  : 56
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 20
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 0
      cpu cores : 10
      apicid    : 1
      initial apicid  : 1
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 21
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 1
      cpu cores : 10
      apicid    : 3
      initial apicid  : 3
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 22
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 2
      cpu cores : 10
      apicid    : 5
      initial apicid  : 5
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 23
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 3
      cpu cores : 10
      apicid    : 7
      initial apicid  : 7
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 24
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 4
      cpu cores : 10
      apicid    : 9
      initial apicid  : 9
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 25
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 8
      cpu cores : 10
      apicid    : 17
      initial apicid  : 17
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 26
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 9
      cpu cores : 10
      apicid    : 19
      initial apicid  : 19
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 27
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 10
      cpu cores : 10
      apicid    : 21
      initial apicid  : 21
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 28
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 11
      cpu cores : 10
      apicid    : 23
      initial apicid  : 23
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 29
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 0
      siblings  : 20
      core id   : 12
      cpu cores : 10
      apicid    : 25
      initial apicid  : 25
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5586.71
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 30
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 0
      cpu cores : 10
      apicid    : 33
      initial apicid  : 33
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 31
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 1
      cpu cores : 10
      apicid    : 35
      initial apicid  : 35
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 32
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 2
      cpu cores : 10
      apicid    : 37
      initial apicid  : 37
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 33
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 3
      cpu cores : 10
      apicid    : 39
      initial apicid  : 39
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 34
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 4
      cpu cores : 10
      apicid    : 41
      initial apicid  : 41
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 35
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 8
      cpu cores : 10
      apicid    : 49
      initial apicid  : 49
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 36
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 9
      cpu cores : 10
      apicid    : 51
      initial apicid  : 51
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 37
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 10
      cpu cores : 10
      apicid    : 53
      initial apicid  : 53
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 38
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 11
      cpu cores : 10
      apicid    : 55
      initial apicid  : 55
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:

      processor : 39
      vendor_id : GenuineIntel
      cpu family  : 6
      model   : 62
      model name  : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
      stepping  : 4
      cpu MHz   : 1200.000
      cache size  : 25600 KB
      physical id : 1
      siblings  : 20
      core id   : 12
      cpu cores : 10
      apicid    : 57
      initial apicid  : 57
      fpu   : yes
      fpu_exception : yes
      cpuid level : 13
      wp    : yes
      flags   : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc arch_perfmon pebs bts rep_good xtopology nonstop_tsc aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid dca sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm ida arat epb xsaveopt pln pts dts tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms
      bogomips  : 5585.83
      clflush size  : 64
      cache_alignment : 64
      address sizes : 46 bits physical, 48 bits virtual
      power management:
    EOS
    info = @sysinfo.parse_cpuinfo(cpuinfo)

    assert_equal( 2, info[:num_physical_packages ])
    assert_equal(20, info[:num_physical_cores    ])
    assert_equal(40, info[:num_logical_processors])
  end

end

