`ifndef BRIDGE_COVERAGE_SV
`define BRIDGE_COVERAGE_SV

// Phân tách các cổng Implementation để quản lý 3 luồng dữ liệu độc lập
`uvm_analysis_imp_decl(_cov_axi)
`uvm_analysis_imp_decl(_cov_apb_reg)
`uvm_analysis_imp_decl(_cov_apb_master)

class bridge_coverage extends uvm_component;

     `uvm_component_utils(bridge_coverage)

     //---------------------------------------------------------
     // ANALYSIS PORTS
     //---------------------------------------------------------
     uvm_analysis_imp_cov_axi #(axi_transaction, bridge_coverage) axi_imp;
     uvm_analysis_imp_cov_apb_reg #(apb_master_seq_item, bridge_coverage) apb_reg_imp;
     uvm_analysis_imp_cov_apb_master #(apb_slave_transaction, bridge_coverage) apb_master_imp;

     //---------------------------------------------------------
     // TRANSACTION HANDLES & VARIABLES
     //---------------------------------------------------------
     axi_transaction       axi_item;
     apb_master_seq_item   apb_item;       // Cho Register access (Internal)
     apb_slave_transaction apb_slave_item; // Cho Master traffic (External)

     int psel_id;
     bit decode_hit, illegal_access, cross_boundary;
     int crossing_type;
     bit pslverr_detected, decerr_detected, decerr_intr, remap_access;

     typedef enum int { REG_BAMS0, REG_BAMS1, REG_BAMS2, REG_BIR, REG_RESERVED } reg_type_e;
     reg_type_e reg_type;

     //=========================================================
     // 1. AXI DOMAIN COVERAGE (Covers Section B, C, D)
     //=========================================================
     covergroup axi_cover;
          option.per_instance = 1;
          option.name = "axi_domain_coverage";

          // Protocol Check (TC 2.x, 3.x, 4.x, 5.x, 6.x, 7.x)
          cp_xfer: coverpoint axi_item.xact_type  { bins wr = {axi_transaction::WRITE}; bins rd = {axi_transaction::READ}; }
          cp_size: coverpoint axi_item.size_type  { bins b1 = {0}; bins b2 = {1}; bins b4 = {2}; }
          cp_brst: coverpoint axi_item.burst_type { bins fix = {0}; bins incr = {1}; bins wrap = {2}; }
          cp_psel: coverpoint psel_id             { bins p0 = {0}; bins p1 = {1}; bins p2 = {2}; bins inv = {3}; }
          
          // Decode & Boundary (TC 3.7, 3.8, 10.6)
          cp_dec:   coverpoint decode_hit    { bins hit = {1}; bins miss = {0}; }
          cp_cross: coverpoint cross_boundary { bins has_cross = {1}; bins no_cross = {0}; }

          // Crosses to ensure full test matrix
					x_full_traffic: cross cp_psel, cp_xfer, cp_brst, cp_size {
										     ignore_bins inv_details = binsof(cp_psel.inv);
										     ignore_bins inv_rd_rare = binsof(cp_psel.inv) && binsof(cp_xfer.rd);
										}
					x_crossing: cross cp_cross, cp_brst, cp_psel {
										     ignore_bins no_cr = binsof(cp_cross.no_cross);
										     ignore_bins fix_cross = binsof(cp_cross.has_cross) && binsof(cp_brst.fix);
										     ignore_bins inv_cross = binsof(cp_cross.has_cross) && binsof(cp_psel.inv);
										     ignore_bins p2_cross = binsof(cp_cross.has_cross) && binsof(cp_psel.p2);
										}
     endgroup

     //=========================================================
     // 2. APB REGISTER COVERAGE (Covers Section A & F)
     //=========================================================
     covergroup apb_reg_cover;
          option.per_instance = 1;
          option.name = "apb_register_coverage";

          cp_reg: coverpoint reg_type { 
               bins bams[] = {REG_BAMS0, REG_BAMS1, REG_BAMS2}; 
               bins bir    = {REG_BIR}; 
               bins rsv    = {REG_RESERVED}; 
          }
          cp_rw: coverpoint apb_item.we { bins rd = {0}; bins wr = {1}; }
          
          cp_strb: coverpoint apb_item.strb {
               bins word_acc = {4'b1111};
          }

          cp_remap: coverpoint remap_access { bins act = {1}; bins idle = {0}; }

          x_reg_access: cross cp_reg, cp_rw, cp_strb {
               ignore_bins rsv_all = binsof(cp_reg.rsv);
          }

          x_remap_op: cross cp_remap, cp_reg {
               ignore_bins act_non_bams = binsof(cp_remap.act) && (binsof(cp_reg.rsv) || binsof(cp_reg.bir));
               ignore_bins idle_bams    = binsof(cp_remap.idle) && binsof(cp_reg.bams);
          }
     endgroup

     //=========================================================
     // 3. APB MASTER COVERAGE (Covers Section E & Slave Errors)
     //=========================================================
		covergroup apb_master_cover;
				      option.per_instance = 1;
				      
				      cp_psel_out: coverpoint apb_slave_item.psel { 
				           bins active_slaves[] = {3'b001, 3'b010}; 
				           ignore_bins unused_s2 = {3'b100}; 
				      }
				      
				      cp_pslverr: coverpoint pslverr_detected { bins status[] = {0, 1}; }
				      cp_decerr:  coverpoint decerr_detected  { bins status[] = {0, 1}; }
				      

				      cp_intr: coverpoint decerr_intr { 
				           bins levels[] = {0, 1}; 
				           ignore_bins clear_trans = (1 => 0); 
				      }

				      x_sticky_check: cross cp_decerr, cp_intr {
				           ignore_bins red_bins = (binsof(cp_decerr.status) intersect {0} && binsof(cp_intr.levels) intersect {1}) ||
				                                  (binsof(cp_decerr.status) intersect {1} && binsof(cp_intr.levels) intersect {0});
				      }

				      x_slave_err_matrix: cross cp_psel_out, cp_pslverr;
     endgroup

     //---------------------------------------------------------
     // CONSTRUCTOR
     //---------------------------------------------------------
     function new(string name = "bridge_coverage", uvm_component parent = null);
          super.new(name, parent);
          axi_cover        = new();
          apb_reg_cover    = new();
          apb_master_cover = new();

          axi_imp        = new("axi_imp", this);
          apb_reg_imp    = new("apb_reg_imp", this);
          apb_master_imp = new("apb_master_imp", this);
     endfunction

     //---------------------------------------------------------
     // SAMPLING LOGIC
     //---------------------------------------------------------

     virtual function void write_cov_axi(axi_transaction trans);
          int end_addr;
          axi_item = trans;

          // Address decoding logic
          if (trans.addr inside {[32'h0000_0000:32'h0000_0FFF]})      psel_id = 0;
          else if (trans.addr inside {[32'h0000_1000:32'h0000_1FFF]}) psel_id = 1;
          else if (trans.addr inside {[32'h0000_2000:32'h0000_2FFF]}) psel_id = 2;
          else                                                        psel_id = 3;

          decode_hit = (psel_id != 3);
          illegal_access = ~decode_hit;

          // Crossing logic
          cross_boundary = 0; crossing_type = 0;
          end_addr = trans.addr + ((trans.len + 1) << trans.size_type);
          if ((trans.addr <= 32'h0000_0FFF) && (end_addr > 32'h0000_0FFF)) begin cross_boundary = 1; crossing_type = 1; end
          if ((trans.addr <= 32'h0000_1FFF) && (end_addr > 32'h0000_1FFF)) begin cross_boundary = 1; crossing_type = 2; end

          axi_cover.sample();
     endfunction

     virtual function void write_cov_apb_reg(apb_master_seq_item trans);
          apb_item = trans;
          remap_access = 0;
          case (trans.addr)
               8'h00: begin reg_type = REG_BAMS0; remap_access = 1; end
               8'h04: begin reg_type = REG_BAMS1; remap_access = 1; end
               8'h08: begin reg_type = REG_BAMS2; remap_access = 1; end
               8'h0C: reg_type = REG_BIR;
               default: reg_type = REG_RESERVED;
          endcase
          apb_reg_cover.sample();
     endfunction

     virtual function void write_cov_apb_master(apb_slave_transaction trans);
          apb_slave_item = trans;
          pslverr_detected = (trans.error == apb_slave_transaction::ERROR);
          decerr_detected  = (trans.decerr == 1);
          decerr_intr      = decerr_detected;
          apb_master_cover.sample();
     endfunction

endclass
`endif
