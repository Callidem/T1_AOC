if {[file isdirectory work]} { vdel -all -lib work }
vlib work
vmap work work

vcom -2008 mult_div.vhd
vcom -2008 MIPS-MC_SingleEdge.vhd
vcom -2008 L1_Cache.vhd
vcom -2008 MIPS-MC_SingleEdge_tb.vhd

vsim -voptargs=+acc=lprn -t ps work.CPU_tb

do wave.do

set StdArithNoWarnings 1
set StdVitalGlitchNoWarnings 1

run 300 us

