# sim/common/run_target.do
# Requirements: cwd must be = sim/ (root fir simulations)
# Example:
#   cd sim
#   do common/run_target.do modem_tx_sim

if {![info exists 1] || $1 eq ""} {
    echo "Error: no target specified."
    echo "Example: do common/run_target.do <target_name>"
    return -code error "target name required"
}
set TARGET_NAME $1

set SIM_ROOT   [pwd]
set COMMON_DIR [file join $SIM_ROOT common]
set TARGET_DIR [file join $SIM_ROOT targets $TARGET_NAME]

# Directory check
if {![file isdirectory [file join $SIM_ROOT targets]] || ![file isdirectory $COMMON_DIR]} {
    echo "Current directory: $SIM_ROOT"
    echo "Do first: cd <путь_до>/sim"
    return -code error "wrong working directory"
}

if {![file isdirectory $TARGET_DIR]} {
    echo "Error: target '$TARGET_NAME' not found in $SIM_ROOT/targets/"
    echo "Available targets:"
    foreach d [glob -nocomplain -type d -directory [file join $SIM_ROOT targets] *] {
        echo "  - [file tail $d]"
    }
    return -code error "unknown target"
}

set RUN_DIR [file join $TARGET_DIR run]
file mkdir $RUN_DIR

set PREV_DIR [pwd]
cd $RUN_DIR

source [file join $TARGET_DIR target_cfg.do]

catch {quit -sim}
catch {vdel -all -lib work}
vlib work
vmap work work

set PYTHON_EXE "py"
if {[catch {exec $PYTHON_EXE [file join $COMMON_DIR generate_f.py] $PROJECT_DIR $TOP_FILE} out]} {
    echo "generate_f.py: $out"
} else {
    echo $out
}

vlog -f [file rootname $TOP_FILE].f
vsim -voptargs=+acc work.$TOP_MODULE

if {[info exists WAVES_DO] && $WAVES_DO ne ""} {
    do [file join $TARGET_DIR $WAVES_DO]
}

run -all

# Does not allow stopping the simulation from the testbench
# cd $PREV_DIR

if {[batch_mode]} {
    quit -sim
}