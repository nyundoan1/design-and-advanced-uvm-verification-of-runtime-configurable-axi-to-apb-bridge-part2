# Design and Advanced UVM Verification of a Runtime-Configurable AXI-to-APB Bridge

## Project Overview (Graduation Thesis)

This project presents the **RTL design and advanced UVM-based verification** of a **Runtime-Configurable AXI-to-APB Bridge**.

Main project scope includes:

- RTL design using **Verilog**
- UVM-based verification environment development
- AXI/APB VIP integration
- Simulation and regression using **QuestaSim**
- Verification Planning (VPlan) with **70 testcases**
- FPGA synthesis and implementation using **Xilinx Vivado**

This repository represents the **final completed version** of the project, covering full RTL design, verification flow, coverage closure, and FPGA evaluation.

For detailed architecture, verification methodology, and full experimental results:

📁 **docs/LuanVanTotNghiep/**



# 1. Project Directory Structure

The project is organized into separate RTL, verification, simulation, and register-model related directories.

<img width="1874" height="695" alt="image" src="https://github.com/user-attachments/assets/f30a10a1-e963-4de5-b08b-db9e0dfed9ab" />



Main directories:
- `regmodel/` → Register abstraction model  
- `rtl/` → RTL design files
- `sequences/` → UVM sequences  
- `sim/` → Simulation scripts / Makefile flow  
- `tb/` → UVM testbench  
- `testcases/` → Test library  
- `vip/` → AXI/APB verification IP 



# 2. RTL Design Architecture

The bridge is designed with separate AXI clock domains, APB clock domains and runtime configurable logic via APB Register.
<img width="945" height="414" alt="image" src="https://github.com/user-attachments/assets/0e00fad1-7179-4219-b85b-f75e0f48d4a4" />
<img width="1810" height="851" alt="image" src="https://github.com/user-attachments/assets/eb9b3914-34a5-4897-8fc8-d3401afeb937" />

Main blocks:
- AXI Clock Domain
- APB Clock Domain
  - APB Master
  - APB Register


# 3. Register Specification

The bridge supports **runtime-configurable APB registers** for dynamic address remapping, memory size allocation, and interrupt handling. These registers define APB slave address regions and support bridge-level configuration during runtime.



### Register Map Overview

The APB register map defines the primary configuration registers accessible by software.

<img width="771" height="143" alt="image" src="https://github.com/user-attachments/assets/c4e0e9fb-82f6-4e6d-bd4b-a4e3f761c981" />




### BAMS0 Register

This register defines the base address and memory size of **APB Slave 0**.


<img width="995" height="212" alt="image" src="https://github.com/user-attachments/assets/feee8a6a-f8cc-4015-90d4-5b0094213440" />




### BAMS1 Register

This register controls the address mapping of **APB Slave 1**.

<img width="991" height="216" alt="image" src="https://github.com/user-attachments/assets/5ca409c3-990d-4baf-9711-6f3f12c992ac" />




### BAMS2 Register

This register defines the address region of **APB Slave 2**.

<img width="989" height="210" alt="image" src="https://github.com/user-attachments/assets/728f62e5-db26-46c7-bf19-69cc40449c67" />




### Bridge Interrupt Register (BIR)

This register manages bridge-level interrupt handling and decode error status.

<img width="991" height="209" alt="image" src="https://github.com/user-attachments/assets/65af3ef3-45de-4d6f-8f5b-42e8ded27963" />


Interrupt functions:
- **DecErrSt** → Decode Error Status (RW1C)
- **DecErrEn** → Decode Error Interrupt Enable


# 4. Write Transaction Flow

AXI write transactions are converted into APB write operations.

<img width="800" height="332" alt="image" src="https://github.com/user-attachments/assets/117278b9-fe44-4605-ad27-0ba57a9c1e39" />



# 5. Read Transaction Flow

AXI read transactions are converted into APB read accesses.

<img width="884" height="369" alt="image" src="https://github.com/user-attachments/assets/30206a5e-c0f2-4c62-b04e-250ee9364a7c" />




# 6. Verification Plan (VPlan)

A structured verification plan was developed to ensure systematic functional validation of the **Runtime-Configurable AXI-to-APB Bridge**.  
The verification scope covers protocol behavior, register functionality, error handling, remap logic, and runtime configuration scenarios.

<img width="336" height="395" alt="image" src="https://github.com/user-attachments/assets/9f6492a3-302f-44a2-befe-7f17f7e9d42c" />

### Main Verification Categories

- **APB Register Configuration**
  - Register default value check
  - Read/Write access verification
  - Reserved region protection
  - Byte access behavior

- **AXI Write Transaction Verification**
  - FIXED / INCR / WRAP burst write
  - Slave selection
  - Boundary crossing
  - PSLVERR handling

- **AXI Read Transaction Verification**
  - FIXED / INCR / WRAP burst read
  - Read response validation
  - Slave decode verification
  - Error response checking

- **Random Transaction Verification**
  - Constrained-random AXI read/write traffic
  - Address / burst / size randomization
  - DUT stability checking

- **Interrupt Verification**
  - Decode error interrupt
  - Interrupt enable / clear behavior
  - Sticky interrupt validation

- **Dynamic Address Remap Verification**
  - Runtime remap
  - Reserved region protection
  - Old region invalidation
  - Address crossing validation

### Verification Summary

- **6 major verification categories**
- **70 total directed + constrained-random testcases**
- Functional correctness validation
- Protocol behavior verification
- Register-level verification
- Error and corner-case handling

Detailed verification matrix, testcase descriptions, and coverage mapping are available in: 📁 **docs/VPLAN/**


# 7. UVM Testbench Architecture

A reusable UVM-based verification environment was developed.

<img width="722" height="474" alt="image" src="https://github.com/user-attachments/assets/1680b0a4-665c-4209-a530-07e3cd2aa61c" />



# 8. Coverage Results

Coverage-driven verification is one of the major objectives of this repository.

Coverage includes:
- Functional Coverage (FC)
 <img width="588" height="531" alt="image" src="https://github.com/user-attachments/assets/b2f56881-ea9d-4cce-9f45-f9e43416fe2a" />

- Code Coverage
<img width="925" height="200" alt="image" src="https://github.com/user-attachments/assets/a5982ffe-c3d4-402b-abd3-0a4e778c1b56" />

# 9. How to Run

This project supports **single testcase simulation, regression execution, waveform debugging, and coverage analysis**.



## Environment Setup

Move to the simulation directory to see Makefile:

```bash
cd sim/
```

Each time a new terminal is opened, source the project environment:

```bash
source project_env.bash
```
## Run Single Testcase

Clean previous build:

```bash
make clean
```

Compile the design and testbench:

```bash
make build
```

Run a specific testcase:

```bash
make TESTNAME=tc11_read_default
```

The simulation automatically generates:
- Log files  
- Waveform files  
- Coverage databases  

To open waveform:

```bash
make wave
```


## Run Regression

After validating all standalone testcases, update:

```bash
regress.cfg
```

with the list of testcases to execute.

Then run regression:

```bash
make clean
make build
perl regress.pl
```

After completion, the regression report will be generated in:

```bash
sim/regress.rpt
```

This report shows:
- PASS testcase  
- FAIL testcase  
- Regression summary  

Regression should complete successfully before coverage analysis.

---

## Coverage Merge & Analysis

After regression, multiple `.ucdb` files are generated inside:

```bash
cov/
```

If you've got pass all the testcases then Merge all coverage databases by using in /sim:

```bash
make cov_merge
```

This creates:

```bash
cov/IP_MERGE.ucdb
```

Open merged coverage result:

```bash
make cov_open
```

This is used to analyze:
- Functional Coverage (FC)  
- Code Coverage  
- Coverage completeness  
- Verification closure
- 
# 10. Author

**Nhan Doan**  
RTL Design, Verification Environment Development, Testcase Development, RTL Debugging & Bug Fixing  
Contact: 0328 044 046

**Van Anh**  
VIP Development, Sequence Development, Scoreboard Implementation, Testcase Debugging & Validation  
Contact: 0362 273 140
