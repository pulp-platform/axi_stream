// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Denis Gregor <romeoradescu25@proton.me>

// Every frame must leave the upsizer.
//
// AcceptDataIn pads when a beat arrives with TLAST before the wide word is
// full. The DataOut fast path ("already accept next subtransfer") also consumes
// a beat and latches its TLAST, but returned to AcceptDataIn unconditionally,
// so a frame whose final beat was taken there was never padded out. Its
// remainder stayed in the register until a later frame filled the word and then
// left merged into that frame.
//
// The sweep is the point: only lengths one beat past a word boundary reach the
// fast path with TLAST set, so a single hand-picked length misses this.

`timescale 1 ns/1 ps
`include "axi_stream/typedef.svh"

module tb_axi_stream_dw_upsizer_last ();

  localparam int unsigned DW_IN  = 8;
  localparam int unsigned DW_OUT = 64;
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

  axi_stream_dw_upsizer #(
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

  logic [DW_OUT-1:0]   words [$];
  logic [DW_OUT/8-1:0] keeps [$];
  logic                lasts [$];

  assign out_rsp.tready = 1'b1;

  always @(posedge clk_i) begin
    if (rst_ni && out_req.tvalid && out_rsp.tready) begin
      words.push_back(out_req.t.data);
      keeps.push_back(out_req.t.keep);
      lasts.push_back(out_req.t.last);
    end
  end

  int unsigned failures = 0;

  // TVALID is held high across the whole frame, so the final beat can be taken
  // by the DataOut fast path. A gap before the last beat hides the bug.
  task automatic send_frame(input int unsigned n);
    words.delete();
    keeps.delete();
    lasts.delete();
    for (int unsigned i = 0; i < n; i++) begin
      in_req.t.data = 8'hA0 + i[7:0];
      in_req.t.strb = 1'b1;
      in_req.t.keep = 1'b1;
      in_req.t.last = (i == n-1);
      in_req.t.id   = '0;
      in_req.t.dest = '0;
      in_req.t.user = '0;
      in_req.tvalid = 1'b1;
      forever begin
        @(posedge clk_i);
        if (in_rsp.tready) break;
      end
    end
    in_req.tvalid = 1'b0;
    in_req.t.last = 1'b0;
    repeat (60) @(posedge clk_i);
  endtask

  task automatic check(input string name, input bit ok, input string detail);
    if (ok) begin
      $display("  PASS  %s", name);
    end else begin
      $display("  FAIL  %s -- %s", name, detail);
      failures++;
    end
  endtask

  initial begin
    in_req = '0;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);

    // Every length from one beat to three words.
    for (int unsigned n = 1; n <= 24; n++) begin
      automatic int unsigned expected = (n + 7) / 8;
      send_frame(n);
      check($sformatf("%0d-beat frame emits %0d word(s)", n, expected),
            words.size() == expected,
            $sformatf("emitted %0d", words.size()));
    end

    // Content of a length that goes through the fast path with TLAST set.
    send_frame(9);
    if (words.size() == 2) begin
      check("9-beat frame: first word holds beats 0-7",
            words[0] == 64'hA7A6A5A4A3A2A1A0, "payload differs");
      check("9-beat frame: second word holds beat 8",
            words[1][7:0] == 8'hA8, "tail beat differs");
      check("9-beat frame: tail TKEEP marks one valid byte",
            keeps[1] == 8'h01, "tail TKEEP differs");
      check("9-beat frame: TLAST on the final word",
            lasts[1] == 1'b1, "TLAST missing");
    end else begin
      check("9-beat frame emits two words", 1'b0, "cannot check content");
    end

    if (failures == 0) begin
      $display("tb_axi_stream_dw_upsizer_last: all checks passed");
    end else begin
      $error("tb_axi_stream_dw_upsizer_last: %0d check(s) failed", failures);
    end
    $finish;
  end

endmodule
