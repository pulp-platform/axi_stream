// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Denis Gregor <romeoradescu25@proton.me>

// A downsizer must emit one sub-transfer per VALID byte, not one per lane.
//
// Emitting the lanes a partial beat marks invalid puts junk into the outgoing
// stream. Observed in pulp-platform/pulp-ethernet#5: a 52-byte Ethernet
// payload produced an 84-byte frame instead of 78. The excess of exactly six
// is the invalid lanes of the final 64-bit beat (8 - 2 valid bytes).
//
// Self-contained: no randomized drivers, so the checks state exact byte
// counts and can be read as the specification.

`timescale 1 ns/1 ps
`include "axi_stream/typedef.svh"

module tb_axi_stream_dw_downsizer_tkeep ();

  localparam int unsigned DW_IN  = 64;
  localparam int unsigned DW_OUT = 8;
  localparam time tCK = 8ns;

  typedef logic [DW_IN-1:0]    tdata_in_t;
  typedef logic [DW_IN/8-1:0]  tstrb_in_t;
  typedef logic [DW_IN/8-1:0]  tkeep_in_t;
  typedef logic [DW_OUT-1:0]   tdata_out_t;
  typedef logic [DW_OUT/8-1:0] tstrb_out_t;
  typedef logic [DW_OUT/8-1:0] tkeep_out_t;
  typedef logic [0:0]          tid_t;
  typedef logic [0:0]          tdest_t;
  typedef logic [0:0]          tuser_t;

  `AXI_STREAM_TYPEDEF_ALL(in, tdata_in_t, tstrb_in_t, tkeep_in_t, tid_t, tdest_t, tuser_t)
  `AXI_STREAM_TYPEDEF_ALL(out, tdata_out_t, tstrb_out_t, tkeep_out_t, tid_t, tdest_t, tuser_t)

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #(tCK/2) clk_i = ~clk_i;

  in_req_t  in_req;
  in_rsp_t  in_rsp;
  out_req_t out_req;
  out_rsp_t out_rsp;

  axi_stream_dw_downsizer #(
    .DataWidthIn         (DW_IN),
    .DataWidthOut        (DW_OUT),
    .IdWidth             (1),
    .DestWidth           (1),
    .UserWidth           (1),
    .axi_stream_in_req_t (in_req_t),
    .axi_stream_in_rsp_t (in_rsp_t),
    .axi_stream_out_req_t(out_req_t),
    .axi_stream_out_rsp_t(out_rsp_t)
  ) i_dut (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .in_req_i (in_req),
    .in_rsp_o (in_rsp),
    .out_req_o(out_req),
    .out_rsp_i(out_rsp)
  );

  int unsigned emitted;
  int unsigned lasts;
  int unsigned failures = 0;
  logic [DW_OUT-1:0] first_byte;

  assign out_rsp.tready = 1'b1;

  always @(posedge clk_i) begin
    if (rst_ni && out_req.tvalid && out_rsp.tready) begin
      if (emitted == 0) first_byte <= out_req.t.data;
      emitted <= emitted + 1;
      if (out_req.t.last) lasts <= lasts + 1;
    end
  end

  // Drives exactly one beat: TVALID is dropped on the first accepting edge,
  // since holding it lets the LastDataOut state latch a second beat.
  task automatic send_beat(input tdata_in_t data, input tkeep_in_t keep, input logic last);
    in_req.t.data = data;
    in_req.t.strb = keep;
    in_req.t.keep = keep;
    in_req.t.last = last;
    in_req.t.id   = '0;
    in_req.t.dest = '0;
    in_req.t.user = '0;
    in_req.tvalid = 1'b1;
    forever begin
      @(posedge clk_i);
      if (in_rsp.tready) break;
    end
    in_req.tvalid = 1'b0;
    in_req.t.last = 1'b0;
  endtask

  task automatic check(input string name, input int unsigned got, input int unsigned exp);
    if (got == exp) begin
      $display("  PASS  %-44s %0d", name, got);
    end else begin
      $display("  FAIL  %-44s got %0d, expected %0d", name, got, exp);
      failures++;
    end
  endtask

  task automatic reset_counters();
    emitted = 0;
    lasts   = 0;
    @(posedge clk_i);
  endtask

  initial begin
    in_req  = '0;
    emitted = 0;
    lasts   = 0;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);

    // The reported case: only two lanes of the final beat are valid.
    reset_counters();
    send_beat(64'h1122_3344_5566_7788, 8'h03, 1'b1);
    repeat (30) @(posedge clk_i);
    check("final beat TKEEP=0x03 emits 2 bytes", emitted, 2);
    check("final beat TKEEP=0x03 emits 1 TLAST", lasts, 1);

    // A fully valid beat must be unaffected.
    reset_counters();
    send_beat(64'hAABB_CCDD_EEFF_0011, 8'hFF, 1'b1);
    repeat (30) @(posedge clk_i);
    check("full beat TKEEP=0xFF emits 8 bytes", emitted, 8);
    check("full beat TKEEP=0xFF emits 1 TLAST", lasts, 1);

    // One valid byte: it is itself the last sub-transfer and carries TLAST.
    reset_counters();
    send_beat(64'h0000_0000_0000_00A5, 8'h01, 1'b1);
    repeat (30) @(posedge clk_i);
    check("single-byte beat emits 1 byte", emitted, 1);
    check("single-byte beat emits 1 TLAST", lasts, 1);
    check("single-byte beat carries the valid lane", int'(first_byte), 8'hA5);

    // Seven of eight lanes valid.
    reset_counters();
    send_beat(64'h00FF_EEDD_CCBB_AA99, 8'h7F, 1'b1);
    repeat (30) @(posedge clk_i);
    check("beat TKEEP=0x7F emits 7 bytes", emitted, 7);

    // A full beat followed by a two-byte tail: 8 + 2, one TLAST.
    reset_counters();
    send_beat(64'h0102_0304_0506_0708, 8'hFF, 1'b0);
    send_beat(64'h0000_0000_0000_0B0A, 8'h03, 1'b1);
    repeat (40) @(posedge clk_i);
    check("full beat + 2-byte tail emits 10 bytes", emitted, 10);
    check("full beat + 2-byte tail emits 1 TLAST", lasts, 1);

    if (failures == 0) begin
      $display("tb_axi_stream_dw_downsizer_tkeep: all checks passed");
    end else begin
      $error("tb_axi_stream_dw_downsizer_tkeep: %0d check(s) failed", failures);
    end
    $finish;
  end

endmodule
