`uvm_analysis_imp_decl(_drv)
`uvm_analysis_imp_decl(_mon)
`uvm_analysis_imp_decl(_axi)
`uvm_analysis_imp_decl(_slv)

class scoreboard extends uvm_scoreboard;

  `uvm_component_utils(scoreboard)

  typedef enum bit [1:0] {
    DECODE_OK,
    DECODE_NO_MATCH,
    DECODE_MULTI_MATCH
  } decode_result_e;

  typedef struct {
    axi_transaction tr;
    logic [31:0]    bams0;
    logic [31:0]    bams1;
    logic [31:0]    bams2;
    logic [31:0]    bir;
  } axi_snapshot_t;

  // ============================================================
  // Analysis exports
  // ============================================================

  uvm_analysis_imp_drv #(apb_master_seq_item,   scoreboard) drv_export;
  uvm_analysis_imp_mon #(apb_master_seq_item,   scoreboard) mon_export;
  uvm_analysis_imp_axi #(axi_transaction,       scoreboard) axi_export;
  uvm_analysis_imp_slv #(apb_slave_transaction, scoreboard) slv_export;

  // ============================================================
  // Queues
  // ============================================================

  axi_snapshot_t        axi_queue[$];
  apb_slave_transaction slv_queue[$];

  // ============================================================
  // RAL model
  // ============================================================

  apb_reg_block regmodel;

  // ============================================================
  // Constructor
  // ============================================================

  function new(string name = "scoreboard", uvm_component parent = null);
    super.new(name, parent);

    drv_export = new("drv_export", this);
    mon_export = new("mon_export", this);
    axi_export = new("axi_export", this);
    slv_export = new("slv_export", this);
  endfunction

  // ============================================================
  // Build phase
  // ============================================================

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(apb_reg_block)::get(this, "", "regmodel", regmodel)) begin
      `uvm_fatal("SCB_RAL",
        "Failed to get regmodel from uvm_config_db. Check env: uvm_config_db#(apb_reg_block)::set(this, \"sb\", \"regmodel\", regmodel)")
    end
  endfunction : build_phase

  // ============================================================
  // Log helpers
  // ============================================================

  function string axi_info(axi_transaction tr);

    return $sformatf("Burst=%s Size=%s Len=%0d AXIAddr=0x%08h",
                     tr.burst_type.name(),
                     tr.size_type.name(),
                     tr.len,
                     tr.addr);

  endfunction

  function string axi_beat_info(
    axi_transaction tr,
    int unsigned beat,
    logic [31:0] beat_addr
  );

    return $sformatf("Burst=%s Size=%s Len=%0d Beat=%0d/%0d AXIAddr=0x%08h BeatAddr=0x%08h",
                     tr.burst_type.name(),
                     tr.size_type.name(),
                     tr.len,
                     beat,
                     tr.len,
                     tr.addr,
                     beat_addr);

  endfunction

  function string axi_resp_name(axi_transaction::error_response resp);

    case (resp)

      axi_transaction::OKAY:
        return "OKAY";

      axi_transaction::EXOKAY:
        return "EXOKAY";

      axi_transaction::SLVERR:
        return "SLVERR";

      axi_transaction::DECERR:
        return "DECERR";

      default:
        return "UNKNOWN";

    endcase

  endfunction

  function string snapshot_info(axi_snapshot_t item);

    return $sformatf("SNAPSHOT: BAMS0=0x%08h BAMS1=0x%08h BAMS2=0x%08h BIR=0x%08h DecErrEn=%0b DecErrSt=%0b",
                     item.bams0,
                     item.bams1,
                     item.bams2,
                     item.bir,
                     item.bir[0],
                     item.bir[1]);

  endfunction

  function string bir_info();

    return $sformatf("RAL_BIR=0x%08h DecErrEn=%0b DecErrSt=%0b",
                     get_bir_mirror(),
                     get_bir_mirror()[0],
                     get_bir_mirror()[1]);

  endfunction

  // ============================================================
  // RAL mirror helpers
  // ============================================================

  function logic [31:0] get_reg_mirror32(uvm_reg rg);

    uvm_reg_data_t value;

    value = rg.get_mirrored_value();

    return value[31:0];

  endfunction

  function logic [31:0] get_bams0_mirror();

    return get_reg_mirror32(regmodel.BAMS0);

  endfunction

  function logic [31:0] get_bams1_mirror();

    return get_reg_mirror32(regmodel.BAMS1);

  endfunction

  function logic [31:0] get_bams2_mirror();

    return get_reg_mirror32(regmodel.BAMS2);

  endfunction

  function logic [31:0] get_bir_mirror();

    return get_reg_mirror32(regmodel.BIR);

  endfunction

  // ============================================================
  // BIR behavior on decode error
  //
  // BIR[0] = DecErrEn
  //   1: enable DecErrIntr and allow BIR[1] to be set
  //   0: disable DecErrIntr and keep BIR[1] = 0 on decode error
  //
  // BIR[1] = DecErrSt
  //   W1C status bit
  //   set to 1 only when decode error occurs while DecErrEn=1
  // ============================================================

  function bit update_bir_on_decode_error(
    logic [31:0] addr,
    axi_snapshot_t item
  );

    bit decerr_en;

    decerr_en = item.bir[0];

    if (decerr_en) begin

      void'(regmodel.BIR.DecErrSt.predict(
        1'b1,
        -1,
        UVM_PREDICT_DIRECT
      ));

      `uvm_info("SCB_BIR",
        $sformatf("Decode error at addr=0x%08h while snapshot DecErrEn=1. Predict BIR.DecErrSt=1. %s | %s",
                  addr,
                  snapshot_info(item),
                  bir_info()),
        UVM_LOW)

    end
    else begin

      void'(regmodel.BIR.DecErrSt.predict(
        1'b0,
        -1,
        UVM_PREDICT_DIRECT
      ));

      `uvm_info("SCB_BIR_DISABLED",
        $sformatf("Decode error at addr=0x%08h while snapshot DecErrEn=0. DecErrIntr must stay 0 and BIR.DecErrSt must stay 0. %s | %s",
                  addr,
                  snapshot_info(item),
                  bir_info()),
        UVM_LOW)

    end

    return decerr_en;

  endfunction

  // ============================================================
  // Analysis write functions
  //
  // APB register checking is handled by RAL predictor.
  // drv_export/mon_export are kept to avoid changing env connection.
  //
  // Important remap logic:
  // write_axi() captures BAMS/BIR snapshot at the time AXI transaction
  // is received by the scoreboard.
  // ============================================================

  virtual function void write_drv(apb_master_seq_item tr);

    `uvm_info("SCB_DRV_OBS",
      $sformatf("Observed APB DRV: addr=0x%08h we=%0b wdata=0x%08h rdata=0x%08h strb=4'b%04b",
                tr.addr,
                tr.we,
                tr.wdata,
                tr.rdata,
                tr.strb),
      UVM_HIGH)

  endfunction

  virtual function void write_mon(apb_master_seq_item tr);

    `uvm_info("SCB_MON_OBS",
      $sformatf("Observed APB MON: addr=0x%08h we=%0b wdata=0x%08h rdata=0x%08h strb=4'b%04b | RAL now: BAMS0=0x%08h BAMS1=0x%08h BAMS2=0x%08h BIR=0x%08h",
                tr.addr,
                tr.we,
                tr.wdata,
                tr.rdata,
                tr.strb,
                get_bams0_mirror(),
                get_bams1_mirror(),
                get_bams2_mirror(),
                get_bir_mirror()),
      UVM_HIGH)

  endfunction

  virtual function void write_axi(axi_transaction tr);

    axi_transaction copy;
    axi_snapshot_t  item;

    if (!$cast(copy, tr.clone())) begin
      `uvm_error("SCB_AXI_CAST", "Failed to clone AXI transaction")
      return;
    end

    item.tr    = copy;
    item.bams0 = get_bams0_mirror();
    item.bams1 = get_bams1_mirror();
    item.bams2 = get_bams2_mirror();
    item.bir   = get_bir_mirror();

    axi_queue.push_back(item);

    `uvm_info("SCB_AXI_PUSH",
      $sformatf("Push AXI: type=%s %s data_size=%0d strb_size=%0d error_size=%0d | %s",
                copy.xact_type.name(),
                axi_info(copy),
                copy.data.size(),
                copy.strb.size(),
                copy.error.size(),
                snapshot_info(item)),
      UVM_LOW)

  endfunction

  virtual function void write_slv(apb_slave_transaction tr);

    apb_slave_transaction copy;

    if (!$cast(copy, tr.clone())) begin
      `uvm_error("SCB_SLV_CAST", "Failed to clone APB slave transaction")
      return;
    end

    slv_queue.push_back(copy);

    `uvm_info("SCB_SLV_PUSH",
      $sformatf("Push APB SLV: type=%s psel=%s addr=0x%08h data=0x%08h strb=4'b%04b decerr=%0b error=%s",
                copy.xact_type.name(),
                copy.psel.name(),
                copy.addr,
                copy.data,
                copy.strb,
                copy.decerr,
                copy.error.name()),
      UVM_LOW)

  endfunction

  // ============================================================
  // Decode helpers using snapshot, not final RAL mirror
  // ============================================================

  function int unsigned bams_size_bytes(logic [1:0] size_sel);

    case (size_sel)

      2'b00:
        return 1 * 1024;

      2'b01:
        return 2 * 1024;

      2'b10:
        return 4 * 1024;

      2'b11:
        return 8 * 1024;

      default:
        return 1 * 1024;

    endcase

  endfunction

  function logic [31:0] bams_base_addr(logic [31:0] bams_val);

    return {bams_val[31:10], 10'b0};

  endfunction

  function bit addr_match_bams(
    logic [31:0] addr,
    logic [31:0] bams_val
  );

    logic [31:0] base_addr;
    int unsigned size_byte;

    base_addr = bams_base_addr(bams_val);
    size_byte = bams_size_bytes(bams_val[1:0]);

    return ((addr >= base_addr) &&
            (addr <  (base_addr + size_byte)));

  endfunction

  function apb_slave_transaction::psel_choose predict_psel_from_snapshot(
    logic [31:0] addr,
    axi_snapshot_t item,
    output decode_result_e dec_result
  );

    bit match0;
    bit match1;
    bit match2;
    int match_count;

    match0 = addr_match_bams(addr, item.bams0);
    match1 = addr_match_bams(addr, item.bams1);
    match2 = addr_match_bams(addr, item.bams2);

    match_count = match0 + match1 + match2;

    if (match_count == 1) begin
      dec_result = DECODE_OK;

      if (match0)
        return apb_slave_transaction::PSEL0;
      else if (match1)
        return apb_slave_transaction::PSEL1;
      else
        return apb_slave_transaction::PSEL2;
    end

    else if (match_count == 0) begin
      dec_result = DECODE_NO_MATCH;

      `uvm_info("SCB_DECODE_NO_MATCH",
        $sformatf("Decode NO_MATCH. Addr=0x%08h does not match any slave using snapshot. %s",
                  addr,
                  snapshot_info(item)),
        UVM_LOW)

      return apb_slave_transaction::PSEL_NONE;
    end

    else begin
      dec_result = DECODE_MULTI_MATCH;

      `uvm_info("SCB_DECODE_MULTI_MATCH",
        $sformatf("Decode MULTI_MATCH. Addr=0x%08h matches multiple slaves. match0=%0b match1=%0b match2=%0b using snapshot. %s",
                  addr,
                  match0,
                  match1,
                  match2,
                  snapshot_info(item)),
        UVM_LOW)

      return apb_slave_transaction::PSEL_MULTI;
    end

  endfunction

  // ============================================================
  // AXI helper functions
  // ============================================================

  function int unsigned get_size_bytes(axi_transaction tr);

    case (tr.size_type)

      axi_transaction::BYTE_1:
        return 1;

      axi_transaction::BYTE_2:
        return 2;

      axi_transaction::BYTE_4:
        return 4;

      default: begin
        `uvm_error("SCB_SIZE",
          $sformatf("Unsupported AXI size_type=%0d", tr.size_type))
        return 0;
      end

    endcase

  endfunction

  function logic [31:0] get_next_axi_addr(
    axi_transaction tr,
    logic [31:0]    cur_addr,
    int unsigned    size_bytes,
    int unsigned    total_bytes,
    logic [31:0]    wrap_lower,
    logic [31:0]    wrap_upper
  );

    logic [31:0] next_addr;

    next_addr = cur_addr;

    case (tr.burst_type)

      axi_transaction::FIXED: begin
        next_addr = cur_addr;
      end

      axi_transaction::INCR: begin
        next_addr = cur_addr + size_bytes;
      end

      axi_transaction::WRAP: begin
        next_addr = cur_addr + size_bytes;

        if (next_addr >= wrap_upper)
          next_addr = wrap_lower + (next_addr - wrap_upper);
      end

      default: begin
        next_addr = cur_addr + size_bytes;
      end

    endcase

    return next_addr;

  endfunction

  function logic [3:0] calc_apb_pstrb(
    logic [31:0] addr,
    int unsigned size_bytes,
    logic [3:0]  axi_strb
  );

    return axi_strb;

  endfunction

  function logic [31:0] align_axi_wdata_to_apb(
    logic [31:0] beat_data,
    logic [31:0] addr,
    int unsigned size_bytes
  );

    logic [31:0] apb_data;

    apb_data = 32'h0000_0000;

    case (size_bytes)

      1:
        apb_data[7:0] = beat_data[7:0];

      2:
        apb_data[15:0] = beat_data[15:0];

      4:
        apb_data[31:0] = beat_data[31:0];

      default:
        apb_data = 32'h0000_0000;

    endcase

    return apb_data;

  endfunction

  function logic [31:0] pack_apb_prdata_to_axi_rdata(
    logic [31:0] apb_prdata,
    int unsigned size_bytes
  );

    logic [31:0] exp_rdata;

    exp_rdata = 32'h0000_0000;

    case (size_bytes)

      1:
        exp_rdata[7:0] = apb_prdata[7:0];

      2:
        exp_rdata[15:0] = apb_prdata[15:0];

      4:
        exp_rdata[31:0] = apb_prdata[31:0];

      default:
        exp_rdata = 32'h0000_0000;

    endcase

    return exp_rdata;

  endfunction

  function axi_transaction::error_response apb_error_to_axi_resp(
    apb_slave_transaction act
  );

    if (act.decerr == 1'b1)
      return axi_transaction::DECERR;
    else if (act.error == apb_slave_transaction::ERROR)
      return axi_transaction::SLVERR;
    else
      return axi_transaction::OKAY;

  endfunction

  // ============================================================
  // Queue helpers
  // ============================================================

  function int find_decode_event_index(
    logic [31:0] exp_addr,
    apb_slave_transaction::psel_choose exp_psel
  );

    int found_idx;

    found_idx = -1;

    for (int i = 0; i < slv_queue.size(); i++) begin
      if ((slv_queue[i].decerr == 1'b1) &&
          (slv_queue[i].addr   == exp_addr) &&
          (slv_queue[i].psel   == exp_psel)) begin
        found_idx = i;
        break;
      end
    end

    return found_idx;

  endfunction

  function int find_normal_slv_index(
    logic [31:0] addr,
    apb_slave_transaction::psel_choose psel,
    apb_slave_transaction::xact_type_enum xact_type
  );

    int found_idx;

    found_idx = -1;

    for (int i = 0; i < slv_queue.size(); i++) begin
      if ((slv_queue[i].decerr    == 1'b0) &&
          (slv_queue[i].addr      == addr) &&
          (slv_queue[i].psel      == psel) &&
          (slv_queue[i].xact_type == xact_type)) begin
        found_idx = i;
        break;
      end
    end

    return found_idx;

  endfunction

  function void drop_leftover_decerr_events();

    int i;

    i = 0;

    while (i < slv_queue.size()) begin
      if (slv_queue[i].decerr == 1'b1) begin
        `uvm_info("SCB_DROP_DECERR_EVENT",
          $sformatf("Drop unused DecErr event: addr=0x%08h psel=%s error=%s",
                    slv_queue[i].addr,
                    slv_queue[i].psel.name(),
                    slv_queue[i].error.name()),
          UVM_LOW)

        slv_queue.delete(i);
      end
      else begin
        i++;
      end
    end

  endfunction

  // ============================================================
  // AXI response checks
  // ============================================================

  function void check_axi_bresp(
    axi_snapshot_t item,
    axi_transaction::error_response exp_resp
  );

    axi_transaction tr;
    axi_transaction::error_response act_resp;

    tr = item.tr;

    if (tr.error.size() < 1) begin
      `uvm_error("SCB_AXI_BRESP",
        $sformatf("AXI BRESP missing. %s error_size=%0d | %s",
                  axi_info(tr),
                  tr.error.size(),
                  snapshot_info(item)))
      return;
    end

    act_resp = tr.error[0];

    if (act_resp !== exp_resp) begin
      `uvm_error("SCB_AXI_BRESP",
        $sformatf("AXI BRESP mismatch. %s Exp=%s Act=%s | %s",
                  axi_info(tr),
                  axi_resp_name(exp_resp),
                  axi_resp_name(act_resp),
                  snapshot_info(item)))
    end
    else begin
      `uvm_info("SCB_AXI_BRESP_OK",
        $sformatf("AXI BRESP OK. %s Resp=%s | %s",
                  axi_info(tr),
                  axi_resp_name(act_resp),
                  snapshot_info(item)),
        UVM_LOW)
    end

  endfunction

  function void check_axi_rresp(
    axi_snapshot_t item,
    int unsigned beat,
    int unsigned error_offset,
    axi_transaction::error_response exp_resp
  );

    axi_transaction tr;
    axi_transaction::error_response act_resp;
    int unsigned idx;

    tr = item.tr;
    idx = error_offset + beat;

    if (tr.error.size() <= idx) begin
      `uvm_error("SCB_AXI_RRESP",
        $sformatf("AXI RRESP missing. %s Beat=%0d/%0d ErrorIdx=%0d ErrorSize=%0d | %s",
                  axi_info(tr),
                  beat,
                  tr.len,
                  idx,
                  tr.error.size(),
                  snapshot_info(item)))
      return;
    end

    act_resp = tr.error[idx];

    if (act_resp !== exp_resp) begin
      `uvm_error("SCB_AXI_RRESP",
        $sformatf("AXI RRESP mismatch. %s Beat=%0d/%0d Exp=%s Act=%s | %s",
                  axi_info(tr),
                  beat,
                  tr.len,
                  axi_resp_name(exp_resp),
                  axi_resp_name(act_resp),
                  snapshot_info(item)))
    end
    else begin
      `uvm_info("SCB_AXI_RRESP_OK",
        $sformatf("AXI RRESP OK. %s Beat=%0d/%0d Resp=%s | %s",
                  axi_info(tr),
                  beat,
                  tr.len,
                  axi_resp_name(act_resp),
                  snapshot_info(item)),
        UVM_LOW)
    end

  endfunction

  // ============================================================
  // Decode error interrupt check
  // ============================================================

  function bit check_decode_error_interrupt_enabled(
    string tag,
    axi_snapshot_t item,
    logic [31:0] exp_addr,
    decode_result_e dec_result
  );

    int match_idx;
    bit has_error;

    axi_transaction tr;
    apb_slave_transaction act;
    apb_slave_transaction::psel_choose exp_psel;

    tr = item.tr;
    has_error = 1'b0;

    if (dec_result == DECODE_NO_MATCH)
      exp_psel = apb_slave_transaction::PSEL_NONE;
    else if (dec_result == DECODE_MULTI_MATCH)
      exp_psel = apb_slave_transaction::PSEL_MULTI;
    else begin
      `uvm_error(tag,
        $sformatf("check_decode_error_interrupt_enabled called with DECODE_OK. %s",
                  axi_info(tr)))
      return 0;
    end

    match_idx = find_decode_event_index(exp_addr, exp_psel);

    if (match_idx < 0) begin
      `uvm_error(tag,
        $sformatf("Missing DecErrIntr event while snapshot DecErrEn=1. %s ExpDecErrAddr=0x%08h Decode=%s ExpectedPSEL=%s slv_q_size=%0d | %s",
                  axi_info(tr),
                  exp_addr,
                  dec_result.name(),
                  exp_psel.name(),
                  slv_queue.size(),
                  snapshot_info(item)))
      return 0;
    end

    act = slv_queue[match_idx];
    slv_queue.delete(match_idx);

    if (act.decerr !== 1'b1) begin
      has_error = 1'b1;

      `uvm_error(tag,
        $sformatf("Matched DecErr event has decerr=0 while snapshot DecErrEn=1. %s ExpAddr=0x%08h ActAddr=0x%08h | %s",
                  axi_info(tr),
                  exp_addr,
                  act.addr,
                  snapshot_info(item)))
    end

    if (act.psel !== exp_psel) begin
      has_error = 1'b1;

      `uvm_error(tag,
        $sformatf("Decode-error PSEL mismatch. %s ExpAddr=0x%08h ExpPSEL=%s ActPSEL=%s | %s",
                  axi_info(tr),
                  exp_addr,
                  exp_psel.name(),
                  act.psel.name(),
                  snapshot_info(item)))
    end

    if (act.error !== apb_slave_transaction::ERROR) begin
      has_error = 1'b1;

      `uvm_error(tag,
        $sformatf("Decode-error event should have ERROR. %s ExpAddr=0x%08h ActError=%s | %s",
                  axi_info(tr),
                  exp_addr,
                  act.error.name(),
                  snapshot_info(item)))
    end

    if (!has_error) begin
      `uvm_info(tag,
        $sformatf("DecErrIntr OK because snapshot DecErrEn=1. %s DecErrAddr=0x%08h Decode=%s PSEL=%s DecErr=%0b Error=%s | %s",
                  axi_info(tr),
                  act.addr,
                  dec_result.name(),
                  act.psel.name(),
                  act.decerr,
                  act.error.name(),
                  snapshot_info(item)),
        UVM_LOW)
    end

    return !has_error;

  endfunction

  function bit check_decode_error_interrupt_disabled_for_addr(
    string tag,
    axi_snapshot_t item,
    int unsigned beat,
    logic [31:0] exp_addr,
    decode_result_e dec_result
  );

    int match_idx;
    axi_transaction tr;
    apb_slave_transaction act;
    apb_slave_transaction::psel_choose exp_psel;

    tr = item.tr;

    if (dec_result == DECODE_NO_MATCH)
      exp_psel = apb_slave_transaction::PSEL_NONE;
    else if (dec_result == DECODE_MULTI_MATCH)
      exp_psel = apb_slave_transaction::PSEL_MULTI;
    else begin
      `uvm_error(tag,
        $sformatf("check_decode_error_interrupt_disabled_for_addr called with DECODE_OK. %s",
                  axi_beat_info(tr, beat, exp_addr)))
      return 0;
    end

    match_idx = find_decode_event_index(exp_addr, exp_psel);

    if (match_idx >= 0) begin

      act = slv_queue[match_idx];
      slv_queue.delete(match_idx);

      `uvm_error(tag,
        $sformatf("DecErrIntr asserted even though snapshot DecErrEn=0. This is not allowed. %s Decode=%s ExpPSEL=%s ActAddr=0x%08h ActPSEL=%s DecErr=%0b Error=%s | %s",
                  axi_beat_info(tr, beat, exp_addr),
                  dec_result.name(),
                  exp_psel.name(),
                  act.addr,
                  act.psel.name(),
                  act.decerr,
                  act.error.name(),
                  snapshot_info(item)))

      return 0;
    end

    `uvm_info(tag,
      $sformatf("DecErrIntr correctly not asserted because snapshot DecErrEn=0. %s Decode=%s ExpectedPSEL=%s | %s",
                axi_beat_info(tr, beat, exp_addr),
                dec_result.name(),
                exp_psel.name(),
                snapshot_info(item)),
      UVM_LOW)

    return 1;

  endfunction

  // ============================================================
  // APB slave beat check
  // ============================================================

  function bit check_apb_write_beat(
    axi_snapshot_t        item,
    int unsigned          beat,
    int unsigned          data_offset,
    logic [31:0]          beat_addr,
    int unsigned          size_bytes,
    apb_slave_transaction::psel_choose exp_psel,
    apb_slave_transaction act
  );

    bit has_error;
    axi_transaction tr;
    logic [31:0] beat_data;
    logic [31:0] exp_data;
    logic [3:0]  axi_strb;
    logic [3:0]  exp_strb;
    int unsigned data_idx;

    tr = item.tr;
    has_error = 1'b0;
    data_idx  = data_offset + beat;

    if (act.xact_type !== apb_slave_transaction::WRITE) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_TYPE",
        $sformatf("APB SLV TYPE mismatch. Exp=WRITE Act=%s %s | %s",
                  act.xact_type.name(),
                  axi_beat_info(tr, beat, beat_addr),
                  snapshot_info(item)))
    end

    if (act.psel !== exp_psel) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_PSEL",
        $sformatf("APB SLV PSEL mismatch. %s Exp=%s Act=%s | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  exp_psel.name(),
                  act.psel.name(),
                  snapshot_info(item)))
    end

    if (act.addr !== beat_addr) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_ADDR",
        $sformatf("APB SLV ADDR mismatch. %s Exp=0x%08h Act=0x%08h | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  beat_addr,
                  act.addr,
                  snapshot_info(item)))
    end

    if (act.decerr !== 1'b0) begin
      has_error = 1'b1;

      `uvm_error("SCB_WR_DECERR_FALSE",
        $sformatf("DecErr event appears in normal WRITE access. %s ActDecErr=%0b | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  act.decerr,
                  snapshot_info(item)))
    end

    if (tr.data.size() > data_idx) begin
      beat_data = tr.data[data_idx][31:0];
    end
    else begin
      beat_data = 32'h0000_0000;
      has_error = 1'b1;

      `uvm_error("SCB_AXI_DATA",
        $sformatf("AXI WRITE data underflow. %s DataIdx=%0d DataSize=%0d | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  data_idx,
                  tr.data.size(),
                  snapshot_info(item)))
    end

    if (tr.strb.size() > beat) begin
      axi_strb = tr.strb[beat][3:0];
    end
    else begin
      axi_strb = 4'hF;

      `uvm_warning("SCB_AXI_STRB",
        $sformatf("AXI WRITE strb missing. %s Use 4'hF | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  snapshot_info(item)))
    end

    exp_data = align_axi_wdata_to_apb(beat_data, beat_addr, size_bytes);
    exp_strb = calc_apb_pstrb(beat_addr, size_bytes, axi_strb);

    if (act.data !== exp_data) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_WDATA",
        $sformatf("APB SLV WDATA mismatch. %s Exp=0x%08h Act=0x%08h AXI_DATA=0x%08h | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  exp_data,
                  act.data,
                  beat_data,
                  snapshot_info(item)))
    end

    if (act.strb !== exp_strb) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_STRB",
        $sformatf("APB SLV PSTRB mismatch. %s Exp=4'b%04b Act=4'b%04b AXI_STRB=4'b%04b | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  exp_strb,
                  act.strb,
                  axi_strb,
                  snapshot_info(item)))
    end

    if (!has_error) begin
      if (act.error == apb_slave_transaction::NO_ERROR) begin
        `uvm_info("SCB_APB_WR_STATUS_OK",
          $sformatf("APB WRITE request OK, response NO_ERROR. %s Data=0x%08h Strb=4'b%04b PSEL=%s PSLVERR=%s | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    act.data,
                    act.strb,
                    act.psel.name(),
                    act.error.name(),
                    snapshot_info(item)),
          UVM_LOW)
      end
      else begin
        `uvm_info("SCB_APB_WR_STATUS_ERR",
          $sformatf("APB WRITE request OK, response ERROR. %s Data=0x%08h Strb=4'b%04b PSEL=%s PSLVERR=%s. AXI BRESP should be SLVERR. | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    act.data,
                    act.strb,
                    act.psel.name(),
                    act.error.name(),
                    snapshot_info(item)),
          UVM_LOW)
      end
    end

    return !has_error;

  endfunction

  function bit check_apb_read_beat(
    axi_snapshot_t        item,
    int unsigned          beat,
    int unsigned          data_offset,
    int unsigned          error_offset,
    logic [31:0]          beat_addr,
    int unsigned          size_bytes,
    apb_slave_transaction::psel_choose exp_psel,
    apb_slave_transaction act
  );

    bit has_error;
    axi_transaction tr;
    logic [31:0] exp_rdata;
    logic [31:0] act_axi_rdata;
    int unsigned data_idx;
    axi_transaction::error_response exp_rresp;

    tr = item.tr;
    has_error = 1'b0;
    data_idx  = data_offset + beat;

    if (act.xact_type !== apb_slave_transaction::READ) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_TYPE",
        $sformatf("APB SLV TYPE mismatch. Exp=READ Act=%s %s | %s",
                  act.xact_type.name(),
                  axi_beat_info(tr, beat, beat_addr),
                  snapshot_info(item)))
    end

    if (act.psel !== exp_psel) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_PSEL",
        $sformatf("APB SLV PSEL mismatch. %s Exp=%s Act=%s | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  exp_psel.name(),
                  act.psel.name(),
                  snapshot_info(item)))
    end

    if (act.addr !== beat_addr) begin
      has_error = 1'b1;

      `uvm_error("SCB_SLV_ADDR",
        $sformatf("APB SLV ADDR mismatch. %s Exp=0x%08h Act=0x%08h | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  beat_addr,
                  act.addr,
                  snapshot_info(item)))
    end

    if (act.decerr !== 1'b0) begin
      has_error = 1'b1;

      `uvm_error("SCB_RD_DECERR_FALSE",
        $sformatf("DecErr event appears in normal READ access. %s ActDecErr=%0b | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  act.decerr,
                  snapshot_info(item)))
    end

    if (!has_error) begin
      if (act.error == apb_slave_transaction::NO_ERROR) begin
        `uvm_info("SCB_APB_RD_STATUS_OK",
          $sformatf("APB READ request OK, response NO_ERROR. %s PRDATA=0x%08h PSEL=%s PSLVERR=%s. AXI RRESP should be OKAY and RDATA will be checked. | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    act.data,
                    act.psel.name(),
                    act.error.name(),
                    snapshot_info(item)),
          UVM_LOW)
      end
      else begin
        `uvm_info("SCB_APB_RD_STATUS_ERR",
          $sformatf("APB READ request OK, response ERROR. %s PRDATA=0x%08h PSEL=%s PSLVERR=%s. AXI RRESP should be SLVERR and RDATA will not be checked. | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    act.data,
                    act.psel.name(),
                    act.error.name(),
                    snapshot_info(item)),
          UVM_LOW)
      end
    end

    exp_rresp = apb_error_to_axi_resp(act);

    check_axi_rresp(
      item,
      beat,
      error_offset,
      exp_rresp
    );

    if (act.error == apb_slave_transaction::NO_ERROR) begin

      if (tr.data.size() <= data_idx) begin
        has_error = 1'b1;

        `uvm_error("SCB_AXI_RDATA",
          $sformatf("AXI READ data underflow. %s DataIdx=%0d DataSize=%0d | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    data_idx,
                    tr.data.size(),
                    snapshot_info(item)))
      end
      else begin

        exp_rdata     = pack_apb_prdata_to_axi_rdata(act.data, size_bytes);
        act_axi_rdata = tr.data[data_idx][31:0];

        if (act_axi_rdata !== exp_rdata) begin
          has_error = 1'b1;

          `uvm_error("SCB_AXI_RDATA",
            $sformatf("AXI RDATA mismatch. %s SizeBytes=%0d Exp=0x%08h Act=0x%08h APB_PRDATA=0x%08h | %s",
                      axi_beat_info(tr, beat, beat_addr),
                      size_bytes,
                      exp_rdata,
                      act_axi_rdata,
                      act.data,
                      snapshot_info(item)))
        end
        else begin
          `uvm_info("SCB_AXI_RDATA_OK",
            $sformatf("AXI RDATA OK. %s SizeBytes=%0d ExpRDATA=0x%08h ActRDATA=0x%08h APB_PRDATA=0x%08h | %s",
                      axi_beat_info(tr, beat, beat_addr),
                      size_bytes,
                      exp_rdata,
                      act_axi_rdata,
                      act.data,
                      snapshot_info(item)),
            UVM_LOW)
        end

      end
    end
    else begin
      `uvm_info("SCB_AXI_RDATA_NOT_CHECKED",
        $sformatf("AXI RDATA not checked because APB read returned ERROR. %s APB_PRDATA=0x%08h APB_ERR=%s | %s",
                  axi_beat_info(tr, beat, beat_addr),
                  act.data,
                  act.error.name(),
                  snapshot_info(item)),
        UVM_LOW)
    end

    return !has_error;

  endfunction

  // ============================================================
  // AXI to APB checking
  // ============================================================

  function void check_axi_write_to_apb(
    axi_snapshot_t item,
    int unsigned data_offset = 0
  );

    axi_transaction tr;

    int unsigned num_beats;
    int unsigned size_bytes;
    int unsigned total_bytes;

    logic [31:0] beat_addr;
    logic [31:0] wrap_lower;
    logic [31:0] wrap_upper;

    int beat;
    int act_idx;

    bit has_apb_slverr;
    bit has_decerr;
    bit decerr_intr_enabled_for_this_xact;
    bit decerr_event_checked;

    decode_result_e dec_result;
    decode_result_e first_decerr_result;

    logic [31:0] first_decerr_addr;

    apb_slave_transaction::psel_choose exp_psel;
    apb_slave_transaction act;

    axi_transaction::error_response exp_bresp;

    tr = item.tr;
    size_bytes = get_size_bytes(tr);

    if (size_bytes == 0)
      return;

    num_beats = tr.len + 1;
    beat_addr = tr.addr[31:0];

    total_bytes = num_beats * size_bytes;

    if (total_bytes != 0) begin
      wrap_lower = (tr.addr[31:0] / total_bytes) * total_bytes;
      wrap_upper = wrap_lower + total_bytes;
    end
    else begin
      wrap_lower = tr.addr[31:0];
      wrap_upper = tr.addr[31:0];
    end

    has_apb_slverr                    = 1'b0;
    has_decerr                        = 1'b0;
    decerr_intr_enabled_for_this_xact = 1'b0;
    decerr_event_checked              = 1'b0;
    first_decerr_result               = DECODE_OK;
    first_decerr_addr                 = tr.addr[31:0];

    `uvm_info("SCB_AXI_WR_START",
      $sformatf("Start checking AXI WRITE. %s NumBeats=%0d | %s",
                axi_info(tr),
                num_beats,
                snapshot_info(item)),
      UVM_LOW)

    for (beat = 0; beat < num_beats; beat++) begin

      exp_psel = predict_psel_from_snapshot(beat_addr, item, dec_result);

      if (dec_result != DECODE_OK) begin

        has_decerr = 1'b1;

        if (update_bir_on_decode_error(beat_addr, item)) begin

          decerr_intr_enabled_for_this_xact = 1'b1;

          if (!decerr_event_checked) begin
            first_decerr_addr    = beat_addr;
            first_decerr_result  = dec_result;
            decerr_event_checked = 1'b1;
          end

        end
        else begin

          void'(check_decode_error_interrupt_disabled_for_addr(
            "SCB_WR_DECERR_INTR_OFF",
            item,
            beat,
            beat_addr,
            dec_result
          ));

        end

        `uvm_info("SCB_WR_DECERR",
          $sformatf("AXI WRITE decode error. %s Decode=%s ExpPSEL=%s | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    dec_result.name(),
                    exp_psel.name(),
                    snapshot_info(item)),
          UVM_LOW)

      end
      else begin

        act_idx = find_normal_slv_index(
                    beat_addr,
                    exp_psel,
                    apb_slave_transaction::WRITE
                  );

        if (act_idx < 0) begin
          `uvm_error("SCB_SLV_MISSING",
            $sformatf("Missing APB WRITE beat. %s ExpPSEL=%s | %s",
                      axi_beat_info(tr, beat, beat_addr),
                      exp_psel.name(),
                      snapshot_info(item)))
        end
        else begin
          act = slv_queue[act_idx];
          slv_queue.delete(act_idx);

          void'(check_apb_write_beat(
            item,
            beat,
            data_offset,
            beat_addr,
            size_bytes,
            exp_psel,
            act
          ));

          if (act.error == apb_slave_transaction::ERROR)
            has_apb_slverr = 1'b1;
        end

      end

      beat_addr = get_next_axi_addr(
                    tr,
                    beat_addr,
                    size_bytes,
                    total_bytes,
                    wrap_lower,
                    wrap_upper
                  );
    end

    if (has_decerr && decerr_intr_enabled_for_this_xact) begin
      void'(check_decode_error_interrupt_enabled(
        "SCB_WR_DECERR_INTR",
        item,
        first_decerr_addr,
        first_decerr_result
      ));
    end

    if (has_decerr)
      exp_bresp = axi_transaction::DECERR;
    else if (has_apb_slverr)
      exp_bresp = axi_transaction::SLVERR;
    else
      exp_bresp = axi_transaction::OKAY;

    check_axi_bresp(item, exp_bresp);

  endfunction

  function void check_axi_read_to_apb(
    axi_snapshot_t item,
    int unsigned data_offset  = 0,
    int unsigned error_offset = 0
  );

    axi_transaction tr;

    int unsigned num_beats;
    int unsigned size_bytes;
    int unsigned total_bytes;

    logic [31:0] beat_addr;
    logic [31:0] wrap_lower;
    logic [31:0] wrap_upper;

    int beat;
    int act_idx;

    bit decerr_intr_enabled_for_this_xact;
    bit decerr_event_checked;

    decode_result_e dec_result;
    decode_result_e first_decerr_result;

    logic [31:0] first_decerr_addr;

    apb_slave_transaction::psel_choose exp_psel;
    apb_slave_transaction act;

    tr = item.tr;
    size_bytes = get_size_bytes(tr);

    if (size_bytes == 0)
      return;

    num_beats = tr.len + 1;
    beat_addr = tr.addr[31:0];

    total_bytes = num_beats * size_bytes;

    if (total_bytes != 0) begin
      wrap_lower = (tr.addr[31:0] / total_bytes) * total_bytes;
      wrap_upper = wrap_lower + total_bytes;
    end
    else begin
      wrap_lower = tr.addr[31:0];
      wrap_upper = tr.addr[31:0];
    end

    decerr_intr_enabled_for_this_xact = 1'b0;
    decerr_event_checked              = 1'b0;
    first_decerr_result               = DECODE_OK;
    first_decerr_addr                 = tr.addr[31:0];

    `uvm_info("SCB_AXI_RD_START",
      $sformatf("Start checking AXI READ. %s NumBeats=%0d | %s",
                axi_info(tr),
                num_beats,
                snapshot_info(item)),
      UVM_LOW)

    for (beat = 0; beat < num_beats; beat++) begin

      exp_psel = predict_psel_from_snapshot(beat_addr, item, dec_result);

      if (dec_result != DECODE_OK) begin

        if (update_bir_on_decode_error(beat_addr, item)) begin

          decerr_intr_enabled_for_this_xact = 1'b1;

          if (!decerr_event_checked) begin
            first_decerr_addr    = beat_addr;
            first_decerr_result  = dec_result;
            decerr_event_checked = 1'b1;
          end

        end
        else begin

          void'(check_decode_error_interrupt_disabled_for_addr(
            "SCB_RD_DECERR_INTR_OFF",
            item,
            beat,
            beat_addr,
            dec_result
          ));

        end

        `uvm_info("SCB_RD_DECERR",
          $sformatf("AXI READ decode error. %s Decode=%s ExpPSEL=%s | %s",
                    axi_beat_info(tr, beat, beat_addr),
                    dec_result.name(),
                    exp_psel.name(),
                    snapshot_info(item)),
          UVM_LOW)

        check_axi_rresp(
          item,
          beat,
          error_offset,
          axi_transaction::DECERR
        );

      end
      else begin

        act_idx = find_normal_slv_index(
                    beat_addr,
                    exp_psel,
                    apb_slave_transaction::READ
                  );

        if (act_idx < 0) begin
          `uvm_error("SCB_SLV_MISSING",
            $sformatf("Missing APB READ beat. %s ExpPSEL=%s | %s",
                      axi_beat_info(tr, beat, beat_addr),
                      exp_psel.name(),
                      snapshot_info(item)))
        end
        else begin
          act = slv_queue[act_idx];
          slv_queue.delete(act_idx);

          void'(check_apb_read_beat(
            item,
            beat,
            data_offset,
            error_offset,
            beat_addr,
            size_bytes,
            exp_psel,
            act
          ));
        end

      end

      beat_addr = get_next_axi_addr(
                    tr,
                    beat_addr,
                    size_bytes,
                    total_bytes,
                    wrap_lower,
                    wrap_upper
                  );
    end

    if (decerr_intr_enabled_for_this_xact) begin
      void'(check_decode_error_interrupt_enabled(
        "SCB_RD_DECERR_INTR",
        item,
        first_decerr_addr,
        first_decerr_result
      ));
    end

  endfunction

  function void check_all_axi_to_apb();

    axi_snapshot_t item;
    axi_transaction tr;
    int unsigned num_beats;

    while (axi_queue.size() > 0) begin

      item = axi_queue.pop_front();
      tr   = item.tr;

      num_beats = tr.len + 1;

      case (tr.xact_type)

        axi_transaction::WRITE: begin
          check_axi_write_to_apb(item, 0);
        end

        axi_transaction::READ: begin
          check_axi_read_to_apb(item, 0, 0);
        end

        axi_transaction::DUAL: begin
          check_axi_write_to_apb(item, 0);
          check_axi_read_to_apb(item, num_beats, 1);
        end

        default: begin
          `uvm_error("SCB_AXI_TYPE",
            $sformatf("Unsupported AXI transaction type=%0d",
                      tr.xact_type))
        end

      endcase

    end

  endfunction

  // ============================================================
  // Check phase
  // ============================================================

  virtual function void check_phase(uvm_phase phase);

    super.check_phase(phase);

    `uvm_info("SCB_CHECK",
      $sformatf("Before check: axi_q=%0d slv_q=%0d | Current RAL: BAMS0=0x%08h BAMS1=0x%08h BAMS2=0x%08h %s",
                axi_queue.size(),
                slv_queue.size(),
                get_bams0_mirror(),
                get_bams1_mirror(),
                get_bams2_mirror(),
                bir_info()),
      UVM_LOW)

    check_all_axi_to_apb();

    drop_leftover_decerr_events();

    if (axi_queue.size() != 0) begin
      `uvm_error("SCB_AXI_LEFTOVER",
        $sformatf("axi_queue still has %0d item(s)",
                  axi_queue.size()))
    end

    if (slv_queue.size() != 0) begin
      `uvm_error("SCB_SLV_LEFTOVER_ACT",
        $sformatf("slv_queue still has %0d item(s). These APB slave transactions were not matched to any AXI transaction.",
                  slv_queue.size()))
    end

    `uvm_info("SCB_FINAL_RAL",
      $sformatf("Final RAL mirror: BAMS0=0x%08h BAMS1=0x%08h BAMS2=0x%08h %s",
                get_bams0_mirror(),
                get_bams1_mirror(),
                get_bams2_mirror(),
                bir_info()),
      UVM_LOW)

  endfunction

endclass : scoreboard

