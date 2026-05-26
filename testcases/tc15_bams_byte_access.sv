`ifndef TC15_BAMS_BYTE_ACCESS_SV
`define TC15_BAMS_BYTE_ACCESS_SV

class tc15_bams_byte_access extends apb_base_test;
  `uvm_component_utils(tc15_bams_byte_access)

  function new(string name="tc15_bams_byte_access", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    uvm_reg         all_regs[$];
    uvm_reg_field   fields[$];
    uvm_status_e    status;
    uvm_reg_data_t  write_data;
    
    phase.raise_objection(this);

    // Bật auto-predict để giá trị mirror cập nhật ngay sau khi write
    env.regmodel.default_map.set_auto_predict(1);

    // Lấy danh sách thanh ghi
    env.regmodel.get_registers(all_regs);

    foreach (all_regs[i]) begin
      // Bỏ qua các thanh ghi không phải BAMS (như BIR)
      if (all_regs[i].get_name() == "BIR" || all_regs[i].get_name() == "bridge_BIR_reg") continue;

      `uvm_info("TC15", $sformatf("--- Stressing Byte Access on: %s ---", all_regs[i].get_name()), UVM_LOW)

      // Lấy các field bên trong thanh ghi
      all_regs[i].get_fields(fields);

      foreach (fields[j]) begin
        // Tạo dữ liệu ngẫu nhiên 32-bit
        void'(std::randomize(write_data));

        `uvm_info("TC15", $sformatf("Writing to Field: %s", fields[j].get_name()), UVM_MEDIUM)
        
        // SỬA LỖI TẠI ĐÂY: Truyền thẳng write_data vào. 
        // RAL sẽ tự động trích xuất số bit tương ứng với field, không cần dùng [ : ]
        fields[j].write(status, write_data);
        
        // Kiểm tra mirror value
        fields[j].mirror(status, UVM_CHECK);
      end

      // Ghi Full Word (32-bit) để cover bin PSTRB 4'b1111 (image_19d9ec.png)
      all_regs[i].write(status, 32'hFFFF_FFFF);
      all_regs[i].mirror(status, UVM_CHECK);
    end

    `uvm_info("TC15", "Byte Access Test Completed", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

`endif
