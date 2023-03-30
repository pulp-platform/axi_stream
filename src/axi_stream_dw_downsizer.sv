// Copyright (c) 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Authors:
// - Thiemo Zaugg <zauggth@ethz.ch>


/// An AXI Stream downsizer
module axi_stream_dw_downsizer #(
  parameter int unsigned DataWidthIn  = 64,
  parameter int unsigned DataWidthOut = 8 ,
  parameter int unsigned IdWidth      = 0 ,
  parameter int unsigned DestWidth    = 0 ,
  parameter int unsigned UserWidth    = 0
) (
  input logic       clk_i   ,
  input logic       rst_ni  ,
  AXI_STREAM_BUS.Tx axis_in ,
  AXI_STREAM_BUS.Rx axis_out
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
      axis_out.tdata = axis_in.tdata[DataWidthOut-1:0];
      axis_out.tstrb = axis_in.tstrb[StrbWidthOut-1:0];
      axis_out.tkeep = axis_in.tkeep[KeepWidthOut-1:0];
      axis_out.tid   = axis_in.tid;
      axis_out.tdest = axis_in.tdest;
      axis_out.tuser = axis_in.tuser;
    end else begin //all other sub-transfers can come from the stored data of the input stream
      axis_out.tdata = tdata_received_q[DataWidthOut-1:0];
      axis_out.tstrb = tstrb_received_q[StrbWidthOut-1:0];
      axis_out.tkeep = tkeep_received_q[KeepWidthOut-1:0];
      axis_out.tid   = tid_received_q;
      axis_out.tdest = tdest_received_q;
      axis_out.tuser = tuser_received_q;
    end
  end

  always_comb begin
    state_d         = state_q;
    counter_d       = 'd0;
    axis_out.tvalid = axis_in.tvalid;
    axis_in.tready  = axis_out.tready;
    axis_out.tlast  = 1'b0;

    tdata_received_d = tdata_received_q;
    tstrb_received_d = tstrb_received_q;
    tkeep_received_d = tkeep_received_q;
    tlast_received_d = tlast_received_q;
    tid_received_d   = tid_received_q;
    tdest_received_d = tdest_received_q;
    tuser_received_d = tuser_received_q;

    unique case (state_q)
      NoValidDataIn : begin
        if (axis_in.tvalid && axis_out.tready) begin
          state_d = AcceptDataIn;
        end
        if (axis_in.tvalid && !axis_out.tready) begin
          state_d = ValidDataInNoReadyOut;
        end
      end

      ValidDataInNoReadyOut : begin
        if (!axis_in.tvalid) begin
          state_d = NoValidDataIn;
        end
        if (axis_in.tvalid && axis_out.tready) begin
          state_d = AcceptDataIn;
        end
      end

      AcceptDataIn : begin
        if (axis_out.tready) begin
          state_d = DataOut;
        end else begin
          state_d = NoReadyInTransmission;
        end
      end

      NoReadyInTransmission : begin
        if (axis_out.tready) begin
          state_d = DataOut;
        end
      end

      DataOut : begin
        if (counter_q == MaxSubTransferIndex) begin
          if (!axis_in.tvalid) begin
            state_d = NoValidDataIn;
          end else if (axis_out.tready) begin
            state_d = AcceptDataIn;
          end else begin
            state_d = ValidDataInNoReadyOut;
          end
        end else begin
          if (!axis_out.tready) begin
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
      axis_out.tvalid = 1'b1;
      axis_in.tready  = 1'b1;
      // save new data from input axi stream to registers
      tdata_received_d = axis_in.tdata >> DataWidthOut;
      tstrb_received_d = axis_in.tstrb >> StrbWidthOut;
      tkeep_received_d = axis_in.tkeep >> KeepWidthOut;
      tlast_received_d = axis_in.tlast;
      tid_received_d   = axis_in.tid;
      tdest_received_d = axis_in.tdest;
      tuser_received_d = axis_in.tuser;
    end
    if (state_d == NoReadyInTransmission) begin
      axis_out.tvalid = 1'b1;
      axis_in.tready  = 1'b0;
      counter_d       = counter_q;
    end
    if (state_d == DataOut) begin
      axis_out.tvalid = 1'b1;
      axis_in.tready  = 1'b0;
      counter_d       = counter_q + 'd1;
      tdata_received_d = tdata_received_q >> DataWidthOut;
      tstrb_received_d = tstrb_received_q >> StrbWidthOut;
      tkeep_received_d = tkeep_received_q >> KeepWidthOut;

      if (counter_q == MaxSubTransferIndex - 1) begin
        // only output the tlast signal on the final sub-transfer
        axis_out.tlast = tlast_received_q;
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
