# AXI Stream SystemVerilog Modules for High-Performance On-Chip Communication
[![CI status](https://akurth.net/usrv/ig/shields/pipeline/github-mirror/axi_stream/master.svg)](https://iis-git.ee.ethz.ch/github-mirror/axi_stream/commits/master)
[![GitHub tag (latest SemVer)](https://img.shields.io/github/v/tag/pulp-platform/axi_stream?color=blue&label=current&sort=semver)](CHANGELOG.md)
[![SHL-0.51 license](https://img.shields.io/badge/license-SHL--0.51-green)](LICENSE)

This repository provides modules to build on-chip communication networks adhering to the [AXI4 Stream Specification][AMBA 5 Stream Spec].

Our **design goals** are:
- **Topology Independence**: We provide elementary building blocks that allow users to implement any network topology.
- **Modularity**: We favor design by composition over design by configuration where possible.  We strive to apply the *Unix philosophy* to hardware: make each module do one thing well.  This means you will more often instantiate our modules back-to-back than change a parameter value to build more specialized networks.
- **Fit for Heterogeneous Networks**: Our modules are parametrizable in terms of data width and transaction concurrency.  This allows to create optimized networks for a wide range of performance (e.g., bandwidth, concurrency, timing), power, and area requirements.
- **Full AXI Standard Compliance**.
- **Compatibility** with a [wide range of (recent versions of) EDA tools](#which-eda-tools-are-supported) and implementation in standardized synthesizable SystemVerilog.

## List of Modules

In addition to the documents linked in the following table, we are setting up [documentation auto-generated from inline docstrings](https://pulp-platform.github.io/axi_stream/master).

| Name                                                 | Description                                             | Doc                            |
|------------------------------------------------------|-------------------------------------------------------- |--------------------------------|
| [`axi_stream_intf`](src/axi_stream_intf.sv)          | This file defines the interfaces we support.            |                                |
| [`axi_stream_test`](test/axi_stream_test.sv)         | A set of testbench utilities for AXI Stream interfaces. |                                |

### Simulation-Only Modules

In addition to the modules above, which are available in synthesis and simulation, the following modules are available only in simulation.  Those modules are widely used in our testbenches, but they are also suitable to build testbenches for AXI modules and systems outside this repository.

| Name                                                 | Description                                                                                             |
|------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| [`axi_stream_driver`](test/axi_stream_test.sv)       | Low-level driver for AXI Stream that can send and receive individual beats on any channel.              |
| [`axi_stream_rand_rx`](test/axi_stream_test.sv)      | AXI Stream receiver component that responds to transactions with constrainable random delays and data.  |


## Which EDA Tools Are Supported?

Our code is written in standard SystemVerilog ([IEEE 1800-2012][], to be precise), so the more important question is: Which subset of SystemVerilog does your EDA tool support?

We aim to be compatible with a wide range of EDA tools.  For this reason, we strive to use as simple language constructs as possible, especially for our synthesizable modules.  We encourage contributions that further simplify our code to make it compatible with even more EDA tools.  We also welcome contributions that work around problems that specific EDA tools may have with our code, as long as:
- the EDA tool is reasonably widely used,
- recent versions of the EDA tool are affected,
- the workaround does not break functionality in other tools, and
- the workaround does not significantly complicate code or add maintenance overhead.

In addition, we suggest to report issues with the SystemVerilog language support directly to the EDA vendor. Our code is fully open and
can / should be shared with the EDA vendor as a testcase for any language problem encountered.

All code in each release and on the default branch is tested on a recent version of at least one industry-standard RTL simulator and synthesizer.  You can examine the [CI settings](./.gitlab-ci.yml) to find out which version of which tool we are running.


[AMBA 5 Stream Spec]: https://documentation-service.arm.com/static/60d5b244677cf7536a55c23e?token=
[IEEE 1800-2012]: https://standards.ieee.org/standard/1800-2012.html
