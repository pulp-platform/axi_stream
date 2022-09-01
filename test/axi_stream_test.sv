// Copyright 2022 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Author: Noah Huetter <huettern@iis.ee.ethz.ch>

/// A set of testbench utilities for AXI Stream interfaces.
package axi_stream_test;


  /// A driver for AXI4-Stream interface.
  class axi_stream_driver #(
    parameter int unsigned DataWidth = 0,
    parameter int unsigned IdWidth   = 0,
    parameter int unsigned DestWidth = 0,
    parameter int unsigned UserWidth = 0,
    parameter time         ApplTime  = 0ns, // stimuli application time
    parameter time         TestTime  = 0ns  // stimuli test time
  );

    virtual AXIS_BUS_DV #(
      .DataWidth ( DataWidth ),
      .IdWidth   ( IdWidth   ),
      .DestWidth ( DestWidth ),
      .UserWidth ( UserWidth )
    ) axi_stream;

    function new(
      virtual AXIS_BUS_DV #(
        .DataWidth(DataWidth),
        .IdWidth(IdWidth),
        .DestWidth(DestWidth),
        .UserWidth(UserWidth)
      ) axi_stream
    );
      this.axi_stream = axi_stream;
    endfunction

    function void reset_tx();
      axi_stream.tvalid <= '0;
      axi_stream.tdata  <= '0;
      axi_stream.tstrb  <= '0;
      axi_stream.tkeep  <= '0;
      axi_stream.tlast  <= '0;
      axi_stream.tid    <= '0;
      axi_stream.tdest  <= '0;
      axi_stream.tuser  <= '0;
    endfunction

    function void reset_rx();
      axi_stream.tready <= '0;
    endfunction

    task cycle_start;
      #TestTime;
    endtask

    task cycle_end;
      @(posedge axi_stream.clk_i);
    endtask

    /// Issue a beat
    task send(input logic [DataWidth-1:0] data, input logic last);
      axi_stream.tdata <= #ApplTime data;
      axi_stream.tstrb <= '0;
      axi_stream.tkeep <= '0;
      axi_stream.tlast <= #ApplTime last;
      axi_stream.tid <= '0;
      axi_stream.tdest <= '0;
      axi_stream.tuser <= '0;
      axi_stream.tvalid <= #ApplTime 1;
      cycle_start();
      while (axi_stream.tready != 1) begin
        cycle_end();
        cycle_start();
      end
      cycle_end();
      axi_stream.tdata  <= #ApplTime '0;
      axi_stream.tlast  <= #ApplTime '0;
      axi_stream.tvalid <= #ApplTime 0;
    endtask

    /// Wait for a beat
    task recv(output [DataWidth-1:0] data, output logic [LW-1:0] last);
      axi_stream.tready <= #ApplTime 1;
      cycle_start();
      while (axi_stream.tvalid != 1) begin
        cycle_end();
        cycle_start();
      end
      data = axi_stream.tdata;
      last = axi_stream.tlast;
      cycle_end();
      axi_stream.tready <= #ApplTime 0;
    endtask

  endclass


  /// The data transferred on a beat
  class axi_stream_beat #(
    parameter DataWidth = 0,
    parameter IdWidth   = 0,
    parameter DestWidth = 0,
    parameter UserWidth = 0
  );
    logic [DataWidth-1:0]   tdata = '0;
    logic [DataWidth/8-1:0] tstrb = '0;
    logic [DataWidth/8-1:0] tkeep = '0;
    logic                   tlast = '0;
    logic [IdWidth-1:0]     tid   = '0;
    logic [DestWidth-1:0]   tdest = '0;
    logic [UserWidth-1:0]   tuser = '0;
  endclass


  class axi_stream_rand_rx #(
    // AXI Stream interface parameters
    parameter int unsigned DataWidth     = 0,
    parameter int unsigned IdWidth       = 0,
    parameter int unsigned DestWidth     = 0,
    parameter int unsigned UserWidth     = 0,
    // Stimuli application and test time
    parameter time         ApplTime      = 0ns,
    parameter time         TestTime      = 0ns,
    // Upper and lower bounds on wait cycles
    parameter int unsigned MinWaitCycles = 0,
    parameter int unsigned MaxWaitCycles = 0
  );
    typedef axi_stream_test::axi_stream_driver #(
      .DataWidth ( DataWidth ),
      .IdWidth   ( IdWidth   ),
      .DestWidth ( DestWidth ),
      .UserWidth ( UserWidth )
    ) axi_stream_driver_t;

    typedef logic [DataWidth-1:0]  data_t;
    typedef logic                   last_t;
    typedef logic [DataWidth/8-1:0] strb_t;

    string              name;
    axi_stream_driver_t drv;
    data_t              recv_queue[$];

    function new(
      virtual AXIS_BUS_DV #(
        .DataWidth ( DataWidth ),
        .IdWidth   ( IdWidth   ),
        .DestWidth ( DestWidth ),
        .UserWidth ( UserWidth )
      ) axi_stream,
      input string name
    );

      this.drv  = new(axi_stream);
      this.name = name;
      assert (DataWidth != 0)
      else $fatal(1, "Data width must be non-zero!");
    endfunction

    function void reset();
      this.drv.reset_rx();
    endfunction

    task automatic rand_wait (input int unsigned min, max);
      int unsigned rand_success, cycles;
      rand_success = std::randomize(
          cycles
      ) with {
        cycles >= min;
        cycles <= max;
      };
      assert (rand_success)
      else $error("Failed to randomize wait cycles!");
      repeat (cycles) @(posedge this.drv.axi_stream.clk_i);
    endtask

    task automatic recv();
      forever begin
        automatic data_t data;
        automatic last_t last;
        rand_wait(MinWaitCycles, MaxWaitCycles);
        this.drv.recv(data, last);
        $display("%0t %s> Recv AR with DATA: %h LAST: %b", $time(), this.name, data, last);
        this.recv_queue.push_back(data);
      end
    endtask : recv

    task automatic run();
      fork
        recv();
      join
    endtask

  endclass

endpackage
