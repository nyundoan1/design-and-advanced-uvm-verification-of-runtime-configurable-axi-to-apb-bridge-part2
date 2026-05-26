`ifndef ENVIRONMENT_SV
`define ENVIRONMENT_SV

class environment extends uvm_env;

  `uvm_component_utils(environment)

  //=========================================================
  // COMPONENTS
  //=========================================================
  scoreboard       sb;
  apb_master_agent apb_master_agt;
  apb_slave_agent  apb_slave_agt;
  axi_agent        axi_agt;
  bridge_coverage  cov;

  //=========================================================
  // CONFIGURATIONS & RAL
  //=========================================================
  apb_master_config       apb_mst_cfg;
  apb_slave_configuration apb_slv_cfg;

  apb_reg_block           regmodel;
  apb_reg_adapter         apb_adapter;
  uvm_reg_predictor #(apb_master_seq_item) apb_predictor;

  // Virtual interfaces
  virtual axi_if        axi_vif;
  virtual apb_master_if apb_master_vif;
  virtual apb_slave_if  apb_slave_vif;

  //---------------------------------------------------------
  // CONSTRUCTOR
  //---------------------------------------------------------
  function new(string name = "environment", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //---------------------------------------------------------
  // BUILD PHASE
  //---------------------------------------------------------
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    `uvm_info("ENV_BUILD", "Entered build_phase", UVM_HIGH)

    // 1. Get Virtual Interfaces from config_db
    if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi_vif", axi_vif)) 
      `uvm_fatal("CONFIG_ERR", "Could not get axi_vif")

    if (!uvm_config_db#(virtual apb_master_if)::get(this, "", "apb_master_vif", apb_master_vif)) 
      `uvm_fatal("CONFIG_ERR", "Could not get apb_master_vif")

    if (!uvm_config_db#(virtual apb_slave_if)::get(this, "", "apb_slave_vif", apb_slave_vif)) 
      `uvm_fatal("CONFIG_ERR", "Could not get apb_slave_vif")

    // 2. Get Agent/Slave Configs
    if (!uvm_config_db#(apb_master_config)::get(this, "", "apb_mst_cfg", apb_mst_cfg)) 
      `uvm_fatal("CONFIG_ERR", "Could not get apb_mst_cfg")

    if (!uvm_config_db#(apb_slave_configuration)::get(this, "", "apb_slv_cfg", apb_slv_cfg)) 
      `uvm_fatal("CONFIG_ERR", "Could not get apb_slv_cfg")

    // 3. Create Components
    sb             = scoreboard::type_id::create("sb", this);
    apb_master_agt = apb_master_agent::type_id::create("apb_master_agt", this);
    apb_slave_agt  = apb_slave_agent::type_id::create("apb_slave_agt", this);
    axi_agt        = axi_agent::type_id::create("axi_agt", this);
    cov            = bridge_coverage::type_id::create("cov", this);

    // 4. RAL Setup
    regmodel = apb_reg_block::type_id::create("regmodel", this);
    regmodel.build();
    regmodel.reset();

    apb_adapter   = apb_reg_adapter::type_id::create("apb_adapter");
    apb_predictor = uvm_reg_predictor#(apb_master_seq_item)::type_id::create("apb_predictor", this);

    apb_predictor.map     = regmodel.apb_map;
    apb_predictor.adapter = apb_adapter;
    regmodel.apb_map.set_auto_predict(0);

    // 5. Pass Resources Downwards
    uvm_config_db#(virtual axi_if)::set(this, "axi_agt", "axi_vif", axi_vif);
    uvm_config_db#(virtual apb_master_if)::set(this, "apb_master_agt", "apb_master_vif", apb_master_vif);
    uvm_config_db#(apb_master_config)::set(this, "apb_master_agt", "apb_mst_cfg", apb_mst_cfg);
    uvm_config_db#(virtual apb_slave_if)::set(this, "apb_slave_agt", "apb_slave_vif", apb_slave_vif);
    uvm_config_db#(apb_slave_configuration)::set(this, "apb_slave_agt", "apb_slv_cfg", apb_slv_cfg);

    // Pass to Scoreboard
    uvm_config_db#(apb_master_config)::set(this, "sb", "apb_mst_cfg", apb_mst_cfg);
    uvm_config_db#(apb_slave_configuration)::set(this, "sb", "apb_slv_cfg", apb_slv_cfg);
    uvm_config_db#(apb_reg_block)::set(this, "sb", "regmodel", regmodel);

    `uvm_info("ENV_BUILD", "Exiting build_phase", UVM_HIGH)
  endfunction : build_phase

  //---------------------------------------------------------
  // CONNECT PHASE
  //---------------------------------------------------------
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    `uvm_info("ENV_CONNECT", "Entered connect_phase", UVM_HIGH)

    // --- Scoreboard Connections ---
    apb_master_agt.mon.item_collected_port.connect(sb.mon_export);
    apb_master_agt.drv.drv_proxy_port.connect(sb.drv_export);
    apb_slave_agt.monitor.apb_item_act.connect(sb.slv_export);
    axi_agt.monitor.axi_item_act.connect(sb.axi_export);

    // --- Coverage Connections ---
    
    // Domain 1: AXI Interface
    axi_agt.monitor.axi_item_act.connect(cov.axi_imp);

    // Domain 2.1: APB Register Access (Bridge Configuration)
    apb_master_agt.mon.item_collected_port.connect(cov.apb_reg_imp);

    // Domain 2.2: APB Master Traffic (External Slave response)
    apb_slave_agt.monitor.apb_item_act.connect(cov.apb_master_imp);

    // --- RAL & Predictor Connections ---
    regmodel.apb_map.set_sequencer(apb_master_agt.sqr, apb_adapter);
    apb_master_agt.mon.item_collected_port.connect(apb_predictor.bus_in);

    `uvm_info("ENV_CONNECT", "Exiting connect_phase", UVM_HIGH)
  endfunction : connect_phase

endclass : environment

`endif
