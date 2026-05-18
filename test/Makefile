# Makefile

# defaults
COCOTB_SIM=1
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
COCOTB_HDL_TIMEUNIT = "1ns"
COCOTB_HDL_TIMEPRECISION = "10ps"
BEHAV?=1
export COCOTB_LOG_LEVEL = INFO
COMPILE_ARGS += -DCOCOTB_SIM 

ifeq ($(SIM),vcs)
COMPILE_ARGS += +incdir+$(PWD)/../src/
COMPILE_ARGS += +vcs+loopreport+5000000
WAVES ?= FSDB
endif

PWD=$(shell pwd)

ifeq ($(BEHAV), 1)
	VERILOG_SOURCES += $(PWD)/../src/parameters.svh
	VERILOG_SOURCES += $(PWD)/../src/tt_um_gray_sobel.sv
	VERILOG_SOURCES += $(PWD)/../src/top_gray_sobel.sv
	VERILOG_SOURCES += $(PWD)/../src/sobel_control.sv
	VERILOG_SOURCES += $(PWD)/../src/ema_threshold.sv
	VERILOG_SOURCES += $(PWD)/../src/sobel_core.sv
	VERILOG_SOURCES += $(PWD)/../src/gray_scale_core.sv
	VERILOG_SOURCES += $(PWD)/../src/async_nreset_synchronizers.sv
	VERILOG_SOURCES += $(PWD)/../src/spi_core.sv
	VERILOG_SOURCES += $(PWD)/../src/spi_control.sv
	VERILOG_SOURCES += $(PWD)/../src/LFSR.sv
	VERILOG_SOURCES += $(PWD)/../src/signature_analyzer.sv
else
	include $(PWD)/../postapr/Makefile.skywater
	#COMPILE_ARGS += +define+USE_POWER_PINS
	VERILOG_SOURCES += $(PWD)/../postapr/tt_um_gray_sobel.nl.v
endif

#TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
#TOPLEVEL = top_gray_sobel
TOPLEVEL = tt_um_gray_sobel

# MODULE is the basename of the Python test file
# MODULE = gray_sobel_TB
MODULE = tt_um_gray_sobel_TB
#COMPILE_ARGS += -PUSE_POWER_PINS=1

# include cocotb's make rules to take care of the simulator setup
# include cocotb's make rules to take care of the simulator setup
ifeq ($(SIM),vcs)
include ../postapr/Makefile.sim
else
include $(shell cocotb-config --makefiles)/Makefile.sim
endif

VERDI       := verdi
VERDI_OPTS  := -ssf
verdi :
	$(VERDI) $(VERDI_OPTS) $(FSDB_FILE) -smart_load_kdb &

clean_output:
	rm -rf  *.jpg *.txt *~


