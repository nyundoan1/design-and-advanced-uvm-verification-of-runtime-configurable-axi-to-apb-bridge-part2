## -------------------------------------------------------------
# This file created by Nhan Doan
# Updated date: 26/05/2026
# Example run string: make TESTNAME={name_of_testcase} {optional}
#		     make run TESTNAME=apb_base_test 
## -------------------------------------------------------------
#
TB_NAME   ?=testbench  
TESTNAME  ?=apb_base_test
VERBOSITY ?=UVM_HIGH
RUNARG    ?=
SEED      ?=1
COV       ?=ON
UCDB ?=

#==============================
ifeq ($(COV),ON)
  CMP_COV_OPT   = -coveropt 3 +cover=bcestf 
  SIM1_COV_OPT  = -coverage -coveranalysis  
  SIM2_COV_OPT  = coverage save -codeAll -cvg -onexit $(TESTNAME)_$(SEED).ucdb;
endif

ifeq ($(strip $(SEED)),random)
  SEED = $(shell /bin/date +%s)
endif

##==============================================================
VLOG =  vlog ${CMP_COV_OPT} \
        -timescale "1us/1ns" \
        +define+UVM_NO_DPI \
        -mfcu \
        -suppress 2181 \
        +acc \
        +incdir+$(UVM_HOME)/src \
        $(UVM_HOME)/src/uvm.sv
		
VSIM =  vsim \
        -sv_seed ${SEED} ${SIM1_COV_OPT}\
        -voptargs=+acc \
        -assertdebug \
        -c ${TB_NAME}\
        -do "${SIM2_COV_OPT} log -r /*;run -all;" \
        -l $(TESTNAME)_$(SEED).log	
##==============================================================

all: build run
build: 	vlib
	$(VLOG)  -f compile.f \
  	+define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR 
		
run:
	$(VSIM) +UVM_TESTNAME=$(TESTNAME) \
          +UVM_VERBOSITY=$(VERBOSITY) \
	        ${RUNARG} 
	mv ${TESTNAME}_$(SEED).log ./log
	mv ${TESTNAME}_$(SEED).ucdb ./cov
	cp -rf vsim.wlf log/$(TESTNAME)_$(SEED).wlf
	ln -sf ./log/${TESTNAME}_$(SEED).log run.log

vlib:
	mkdir -p log
	mkdir -p cov
	vlib work
	vmap work work

wave:
	vsim -i -view vsim.wlf -do "add wave vsim:/$(TB_NAME)/*;" &

cov_gui:
	vsim -i -viewcov cov/$(TESTNAME)_$(SEED).ucdb &
	
cov_merge:
	vcover merge cov/IP_MERGE.ucdb cov/*.ucdb

cov_open:
	vsim -i -viewcov cov/IP_MERGE.ucdb &

cov_report:
	vcover report -details cov/IP_MERGE.ucdb > cov/cov_report.txt

cov_html:
	vcover report -html cov/IP_COV_HTML cov/IP_MERGE.ucdb

clean: 
	rm -rf cov
	rm -rf work
	rm -rf log
	rm -rf *.ini
	rm -rf *.log
	rm -rf *.trace
	rm -rf *.wlf
	rm -rf transcript
	rm -rf *.ucdb
	rm -rf vsim.dbg
	rm -rf tmp_report

help:
	@echo ""
	@echo "======================================================"
	@echo "                AXI-to-APB UVM MAKEFLOW               "
	@echo "======================================================"
	@echo ""
	@echo "Build / Run Commands:"
	@echo "  make build                      : Compile RTL + TB + UVM"
	@echo "  make run TESTNAME=<test_name>   : Run single testcase"
	@echo "  make all TESTNAME=<test_name>   : Build + Run testcase"
	@echo "  make wave                       : Open waveform viewer"
	@echo ""
	@echo "Coverage Flow:"
	@echo "  make clean                      : Clean previous simulation data"
	@echo "  make build                      : Compile design and testbench"
	@echo "  perl regress.pl                 : Run regression testcases"
	@echo "  make cov_merge                  : Merge all UCDB files"
	@echo "  make cov_open                   : Open merged coverage database"
	@echo "  make cov_report                 : Generate text coverage report"
	@echo "  make cov_html                   : Generate HTML coverage report"
	@echo "  make cov_gui TESTNAME=<name>    : Open single testcase UCDB"
	@echo ""
	@echo "Utility:"
	@echo "  make clean                      : Remove work/log/cov/temp files"
	@echo ""
	@echo "Example:"
	@echo "  make run TESTNAME=apb_base_test"
	@echo "  make cov_gui TESTNAME=tc106_reserved_region_after_remap"
	@echo ""
	@echo "======================================================"
