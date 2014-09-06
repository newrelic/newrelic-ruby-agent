These tests are for determining the numbers of physical packages, physical cores,
and logical processors from the data returned by /proc/cpuinfo on Linux hosts.
Each text file in this directory is the output of /proc/cpuinfo on various machines.

The names of all test files should be of the form `Xpack_Ycore_Zthread.txt`
where `X`, `Y`, and `Z` are integers. For example, a single quad-core processor
without hyperthreading would correspond to `1pack_4core_1thread.txt`, while two
6-core processors with hyperthreading would correspond to
`2pack_6core_2thread.txt`, and would be pretty sweet.

Using `X`, `Y`, and `Z` from above, code processing the text in these files
should produce the following expected values:

| property             | value           |
| -------------------- |-----------------|
| # physical packages  | `X`             |
| # physical cores     | `X * Y`         |
| # logical processors | `X * Y * Z`     |

(Obviously, the processing code should do this with no knowledge of the filenames.)
