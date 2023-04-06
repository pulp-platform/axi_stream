// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Thiemo Zaugg <zauggth@ethz.ch>


/// An AXI Stream downsizer
module axi_stream_dw_downsizer #(
  /// AXI Stream Data Width In
  parameter int unsigned DataWidthIn  = 64,
  /// AXI Stream Data Width Out
  parameter int unsigned DataWidthOut = 8 ,
  /// AXI Stream Id Width
  parameter int unsigned IdWidth      = 0,
  /// AXI Stream Dest Width
  parameter int unsigned DestWidth    = 0,
  /// AXI Stream User Width
  parameter int unsigned UserWidth    = 0,
  /// AXI Stream in request struct
  parameter type axi_stream_in_req_t = logic,
  /// AXI Stream in response struct
  parameter type axi_stream_in_rsp_t = logic,
  /// AXI Stream out request struct
  parameter type axi_stream_out_req_t = logic,
  /// AXI Stream out response struct
  parameter type axi_stream_out_rsp_t = logic
) (
  /// Clock
  input  logic            clk_i,
  /// Asynchronous reset, active low
  input  logic            rst_ni,
  /// in port request
  input axi_stream_in_req_t in_req_i,
  /// in port response
  output  axi_stream_in_rsp_t in_rsp_o,
  /// out port request
  output  axi_stream_out_req_t out_req_o,
  /// out port response
  input axi_stream_out_rsp_t out_rsp_i
);

  localparam int unsigned StrbWidthIn         = DataWidthIn / 8              ;
  localparam int unsigned KeepWidthIn         = DataWidthIn / 8              ;
  localparam int unsigned TotalSubTransfers   = DataWidthIn / DataWidthOut   ;
  localparam int unsigned CounterWidth        = $clog2(TotalSubTransfers)    ;
  localparam int unsigned StrbWidthOut        = StrbWidthIn/TotalSubTransfers;
  localparam int unsigned KeepWidthOut        = KeepWidthIn/TotalSubTransfers;
  localparam int unsigned MaxSubTransferIndex = TotalSubTransfers - 1        ;

  logic [DataWidthIn-1:0] tdata_received_d, tdata_received_q;
  logic [StrbWidthIn-1:0] tstrb_received_d, tstrb_received_q;
  logic [KeepWidthIn-1:0] tkeep_received_d, tkeep_received_q;
  logic                   tlast_received_d, tlast_received_q;
  logic [    IdWidth-1:0] tid_received_d,   tid_received_q;
  logic [  DestWidth-1:0] tdest_received_d, tdest_received_q;
  logic [  UserWidth-1:0] tuser_received_d, tuser_received_q;

  logic [CounterWidth-1:0] counter_d, counter_q;

  typedef enum logic [2:0] {NoValidDataIn, ValidDataInNoReadyOut, AcceptDataIn,
                            NoReadyInTransmission, DataOut} state_t;
  state_t state_d, state_q;

  always_comb begin // connect correct signals to output
    if (counter_d == 0) begin //First sub-transfer must come directly from the input axi stream
      out_req_o.t.data = in_req_i.t.data[DataWidthOut-1:0];
      out_req_o.t.strb = in_req_i.t.strb[StrbWidthOut-1:0];
      out_req_o.t.keep = in_req_i.t.keep[KeepWidthOut-1:0];
      out_req_o.t.id   = in_req_i.t.id;
      out_req_o.t.dest = in_req_i.t.dest;
      out_req_o.t.user = in_req_i.t.user;
    end else begin // all other sub-transfers can come from the stored data of the input stream
      out_req_o.t.data = tdata_received_q[DataWidthOut-1:0];
      out_req_o.t.strb = tstrb_received_q[StrbWidthOut-1:0];
      out_req_o.t.keep = tkeep_received_q[KeepWidthOut-1:0];
      out_req_o.t.id   = tid_received_q;
      out_req_o.t.dest = tdest_received_q;
      out_req_o.t.user = tuser_received_q;
    end
  end

  always_comb begin
    state_d         = state_q;
    counter_d       = 'd0;
    out_req_o.tvalid = in_req_i.tvalid;
    in_rsp_o.tready  = out_rsp_i.tready;
    out_req_o.t.last  = 1'b0;

    tdata_received_d = tdata_received_q;
    tstrb_received_d = tstrb_received_q;
    tkeep_received_d = tkeep_received_q;
    tlast_received_d = tlast_received_q;
    tid_received_d   = tid_received_q;
    tdest_received_d = tdest_received_q;
    tuser_received_d = tuser_received_q;

    unique case (state_q)
      NoValidDataIn : begin
        if (in_req_i.tvalid && out_rsp_i.tready) begin
          state_d = AcceptDataIn;
        end
        if (in_req_i.tvalid && !out_rsp_i.tready) begin
          state_d = ValidDataInNoReadyOut;
        end
      end

      ValidDataInNoReadyOut : begin
        if (!in_req_i.tvalid) begin
          state_d = NoValidDataIn;
        end
        if (in_req_i.tvalid && out_rsp_i.tready) begin
          state_d = AcceptDataIn;
        end
      end

      AcceptDataIn : begin
        if (out_rsp_i.tready) begin
          state_d = DataOut;
        end else begin
          state_d = NoReadyInTransmission;
        end
      end

      NoReadyInTransmission : begin
        if (out_rsp_i.tready) begin
          state_d = DataOut;
        end
      end

      DataOut : begin
        if (counter_q == MaxSubTransferIndex) begin
          if (!in_req_i.tvalid) begin
            state_d = NoValidDataIn;
          end else if (out_rsp_i.tready) begin
            state_d = AcceptDataIn;
          end else begin
            state_d = ValidDataInNoReadyOut;
          end
        end else begin
          if (!out_rsp_i.tready) begin
            state_d = NoReadyInTransmission;
          end
        end
      end

      default: begin
        state_d = NoValidDataIn;
      end
    endcase

    // logic for state transitions
    if (state_d == AcceptDataIn) begin
      out_req_o.tvalid = 1'b1;
      in_rsp_o.tready  = 1'b1;
      // save new data from input axi stream to registers
      tdata_received_d = in_req_i.t.data >> DataWidthOut;
      tstrb_received_d = in_req_i.t.strb >> StrbWidthOut;
      tkeep_received_d = in_req_i.t.keep >> KeepWidthOut;
      tlast_received_d = in_req_i.t.last;
      tid_received_d   = in_req_i.t.id;
      tdest_received_d = in_req_i.t.dest;
      tuser_received_d = in_req_i.t.user;
    end
    if (state_d == NoReadyInTransmission) begin
      out_req_o.tvalid = 1'b1;
      in_rsp_o.tready  = 1'b0;
      counter_d       = counter_q;
    end
    if (state_d == DataOut) begin
      out_req_o.tvalid = 1'b1;
      in_rsp_o.tready  = 1'b0;
      counter_d       = counter_q + 'd1;
      tdata_received_d = tdata_received_q >> DataWidthOut;
      tstrb_received_d = tstrb_received_q >> StrbWidthOut;
      tkeep_received_d = tkeep_received_q >> KeepWidthOut;

      if (counter_q == MaxSubTransferIndex - 1) begin
        // only output the tlast signal on the final sub-transfer
        out_req_o.t.last = tlast_received_q;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= NoValidDataIn;
      counter_q <= 'd0;

      tdata_received_q <= 'd0;
      tstrb_received_q <= 'd0;
      tkeep_received_q <= 'd0;
      tlast_received_q <= 1'b1;
      tid_received_q   <= 'd0;
      tdest_received_q <= 'd0;
      tuser_received_q <= 'd0;
    end else begin
      state_q   <= state_d;
      counter_q <= counter_d;

      tdata_received_q <= tdata_received_d;
      tstrb_received_q <= tstrb_received_d;
      tkeep_received_q <= tkeep_received_d;
      tlast_received_q <= tlast_received_d;
      tid_received_q   <= tid_received_d;
      tdest_received_q <= tdest_received_d;
      tuser_received_q <= tuser_received_d;
    end
  end

  // pragma translate_off
  `ifndef VERILATOR
    initial begin: p_assertions
      assert (DataWidthIn > DataWidthOut) else $fatal(1,
                                        "Input data width must be beigger than output data width!");
      assert ((DataWidthIn % DataWidthOut) == 0) else $fatal(1,
                          "Input data width must be an integer multiple of the output data width!");
    end
  `endif
  // pragma translate_on

