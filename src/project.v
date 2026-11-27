// HyperINet v2: Programmable Dual-Lane Non-von-Neumann Interaction-Net Processor
// Emitted directly from lib/silicon/inet-fabric.hypercubical
// Features: Dual-lane disjoint parallel firing (2 redexes/cycle), fused 8-bit NUM/ADD,
//           Lafont CON/DUP/ERA, external runtime graph loader, Tiny Tapeout Sky130 pinout.
module hyperinet_core (
  input  wire       clk,
  input  wire       rst_n,
  input  wire       ena,
  input  wire       load_en,
  input  wire [2:0] slot_sel,
  input  wire [1:0] field_sel,
  input  wire [7:0] load_data,
  output wire       done,
  output wire       dual_fire,
  output wire [2:0] redex_count,
  output wire [2:0] live_nodes,
  output wire [7:0] read_val
);
  localparam [2:0] K_FREE=3'd0, K_CON=3'd1, K_DUP=3'd2, K_ERA=3'd3, K_NUM=3'd4, K_ADD=3'd5, K_ADD1=3'd6;
  reg [2:0] kind [0:7];
  reg [4:0] p0   [0:7];
  reg [4:0] p1   [0:7];
  reg [4:0] p2   [0:7];
  reg [7:0] val  [0:7];
  reg [2:0] rcnt;
  integer i, j;
  // Combinational dual-lane disjoint active-pair scanner & free-slot allocator
  reg       fnd0, fnd1;
  reg [2:0] u0, v0, u1, v1, f0_idx, f1_idx;
  reg [1:0] free_cnt;
  reg [2:0] live_c;
  // Lane 1 fires in parallel iff it is disjoint from Lane 0 and does not need free-slot allocation
  wire l0_is_comm = fnd0 && ((kind[u0]==K_CON && kind[v0]==K_DUP) || (kind[u0]==K_DUP && kind[v0]==K_CON));
  always @(*) begin
    fnd0 = 1'b0; fnd1 = 1'b0; u0 = 3'd0; v0 = 3'd0; u1 = 3'd0; v1 = 3'd0;
    f0_idx = 3'd0; f1_idx = 3'd0; free_cnt = 2'd0; live_c = 3'd0;
    for (i = 0; i < 8; i = i + 1) begin
      if (kind[i] == K_FREE) begin
        if (free_cnt == 2'd0) f0_idx = i[2:0];
        if (free_cnt == 2'd1) f1_idx = i[2:0];
        if (free_cnt < 2'd2)  free_cnt = free_cnt + 2'd1;
      end else live_c = live_c + 3'd1;
    end
    for (i = 0; i < 8; i = i + 1) begin
      for (j = i + 1; j < 8; j = j + 1) begin
        if (kind[i] != K_FREE && kind[j] != K_FREE &&
            p0[i] == {j[2:0], 2'd0} && p0[j] == {i[2:0], 2'd0}) begin
          if (!fnd0) begin
            fnd0 = 1'b1; u0 = i[2:0]; v0 = j[2:0];
          end else if (!fnd1 && i[2:0] != u0 && i[2:0] != v0 && j[2:0] != u0 && j[2:0] != v0 &&
                       !((kind[i]==K_CON && kind[j]==K_DUP) || (kind[i]==K_DUP && kind[j]==K_CON))) begin
            fnd1 = 1'b1; u1 = i[2:0]; v1 = j[2:0];
          end
        end
      end
    end
  end
  assign dual_fire   = fnd0 && fnd1 && !l0_is_comm;
  assign done        = !fnd0;
  assign redex_count = rcnt;
  assign live_nodes  = live_c;
  assign read_val    = val[slot_sel];
  task automatic rewire(input [4:0] dst, input [4:0] new_ref);
    begin
      if (dst[1:0] == 2'd0)      p0[dst[4:2]] <= new_ref;
      else if (dst[1:0] == 2'd1) p1[dst[4:2]] <= new_ref;
      else if (dst[1:0] == 2'd2) p2[dst[4:2]] <= new_ref;
    end
  endtask
  // Single-lane interaction rule executor (shared by Lane 0 and Lane 1)
  task automatic fire_pair(input [2:0] ua, input [2:0] va, input allow_comm);
    reg [2:0] cn, dn;
    begin
      if (kind[ua] == kind[va]) begin
        // Annihilation: CON⋈CON, DUP⋈DUP, ERA⋈ERA
        if (kind[ua] == K_CON || kind[ua] == K_DUP) begin
          rewire(p1[ua], p1[va]); rewire(p1[va], p1[ua]);
          rewire(p2[ua], p2[va]); rewire(p2[va], p2[ua]);
        end
        kind[ua] <= K_FREE; kind[va] <= K_FREE;
      end else if (kind[ua] == K_ERA || kind[va] == K_ERA) begin
        cn = (kind[ua] == K_ERA) ? va : ua; dn = (kind[ua] == K_ERA) ? ua : va;
        if (kind[cn] == K_NUM) begin
          kind[cn] <= K_FREE; kind[dn] <= K_FREE;
        end else begin
          kind[cn] <= K_ERA; p0[cn] <= p1[cn]; rewire(p1[cn], {cn, 2'd0});
          kind[dn] <= K_ERA; p0[dn] <= p2[cn]; rewire(p2[cn], {dn, 2'd0});
        end
      end else if ((kind[ua]==K_NUM && kind[va]==K_ADD) || (kind[ua]==K_ADD && kind[va]==K_NUM)) begin
        // Fused curry: NUM(x) ⋈ ADD(op2, out) -> ADD1(x) wired to op2
        cn = (kind[ua]==K_NUM) ? ua : va; dn = (kind[ua]==K_NUM) ? va : ua;
        kind[cn] <= K_FREE;
        kind[dn] <= K_ADD1; val[dn] <= val[cn];
        p0[dn] <= p1[dn]; p1[dn] <= p2[dn]; rewire(p1[dn], {dn, 2'd0});
      end else if ((kind[ua]==K_NUM && kind[va]==K_ADD1) || (kind[ua]==K_ADD1 && kind[va]==K_NUM)) begin
        // Fused 8-bit add: NUM(y) ⋈ ADD1(x, out) -> NUM(x + y) wired to out
        cn = (kind[ua]==K_NUM) ? ua : va; dn = (kind[ua]==K_NUM) ? va : ua;
        kind[dn] <= K_FREE;
        kind[cn] <= K_NUM; val[cn] <= val[dn] + val[cn];
        p0[cn] <= p1[dn]; rewire(p1[dn], {cn, 2'd0});
      end else if ((kind[ua]==K_NUM && kind[va]==K_DUP) || (kind[ua]==K_DUP && kind[va]==K_NUM)) begin
        // Unboxed NUM duplication: NUM(x) ⋈ DUP(o1, o2) -> 2x NUM(x) in-place
        cn = (kind[ua]==K_NUM) ? ua : va; dn = (kind[ua]==K_NUM) ? va : ua;
        kind[cn] <= K_NUM; val[cn] <= val[cn]; p0[cn] <= p1[dn]; rewire(p1[dn], {cn, 2'd0});
        kind[dn] <= K_NUM; val[dn] <= val[cn]; p0[dn] <= p2[dn]; rewire(p2[dn], {dn, 2'd0});
      end else if (allow_comm && free_cnt == 2'd2) begin
        // Commutation Diamond: CON ⋈ DUP
        cn = (kind[ua]==K_CON) ? ua : va; dn = (kind[ua]==K_CON) ? va : ua;
        kind[cn]     <= K_DUP; p0[cn]     <= p1[cn]; p1[cn]     <= {dn, 2'd1}; p2[cn]     <= {f1_idx, 2'd1}; rewire(p1[cn], {cn, 2'd0});
        kind[f0_idx] <= K_DUP; p0[f0_idx] <= p2[cn]; p1[f0_idx] <= {dn, 2'd2}; p2[f0_idx] <= {f1_idx, 2'd2}; rewire(p2[cn], {f0_idx, 2'd0});
        kind[dn]     <= K_CON; p0[dn]     <= p1[dn]; p1[dn]     <= {cn, 2'd1}; p2[dn]     <= {f0_idx, 2'd1}; rewire(p1[dn], {dn, 2'd0});
        kind[f1_idx] <= K_CON; p0[f1_idx] <= p2[dn]; p1[f1_idx] <= {cn, 2'd2}; p2[f1_idx] <= {f0_idx, 2'd2}; rewire(p2[dn], {f1_idx, 2'd0});
      end
    end
  endtask
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rcnt <= 3'd0;
      for (i = 0; i < 8; i = i + 1) begin
        kind[i] <= K_FREE; p0[i] <= 5'd3; p1[i] <= 5'd3; p2[i] <= 5'd3; val[i] <= 8'd0;
      end
      // Built-in dual-lane parallel showcase: (17 + 25 = 42) || DUP(10)
      kind[0] <= K_NUM; val[0] <= 8'd17; p0[0] <= {3'd1, 2'd0};
      kind[1] <= K_ADD; p0[1] <= {3'd0, 2'd0}; p1[1] <= {3'd2, 2'd0}; p2[1] <= {3'd0, 2'd3};
      kind[2] <= K_NUM; val[2] <= 8'd25; p0[2] <= {3'd1, 2'd1};
      kind[3] <= K_NUM; val[3] <= 8'd10; p0[3] <= {3'd4, 2'd0};
      kind[4] <= K_DUP; p0[4] <= {3'd3, 2'd0}; p1[4] <= {3'd1, 2'd3}; p2[4] <= {3'd2, 2'd3};
    end else if (load_en) begin
      // Runtime external graph loader (field_sel: 0=kind/clear, 1=p0, 2=p1, 3=val; p2=EXT)
      if (field_sel == 2'd0) begin
        kind[slot_sel] <= load_data[2:0]; p2[slot_sel] <= 5'd3;
        if (load_data[7]) rcnt <= 3'd0;
      end else if (field_sel == 2'd1) p0[slot_sel]  <= load_data[4:0];
      else if (field_sel == 2'd2)     p1[slot_sel]  <= load_data[4:0];
      else                            val[slot_sel] <= load_data;
    end else if (ena && fnd0) begin
      fire_pair(u0, v0, 1'b1);
      if (dual_fire) begin
        fire_pair(u1, v1, 1'b0);
        rcnt <= rcnt + 3'd2;
      end else begin
        rcnt <= rcnt + 3'd1;
      end
    end
  end
endmodule
// Tiny Tapeout SkyWater 130nm drop-in top-level wrapper (programmable + dual-lane)
module tt_um_hyperinet (
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);
  wire done_w, dual_w;
  wire [2:0] rcnt_w, live_w;
  wire [7:0] rval_w;
  hyperinet_core u_core (
    .clk(clk), .rst_n(rst_n), .ena(ena),
    .load_en(uio_in[0]), .slot_sel(uio_in[3:1]), .field_sel(uio_in[5:4]), .load_data(ui_in),
    .done(done_w), .dual_fire(dual_w), .redex_count(rcnt_w), .live_nodes(live_w), .read_val(rval_w)
  );
  assign uo_out  = uio_in[7] ? rval_w : {done_w, dual_w, rcnt_w, live_w};
  assign uio_out = 8'd0;
  assign uio_oe  = 8'd0;
endmodule
