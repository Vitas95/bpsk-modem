# sim/common/run_target.do
# Требование: перед вызовом cwd должен быть = sim/ (корень симуляции)
# Использование:
#   cd sim
#   do common/run_target.do modem_tx_sim

if {![info exists 1] || $1 eq ""} {
    echo "Ошибка: не указан таргет."
    echo "Использование: do common/run_target.do <target_name>  (запускать из sim/)"
    return -code error "target name required"
}
set TARGET_NAME $1

set SIM_ROOT   [pwd]
set COMMON_DIR [file join $SIM_ROOT common]
set TARGET_DIR [file join $SIM_ROOT targets $TARGET_NAME]

# Явная проверка, что cwd действительно sim/ — иначе понятная ошибка,
# а не путаница с "не найден таргет"
if {![file isdirectory [file join $SIM_ROOT targets]] || ![file isdirectory $COMMON_DIR]} {
    echo "Ошибка: похоже, скрипт запущен не из папки sim/."
    echo "Текущая директория: $SIM_ROOT"
    echo "Сделай сначала: cd <путь_до>/sim"
    return -code error "wrong working directory"
}

if {![file isdirectory $TARGET_DIR]} {
    echo "Ошибка: таргет '$TARGET_NAME' не найден в $SIM_ROOT/targets/"
    echo "Доступные таргеты:"
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

cd $PREV_DIR

if {[batch_mode]} {
    quit -sim
}