endmodule


`include "axi_stream/assign.svh"
`include "axi_stream/typedef.svh"

/// An AXI Stream downsizer (interface wrapper).
module axi_stream_dw_downsizer_intf #(
  /// AXI Stream Data Width In
  parameter int unsigned DataWidthIn  = 64,
  /// AXI Stream Data Width Out
  parameter int unsigned DataWidthOut = 8 ,
  /// AXI Stream Id Width
  parameter int unsigned IdWidth      = 0,
  /// AXI Stream Dest Width
  parameter int unsigned DestWidth    = 0,
  /// AXI Stream User Width
  parameter int unsigned UserWidth    = 0
) (
  /// Clock
  input logic       clk_i,
  /// Asynchronous reset, active low
  input logic       rst_ni,
  /// AXI Stream Bus Transmitter Port
  AXI_STREAM_BUS.Rx axis_in,
  /// AXI Stream Bus Receiver Port
  AXI_STREAM_BUS.Tx axis_out
);
  // AXI stream channels typedefs
  typedef logic [DataWidthIn-1:0]    tdata_in_t;
  typedef logic [DataWidthOut-1:0]   tdata_out_t;
  typedef logic [DataWidthIn/8-1:0]  tstrb_in_t;
  typedef logic [DataWidthOut/8-1:0] tstrb_out_t;
  typedef logic [DataWidthIn/8-1:0]  tkeep_in_t;
  typedef logic [DataWidthOut/8-1:0] tkeep_out_t;
  typedef logic [IdWidth-1:0]        tid_t;
  typedef logic [DestWidth-1:0]      tdest_t;
  typedef logic [UserWidth-1:0]      tuser_t;

  `AXI_STREAM_TYPEDEF_ALL(s_in, tdata_in_t, tstrb_in_t, tkeep_in_t, tid_t, tdest_t, tuser_t)
  `AXI_STREAM_TYPEDEF_ALL(s_out, tdata_out_t, tstrb_out_t, tkeep_out_t, tid_t, tdest_t, tuser_t)

  // AXI stream signals
  s_in_req_t s_in_req;
  s_out_req_t s_out_req;
  s_in_rsp_t s_in_rsp;
  s_out_rsp_t s_out_rsp;

  // connect modports to req/rsp signals
  `AXI_STREAM_ASSIGN_TO_REQ(s_in_req, axis_in)
  `AXI_STREAM_ASSIGN_FROM_RSP(axis_in, s_in_rsp)
  `AXI_STREAM_ASSIGN_FROM_REQ(axis_out, s_out_req)
  `AXI_STREAM_ASSIGN_TO_RSP(s_out_rsp, axis_out)

  axi_stream_dw_downsizer #(
    .DataWidthIn         (DataWidthIn),
    .DataWidthOut        (DataWidthOut),
    .IdWidth             (IdWidth),
    .DestWidth           (DestWidth),
    .UserWidth           (UserWidth),
    .axi_stream_in_req_t(s_in_req_t),
    .axi_stream_in_rsp_t(s_in_rsp_t),
    .axi_stream_out_req_t(s_out_req_t),
    .axi_stream_out_rsp_t(s_out_rsp_t)
  ) i_axi_stream_dw_downsizer (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .in_req_i (s_in_req),
    .in_rsp_o (s_in_rsp),
    .out_req_o(s_out_req),
    .out_rsp_i(s_out_rsp)
  );

endmodule : axi_stream_dw_downsizer_intf
