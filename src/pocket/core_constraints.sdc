# WAVE7 CONSOLIDATED CORE CONSTRAINTS — private candidate, NOT SIGNOFF.
# Replaces core/core_constraints.sdc read by the APF SDC. Never append to old SDC.
# PLL/base clocks already exist from APF. No asynchronous cut among engine,
# pixel, SDRAM or PSRAM clocks. Exact sources/hashes in manifest.json.
create_generated_clock -name pocket_sdram_pin \
    -source [get_pins -compatibility_mode {ic|clocks|pll|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}] \
    [get_ports {dram_clk}]


# ---- PSRAM40 input IOFF and output phase constraints ----
# Original constraints for wolf_pocket_psram40. REVIEW WITH FIRST FIT.
# Replace the legacy psram_io_budget.sdc section; never append both versions.
# Waveform source is the 80 MHz PLL counter; pin_clk0/1 are actual output FFs.
# At first sys edge phase40 0->1, pin remains0; at next edge pin 0->1.
# Therefore generated pin clocks divide by2 and invert (rise at sys edge+12.5ns).
# Clock is held low only during asynchronous initialization, when no normal
# synchronous data transfer is permitted. No clock-group or false-path cut.
proc ps40_require_count {label collection count} {
    set actual [get_collection_size $collection]
    if {$actual != $count} { error "PSRAM40: $label expected $count objects, got $actual" }
    return $collection
}
set ps40_source [ps40_require_count sys_pll [get_pins -compatibility_mode \
    {ic|clocks|pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] 1]
foreach chip {0 1} {
    set pinclock [ps40_require_count clock_port [get_ports "cram${chip}_clk"] 1]
    # The output FF is a clock generator in the timing netlist. Assign it
    # before deriving the forwarded pad clock, so TimeQuest traces both the
    # SYS clock path and clock-to-output instead of assuming zero latency.
    set pinreg [ps40_require_count clock_output_ff [get_registers \
        "ic|psram_backend|physical|pin_clk${chip}"] 1]
    create_generated_clock -name pocket_psram${chip}_reg -divide_by 2 -invert \
        -source $ps40_source $pinreg
    create_generated_clock -name pocket_psram${chip}_pin -divide_by 1 \
        -source $pinreg $pinclock
    set ps40_capture [ps40_require_count input_ioffs [get_registers \
        "ic|psram_backend|physical|dq${chip}_capture\[*\]"] 16]
    set dq [ps40_require_count dq_ports [get_ports "cram${chip}_dq\[*\]"] 16]
    set outputs [ps40_require_count output_ports [get_ports [list \
        "cram${chip}_a\[*\]" "cram${chip}_dq\[*\]" "cram${chip}_adv_n" \
        "cram${chip}_ce0_n" "cram${chip}_ce1_n" "cram${chip}_oe_n" \
        "cram${chip}_we_n" "cram${chip}_ub_n" "cram${chip}_lb_n"]] 29]
    # Alliance grade-70 timings at <=48MHz: tACLKmax9ns, tKOHmin2ns,
    # input setup3ns (CE setup4ns) and hold2ns. Board bounds below are assumptions, to
    # replace with board measurements/layout if available: each direction0..2ns.
    # Input max9+2(clock flight)+2(DQ flight)=13; min2+0+0=2.
    set_input_delay -clock pocket_psram${chip}_pin -max 13.000 $dq
    set_input_delay -clock pocket_psram${chip}_pin -min 2.000 $dq
    # Conservative DQ/control-vs-clock board skew +/-2ns.
    set_output_delay -clock pocket_psram${chip}_pin -max 5.000 [remove_from_collection $outputs [get_ports [list "cram${chip}_ce0_n" "cram${chip}_ce1_n"]]]
    set_output_delay -clock pocket_psram${chip}_pin -min -4.000 $outputs
    set ce_ports [ps40_require_count ce_ports [get_ports [list "cram${chip}_ce0_n" "cram${chip}_ce1_n"]] 2]
    # CE has a distinct tCSP=4ns requirement, one ns larger than tSP.
    set_output_delay -clock pocket_psram${chip}_pin -max 6.000 $ce_ports
    # Exact RTL contract: dqN_capture samples only when old phase40==1,
    # the CLK40 rising phase. D0 launches at the preceding CLK40 rise.
    # This excludes the intermediate 80MHz falling-CLK40 capture edge only.
    # The following capture->rdata mux is a normal ONE-SYS-cycle path.
    # Scoped to this package's sixteen IOFFs, not rdata or other FFs.
    set_multicycle_path -setup -end -from $dq -to $ps40_capture 2
    set_multicycle_path -hold -end -from $dq -to $ps40_capture 1
}
# If clock groups are explicitly enumerated, add pocket_psram{0,1}_{reg,pin} to
# the group containing clk_74a / sys PLL clocks. They are synchronous to sys.
# WAIT is unused for fixed latency; CRE is asynchronous configuration only.
# Normal address/data/control sources change on CLK40 falling phase.
# DQ-enable also drops at READ step3: address sampled step1, ADV rises step2,
# and there is no device input-data sample at step3. Its first possible change
# after an ACTUAL device input sample is >=one SYS later, as for other outputs.
# A default hold check assumes a change at every SYS/CLK40 coincident rise.
# Move its launch ONE SOURCE period right; do not move latch by25ns and do
# not change output setup. See IOFF_PHASE_PROOF.txt and independent monitor.
proc ps40_output_classify {name} {
    regsub -all {(^|\|)[^|:]+:} $name {\1} canonical
    regsub {^apf_top\|} $canonical {} canonical
    set prefix {ic|psram_backend|physical|}
    if {[string first $prefix $canonical] != 0} {return {}}
    set leaf [string range $canonical [string length $prefix] end]
    if {[regexp {^(a\[(16|17|18|19|20|21)\]|dq_out\[([0-9]|1[0-5])\]|adv|we|oe|be\[[01]\]|ce_n\[[0-3]\]|dq_enable\[[01]\])(~[^|]+)?$} $leaf -> base]} {return $base}
    return {}
}
set ps40_output_names {}
set ps40_output_classes {}
foreach_in_collection object [get_registers {ic|psram_backend|physical|*}] {
    set name [get_register_info -name $object]
    set kind [ps40_output_classify $name]
    if {$kind ne {}} {lappend ps40_output_names $name; lappend ps40_output_classes $kind}
}
set ps40_output_names [lsort -unique $ps40_output_names]
if {[llength [lsort -unique $ps40_output_classes]] != 33} {
    error "PSRAM40: normal output source logical coverage must be33"
}
set ps40_output_ffs [get_registers $ps40_output_names]
if {[get_collection_size $ps40_output_ffs] != [llength $ps40_output_names]} {
    error "PSRAM40: failed to resolve every selected output FF"
}
set ps40_normal_ports [ps40_require_count normal_outputs [get_ports {
    cram0_a[*] cram0_dq[*] cram0_adv_n cram0_ce0_n cram0_ce1_n cram0_oe_n cram0_we_n cram0_ub_n cram0_lb_n
    cram1_a[*] cram1_dq[*] cram1_adv_n cram1_ce0_n cram1_ce1_n cram1_oe_n cram1_we_n cram1_ub_n cram1_lb_n
}] 58]
set ps40_selected_file [open psram40-normal-output-registers.txt w]
foreach name $ps40_output_names {puts $ps40_selected_file $name}
close $ps40_selected_file
puts "PSRAM40: [get_collection_size $ps40_output_ffs] physical output FFs covering33 verified logical sources"
set_multicycle_path -hold -start -from $ps40_output_ffs -to $ps40_normal_ports 1
# CLK, CRE, phase40, capture FFs, capture_pending, rdata and all internal
# register-to-register paths are deliberately excluded from this exception.
# The asynchronous BCR write is separately held87.5ns with CLKstatic; verify
# output path skew and pulse widths, not just these synchronous constraints.


# ---- Clock relationships (all derived/forwarded clocks in source group) ----
set_clock_groups -asynchronous \
    -group [get_clocks {clk_74a ic|clocks|pll|* pocket_sdram_pin pocket_psram0_reg pocket_psram0_pin pocket_psram1_reg pocket_psram1_pin}] \
    -group [get_clocks {clk_74b}] \
    -group [get_clocks {bridge_spiclk}]


# ---- SDRAM external delay assumptions ----
# PRIVATE REPLACEMENT for the four SDRAM input/output delay lines.
# Existing pocket_sdram_pin is the propagated forwarded clock AT FPGA PAD.
# Assumption: each independent one-way CLK/data PCB flight is 0..0.25ns.
# No PCB measurement is available. These values do not add clock uncertainty.
# Read max = tAC2 + clk_flight_max + dq_flight_max = 6+.25+.25.
# Read min = tOH + clk_flight_min + dq_flight_min = 2.5+0+0.
# Write max = tSU + data_flight_max - clk_flight_min = 2+.25-0.
# Write min = -tH + data_flight_min - clk_flight_max = -1+0-.25.
# Do not also add these flights to source latency or a far-end timing model.
# Replace existing four lines; do not add duplicate -add_delay constraints.
set_input_delay -clock pocket_sdram_pin -max 6.500 [get_ports {dram_dq[*]}]
set_input_delay -clock pocket_sdram_pin -min 2.500 [get_ports {dram_dq[*]}]
set_output_delay -clock pocket_sdram_pin -max 2.250 [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_cke dram_ras_n dram_cas_n dram_we_n}]
set_output_delay -clock pocket_sdram_pin -min -1.250 [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_cke dram_ras_n dram_cas_n dram_we_n}]


# ---- SDRAM BL1 / CL2 capture phase ----
# PRIVATE candidate: BL1 / CL2 delayed capture, proved by read-phases.csv.
# ONLY incoming DQ -> the16 enabled data FFs in this exact controller.
# READ is issued on sys E0 and sampled by SDRAM clock C0 at +8.981ns.
# CL2 launches returned word on C1. data_ready_delay[0] captures on sys E3.
# Setup pair: C1 -> E3 (16.013ns nominal), not C2 -> E3 (3.516ns).
# Hold pair: C2+tOH -> E3. The subsequent SDRAM edge can END this BL1 word.
# Therefore setup2 / hold0, NOT the usual clock-enable setup2 / hold1.
# This constrains the finite valid window rather than claiming data stable2T.
# Preserve propagated clock latency, tAC/tOH and board-flight SDC delays.
# Must inspect resulting setup AND hold launch/latch times at all PVT corners.
set sdram_capture_dq [get_ports {dram_dq[*]}]
set sdram_capture_ff [get_registers {ic|system_core|engine|u_sdram|data[*]}]
if {[get_collection_size $sdram_capture_dq] != 16} { error "SDRAM capture expected16 DQ ports" }
if {[get_collection_size $sdram_capture_ff] != 16} { error "SDRAM capture expected16 data registers" }
set_multicycle_path -setup -end -from $sdram_capture_dq -to $sdram_capture_ff 2
set_multicycle_path -hold -end -from $sdram_capture_dq -to $sdram_capture_ff 0


# ---- Specific mailbox CDC, with relocated PSRAM bridge fault ----
# Wave6 CDC: preserve wave5 scopes; relocated memory fault source only.
# system_core.load_fault OR psram_backend.bridge.fault -> engine_fault -> ef_meta.
# Both source registers use clk_sys; ef_meta is the first clk_74a stage.
# No clock-wide false paths between clk_74a, clk_sys, SDRAM or pixel clocks.
proc tr_regs {label pattern} {
    set coll [get_registers $pattern]
    if {[get_collection_size $coll] == 0} { error "timing-review: missing $label ($pattern)" }
    return $coll
}
# Explicit control crossings, ONLY into first metastability-catching stages.
foreach {source dest} {
    {ic|loader|request_toggle} {ic|loader|req_meta}
    {ic|loader|ack_toggle} {ic|loader|ack_meta}
    {ic|loader|done} {ic|loader|done_meta}
    {ic|sound|request} {ic|sound|req_meta}
    {ic|sound|ack} {ic|sound|ack_meta}
    {ic|commands|reset_n} {ic|run_meta}
    {ic|loader|fault} {ic|lf_meta}
    {ic|system_core|load_fault} {ic|ef_meta}
    {ic|psram_backend|bridge|fault} {ic|ef_meta}
} {
    set_false_path -from [tr_regs source $source] -to [tr_regs meta $dest]
}
# Buttons are independent levels, not an atomic payload. Optimized-away unused
# bits are allowed; each controller still has implemented key bits.
for {set c 1} {$c <= 4} {incr c} {
    set_false_path -from [tr_regs "controller $c" "ipm|cont${c}_key\[*\]"] \
        -to [tr_regs keys_meta {ic|system_core|controls|keys_meta[*]}]
}
# Coherent mailboxes: held payload is launched with or before request and cannot
# change until the return acknowledgement. Capture is at least two destination
# cycles later. 10 ns is deliberately below 2*12.5 and 2*13.468 ns.
# No false path on payloads: max-delay must remain effective in TimeQuest 18.1.
foreach {source dest} {
    {ic|sound|held[*]} {ic|sound|sample_pair[*]}
    {ic|loader|slot[*]} {ic|loader|load_index[*]}
    {ic|loader|offset[*]} {ic|loader|load_addr[*]}
} {
    set a [tr_regs payload_source $source]
    set b [tr_regs payload_capture $dest]
    set_max_delay -from $a -to $b 10.000
    # No phase-specific hold requirement for these held-through-ack payloads.
    # Bound physical min path rather than cutting the payload bus.
    set_min_delay -from $a -to $b 0.000
}
# Deliberately leave first-stage -> second-stage paths under ordinary STA.
# Deliberately leave loader RAM dual-clock ports, PLL lock/reset recovery,
# clk_pixel-as-data/pixel_prev and sys->pixel video under ordinary analysis.

# ---- TMS CPU CE4, exact audited scalar/fabric registers ----
# TMS CPU enable contract, Open Ice /4 only. Requires IO_CPU_CE=1 RTL.
# Source audit: ce-register-audit.json; no IO/RAM/asynchronous launch nodes.
# Source and destination CPU FFs change only on the SAME ce_cpu pulse.
# CPU-originated writes/NMI/WV into IO storage are gated on that pulse too.
# Raster counter/event paths originate outside this source collection and
# remain single-cycle. RAM cells and MLAB input/output timing are excluded.
set tms_ce_root {ic|system_core|engine|u_core}
set tms_ce_leaf_names {
    div_dvd_sign_q
    div_dvs_sign_q
    drav_dest_q
    drav_inside_q
    drav_linear_q
    drav_rd_q
    drav_rs_q
    drav_substep_q
    drav_w_q
    fetch_inflight_q
    fill_addr_q
    fill_color_q
    fill_daddr_raw_q
    fill_dest_q
    fill_dptch_q
    fill_dx_q
    fill_dy_q
    fill_row_base_q
    fill_substep_q
    fill_w1_q
    fill_w2_q
    fill_wend_q
    fill_win_en_q
    fill_wstart_q
    fill_x_q
    fill_y_q
    illegal_q
    imm2_hi_q
    imm2_lo_q
    imm_hi_q
    imm_lo_q
    instr_word_q
    int_is_nmi_q
    int_push_q
    int_vec_q
    io_is_io_q
    io_rdata_q
    line_a_q
    line_aborted_q
    line_b_q
    line_color_q
    line_count_q
    line_d_q
    line_daddr_q
    line_dest_q
    line_inc1_q
    line_inc2_q
    line_last_inside_q
    line_offset_q
    line_substep_q
    line_wend_q
    line_wstart_q
    mem_op_step
    mm_mask_q
    mm_rp_q
    move_data_q
    mpy_product_q
    mv_load_data_q
    pair_wb_step
    pblt_color0_q
    pblt_color1_q
    pblt_dptch_q
    pblt_dst_addr_q
    pblt_dst_pix_q
    pblt_dst_row_q
    pblt_dst_xy_raw_q
    pblt_dx_q
    pblt_dy_q
    pblt_sptch_q
    pblt_src_addr_q
    pblt_src_pix_q
    pblt_src_row_q
    pblt_substep_q
    pblt_w1_q
    pblt_w2_q
    pblt_wend_q
    pblt_win_en_q
    pblt_wstart_q
    pblt_x_q
    pblt_y_q
    pix_dest_q
    pixt_inside_q
    pixt_wend_q
    pixt_wstart_q
    popped_pc_q
    popped_st_q
    state_q
}
set tms_ce_patterns {}
foreach reg $tms_ce_leaf_names {
    lappend tms_ce_patterns "${tms_ce_root}|${reg}*"
}
foreach suffix {shared_graphics_registers.graphics_word_q* shared_graphics_registers.graphics_half_q* u_pc|pc_q* u_status_reg|st_q* u_divider|st_q* u_divider|rem_q* u_divider|quot_q* u_divider|dvd_lo_q* u_divider|divisor_q* u_divider|ovf_q* u_divider|iter_q* u_regfile|sp_q* u_regfile|*last_write_addr* u_regfile|*last_write_data* u_regfile|*valid*} {
    lappend tms_ce_patterns "${tms_ce_root}|${suffix}"
}
set tms_ce_ffs [get_registers -nowarn $tms_ce_patterns]
if {[get_collection_size $tms_ce_ffs] == 0} {error "No audited TMS CE registers matched"}
foreach_in_collection reg $tms_ce_ffs {
    set reg_name [get_register_info -name $reg]
    if {[string match {*u_io_regs*} $reg_name] || [string match {*port?_mem*} $reg_name]} {
        error "Unexpected IO/RAM launch node in TMS CE collection: $reg_name"
    }
}
puts "TMS audited CE/4 FFs: [get_collection_size $tms_ce_ffs]"
set_multicycle_path -setup -end 4 -from $tms_ce_ffs -to $tms_ce_ffs
set_multicycle_path -hold -end 3 -from $tms_ce_ffs -to $tms_ce_ffs

# ONLY with the candidate IO gating. These IO storage FFs also accept device
# events, so they are deliberately NOT part of the launching collection.
set tms_ce_io_targets [get_registers -nowarn {ic|system_core|engine|u_core|u_io_regs|io_reg*}]
if {[get_collection_size $tms_ce_io_targets] == 0} {error "No TMS IO storage targets matched"}
puts "TMS CE-qualified IO targets: [get_collection_size $tms_ce_io_targets]"
set_multicycle_path -setup -end 4 -from $tms_ce_ffs -to $tms_ce_io_targets
set_multicycle_path -hold -end 3 -from $tms_ce_ffs -to $tms_ce_io_targets

# Generated block names are flattened with dots by sv2v/Quartus18.1.
set tms_shared_graphics_ffs [get_registers -nowarn {ic|system_core|engine|u_core|shared_graphics_registers.graphics_word_q* ic|system_core|engine|u_core|shared_graphics_registers.graphics_half_q*}]
if {[get_collection_size $tms_shared_graphics_ffs] == 0} {error "Missing shared graphics CE FFs; check fitted generated block naming"}
puts "TMS shared graphics CE FFs: [get_collection_size $tms_shared_graphics_ffs]"


# ---- DCS CE2 with PC-stack registered write payload ----
# DCS CE/2: positive list only, BOTH endpoints required. No clock exception.
# Audited against build/dcs-timing-candidate/{adsp2105,dcs_mem}.sv.
# At CLK_HZ=80MHz and DCS_CORE_HZ=32MHz, enabled-edge spacings repeat 2,3.
# This file is valid only while CORE_CE_EN=1 and minimum CE spacing >=2.
# For every admitted RTL register, ordinary updates occur within cpu_ce/mem_ce.
# Synchronous reset is not a data transfer in normal operation.
# Explicit dcs_ce_ram input/core registers are included ONLY inside the two
# named g_ce_ram instances, with positive register-kind selection below.
# This proposal REQUIRES postmap/postfit confirmation that input and core
# enables remain cpu_ce, plus the unchanged board CE-spacing proof.
# Original inferred pm_rtl_0/dm_rtl_0 and cache RAMs remain excluded.
# ext_rsp_q/ext_rsp_valid, dac_ce, pc_written_toggle and every parent/peripheral are excluded.

proc dcs_ce_classify {full_name} {
    # TimeQuest names may include entity:instance annotations, as reports do.
    set canonical [string trimleft $full_name {|}]
    regsub -all {(^|\|)[^|:]+:} $canonical {\1} canonical
    regsub {^apf_top\|} $canonical {} canonical
    set prefix {ic|system_core|engine|u_dcs_board|u_adsp|}
    if {[string first $prefix $canonical] != 0} {return {}}
    set relative [string range $canonical [string length $prefix] end]
    # The explicit wrapper drives clocken0/1 with cpu_ce and requests NORMAL
    # input AND core enables. Positive list: no arbitrary RAM descendants,
    # latch-output or clock-enable bookkeeping registers.
    # Quartus can render a Verilog generate scope using '.' or '|'.
    if {[regexp {^g_ce_ram[.|](pm_store|dm_store)\|ram\|auto_generated\|ram_block[0-9a-z]+~port([ab])_(we|re|address|data|datain|byteena|byte_enable)_reg([0-9]+|\[[0-9]+\])?(~[^|]*)?$} $relative -> store port kind]} {
        return "ram/$store/$port/$kind"
    }
    # Fabric high-address bank select for a logical RAM split across M10Ks.
    # Must also have cpu_ce enable in the new physical netlist.
    if {[regexp {^g_ce_ram[.|](pm_store|dm_store)\|ram\|auto_generated\|address_reg_([ab])(\[[0-9]+\]|[0-9]+)(~[^|]*)?$} $relative -> store port]} {
        return "ram/$store/$port/bankaddress"
    }
    # Exact one-hot encoding observed and proved in fitted wave12 netlist.
    # No wildcard/replica/cache suffix is admitted by this extension.
    if {$relative eq {mem_need_r.01}} {return {mem_need_r.01}}
    set owner core
    if {[string first {u_mem|} $relative] == 0} {
        set owner cache
        set relative [string range $relative 6 end]
    }
    # A literal declared RTL name with optional bit/array subscripts and
    # compiler replication suffix. Any additional hierarchy is rejected.
    if {![regexp {^([A-Za-z_][A-Za-z_0-9]*)(\[[0-9]+\])*(~[^|]*)?$} $relative -> leaf]} {
        # Quartus may turn an audited state vector into named one-hot flops.
        if {![regexp {^(state|rstate)\.[A-Za-z_][A-Za-z_0-9]*(~[^|]*)?$} $relative -> leaf]} {return {}}
    }
    set core_names {gr iR mR lR baseR lmask astat mstat sstat imask icntl px afb mfb sbb mrzb cntr data_bank fetch_r pmb_q dm_q pc state loop_end loop_cond loop_sp pc_sp pc_push_addr pc_push_data pc_write_toggle pc_last_addr pc_last_data pc_last_valid cntr_stack cntr_sp host_rst_r reboot_pending reboot_bank boot_active boot_idx boot_plen boot_bank boot_phase boot_b0 boot_b1 stat_sp status_last_addr status_last_data status_last_valid tim_scale tim_count tim_period tim_scale_cnt tim_irq_latch ab_active ab_ireg ab_base ab_size ab_incs dac_slot_ctr dac_slot_go input_data irq2_line irq2_latch latch_control output_data irq1_pulse ctl_s1_autobuf ctl_syscontrol op_r exec_reg_data generic_read_select_r ea_addr_r pm_addr_r pm_rd_r bank_rd_r tx1_r mem_need_r div_done div_i div_q div_nd div_rem div_v ab_drain_cnt dr_done dr_idx dr_acc dr_region dr_rom_a dac_sample o_ppc o_valid o_unimpl}
    set cache_names {pf_valid rstate srv_addr srv_boot srv_byte ddr_cnt ddr_beat pfd_q pft_q pfv_q}
    if {$owner eq {core} && [lsearch -exact $core_names $leaf] >= 0} {return $leaf}
    if {$owner eq {cache} && [lsearch -exact $cache_names $leaf] >= 0} {return "u_mem|$leaf"}
    return {}
}

set dcs_ce_names {}
set dcs_ce_inventory [get_registers -nowarn {*|u_adsp|*}]
set dcs_ce_count 0
# read_sdc may be evaluated repeatedly in the same Tcl interpreter.
# array set with an empty list does not clear existing elements.
unset -nocomplain dcs_ce_categories
array set dcs_ce_categories {}
set dcs_ce_log [open dcs-ce-selected-registers.txt w]
foreach_in_collection reg $dcs_ce_inventory {
    set name [get_register_info -name $reg]
    set category [dcs_ce_classify $name]
    if {$category ne {}} {
        lappend dcs_ce_names $name
        incr dcs_ce_count
        if {![info exists dcs_ce_categories($category)]} {set dcs_ce_categories($category) 0}
        incr dcs_ce_categories($category)
        puts $dcs_ce_log $name
    }
}
close $dcs_ce_log
# foreach_in_collection supplies opaque reg_N handles, not a collection.
# Resolve the recorded real names together; never pass reg_N as a name filter.
set dcs_ce_regs [get_registers -nowarn $dcs_ce_names]
set dcs_ce_actual_count [get_collection_size $dcs_ce_regs]
if {$dcs_ce_actual_count != $dcs_ce_count} {
    error "DCS CE/2: selected $dcs_ce_count names but resolved $dcs_ce_actual_count registers"
}
# Audit the collection returned by TimeQuest, not only the selected-name list.
foreach_in_collection reg $dcs_ce_regs {
    set resolved_name [get_register_info -name $reg]
    if {[dcs_ce_classify $resolved_name] eq {}} {
        error "DCS CE/2: resolved an unreviewed register: $resolved_name"
    }
}
# Do not silently apply an empty/renamed hierarchy. Optional/optimized-out
# signals may be absent, but each indispensable architecture group must exist.
foreach required {state op_r gr baseR u_mem|rstate u_mem|srv_addr ram/pm_store/a/address ram/pm_store/b/address ram/dm_store/a/address ram/dm_store/b/address} {
    if {![info exists dcs_ce_categories($required)]} {
        error "DCS CE/2: required register group absent: $required"
    }
}
if {$dcs_ce_count < 100} {error "DCS CE/2: implausibly small audited collection ($dcs_ce_count)"}
# Executable identity is the documented SDC flow discriminator. Only the
# Fitter may defer absent post-fit RAM pseudo-nodes; STA remains strict.
# Current and legacy Quartus names are checked for agreement if both exist.
proc dcs_sdc_is_fitter {} {
    set names {}
    foreach var {::TimingAnalyzerInfo(nameofexecutable) ::TimeQuestInfo(nameofexecutable) ::quartus(nameofexecutable)} {
        if {[info exists $var]} {lappend names [set $var]}
    }
    set names [lsort -unique $names]
    if {[llength $names]>1} {error "DCS SDC: conflicting executable identities $names"}
    return [expr {[llength $names]==1 && [lindex $names 0] eq {quartus_fit}}]
}
# Payload widths refer to distinct logical bit indices. The Fitter may add
# replicas while optimizing: verify every bit, but do not freeze replica count.
# Post-fit STA remains strict to the exact independently audited wave12 netlist.
# Pass the caller's values: read_sdc may execute in a local Tcl frame.
# No implicit global or upvar is valid for these per-evaluation collections.
proc dcs_sdc_require_payload {category width physical_count selected_names category_counts} {
    set bits {}
    foreach name $selected_names {
        if {[dcs_ce_classify $name] ne $category} {continue}
        if {![regexp {\[([0-9]+)\](~[^|]*)?$} $name -> bit]} {
            error "DCS payload CE/2: cannot resolve logical bit in $name"
        }
        lappend bits $bit
    }
    set bits [lsort -integer -unique $bits]
    set expected {}
    for {set bit 0} {$bit<$width} {incr bit} {lappend expected $bit}
    if {$bits ne $expected} {
        error "DCS payload CE/2: missing or unexpected logical bits in $category: $bits"
    }
    if {![dict exists $category_counts $category]} {error "DCS payload CE/2: absent category $category"}
    set actual_count [dict get $category_counts $category]
    if {[dcs_sdc_is_fitter]} {
        post_message -type info "DCS payload CE/2: Fitter has all $width logical $category bits, $actual_count physical names; exact post-fit count requires audit"
    } elseif {$actual_count!=$physical_count} {
        error "DCS payload CE/2: expected $physical_count post-fit FFs in $category; re-audit fitted implementation"
    }
}
dcs_sdc_require_payload exec_reg_data 16 16 $dcs_ce_names [array get dcs_ce_categories]
dcs_sdc_require_payload pc_push_addr 32 32 $dcs_ce_names [array get dcs_ce_categories]
dcs_sdc_require_payload pc_push_data 14 14 $dcs_ce_names [array get dcs_ce_categories]

# This physical encoding can be absent during optimization. Post-fit it must
# match the single separately proved FF; any new placement requires re-audit.
# Inline caller-local variables avoid implicit globals/read_sdc scope errors.
if {![dcs_sdc_is_fitter]} {
    if {![info exists dcs_ce_categories(mem_need_r.01)] || $dcs_ce_categories(mem_need_r.01)!=1} {
        error "DCS CE/2: expected exactly one audited mem_need_r.01 FF; re-audit fitted encoding"
    }
}

post_message -type info "DCS CE/2: $dcs_ce_actual_count resolved explicit RTL registers; selected names saved to dcs-ce-selected-registers.txt"
set_multicycle_path -setup -end -from $dcs_ce_regs -to $dcs_ce_regs 2
set_multicycle_path -hold -end -from $dcs_ce_regs -to $dcs_ce_regs 1


# Private wave6 extension. Requires existing audited $tms_ce_ffs and
# $tms_ce_io_targets from tms_cpu_ce_dotfix.sdc, plus Pocket CPU_CE_WRITE=1.
# Do not merge these additions into tms_ce_ffs: IO raster destinations differ.
set tms_boundary_root {ic|system_core|engine}
set tms_io_ce_patterns {}
set tms_io_nonraster_patterns {}
for {set index 0} {$index < 32} {incr index} {
    # DPYADR is autonomously loaded at vblank on ANY system edge.
    if {$index == 30} {continue}
    if {$index == 18} {
        # INTPEND.DI (bit10) is autonomously set by raster at full rate.
        for {set bit 0} {$bit < 16} {incr bit} {
            if {$bit == 10} {continue}
            set pattern [format {%s|u_core|u_io_regs|io_reg[%d][%d]*} $tms_boundary_root $index $bit]
            lappend tms_io_ce_patterns $pattern
            lappend tms_io_nonraster_patterns $pattern
        }
    } else {
        set pattern [format {%s|u_core|u_io_regs|io_reg[%d]*} $tms_boundary_root $index]
        lappend tms_io_ce_patterns $pattern
        # Exclude all raster configuration indexes0..10 from sources to
        # autonomous IO targets. They feed u_video and DPYSTRT->DPYADR.
        if {$index > 10} {lappend tms_io_nonraster_patterns $pattern}
    }
}
set tms_io_ce [get_registers -nowarn $tms_io_ce_patterns]
set tms_io_nonraster_ce [get_registers -nowarn $tms_io_nonraster_patterns]
set tms_adapter_capture [get_registers -nowarn {
    ic|system_core|engine|u_memcdc|m_we*
    ic|system_core|engine|u_memcdc|m_addr*
    ic|system_core|engine|u_memcdc|m_size*
    ic|system_core|engine|u_memcdc|m_wdata*
}]
# All four payload registers update only in SC_IDLE && ce_cpu && c_req.
# Never include c_ack/c_rdata/m_req/scst: they update on non-CE system edges.
set tms_io_autonomous_targets [get_registers -nowarn {
    ic|system_core|engine|u_core|u_io_regs|io_reg[18][10]*
    ic|system_core|engine|u_core|u_io_regs|io_reg[30]*
}]
foreach {label objects} [list io_cpu_only $tms_io_ce io_nonraster $tms_io_nonraster_ce \
        adapter_capture $tms_adapter_capture autonomous_io $tms_io_autonomous_targets] {
    if {[get_collection_size $objects] == 0} {error "TMS CE boundary: empty $label"}
    puts "TMS CE boundary $label: [get_collection_size $objects] registers"
}
# Guard actual resolved bits as well as nonempty collections.
foreach_in_collection reg $tms_io_ce {
    set name [get_register_info -name $reg]
    if {![regexp {io_reg\[([0-9]+)\]\[([0-9]+)\]} $name unused index bit]} {
        error "Unexpected IO CE register name: $name"
    }
    if {$index == 30 || ($index == 18 && $bit == 10)} {
        error "Full-rate IO bit accidentally included in CE sources: $name"
    }
}
foreach_in_collection reg $tms_io_nonraster_ce {
    set name [get_register_info -name $reg]
    regexp {io_reg\[([0-9]+)\]\[([0-9]+)\]} $name unused index bit
    if {$index <= 10 || $index == 30 || ($index == 18 && $bit == 10)} {
        error "Raster source accidentally included in nonraster sources: $name"
    }
}
# Record resolved names to check literal bracket matching and duplicates.
set tms_boundary_f [open tms-ce-boundary-selected.txt w]
foreach {label objects} [list io_cpu_only $tms_io_ce io_nonraster $tms_io_nonraster_ce \
        adapter_capture $tms_adapter_capture autonomous_io $tms_io_autonomous_targets] {
    puts $tms_boundary_f "COLLECTION $label"
    foreach_in_collection reg $objects {puts $tms_boundary_f [get_register_info -name $reg]}
}
close $tms_boundary_f
# The core, these IO bits and adapter captures share the same /4 enable phase.
foreach {sources targets} [list \
        $tms_ce_ffs $tms_adapter_capture \
        $tms_io_ce $tms_ce_ffs \
        $tms_io_ce $tms_io_ce \
        $tms_io_ce $tms_adapter_capture \
        $tms_io_nonraster_ce $tms_io_autonomous_targets] {
    set_multicycle_path -setup -end 4 -from $sources -to $targets
    set_multicycle_path -hold -end 3 -from $sources -to $targets
}
# Last pair: nonraster IO sources can affect those two target classes only via
# ce_cpu-qualified CPU writes/WV; their full-rate assignments use raster
# state/config0..10. The full-rate branch is NOT relaxed from its true sources.


# Executable identity is the documented SDC flow discriminator. Only the
# Fitter may defer absent post-fit RAM pseudo-nodes; STA remains strict.
# Current and legacy Quartus names are checked for agreement if both exist.
proc dcs_sdc_is_fitter {} {
    set names {}
    foreach var {::TimingAnalyzerInfo(nameofexecutable) ::TimeQuestInfo(nameofexecutable) ::quartus(nameofexecutable)} {
        if {[info exists $var]} {lappend names [set $var]}
    }
    set names [lsort -unique $names]
    if {[llength $names]>1} {error "DCS SDC: conflicting executable identities $names"}
    return [expr {[llength $names]==1 && [lindex $names 0] eq {quartus_fit}}]
}
# DCS explicit DM read-output cone, source-only CE/2 extension.
# Apply AFTER the existing DCS CE collection and its setup2/hold1 exceptions.
# Evidence: timing-wave7-iofix netlist + exact vendor-model 32-slice proof.
# The TimeQuest suffix is a pseudo endpoint: do not infer literal WREN state.
# Both DM read input and RAM core are gated by the exact CPU CE (2/3 SYS
# spacing). q_b and bank selection change only on CE; no next-SYS update.
# This extends only launch sources. All incoming paths to these aliases keep
# their ordinary constraint. Cache, PM, peripherals and full-rate CDC stay out.

proc dcs_dm_output_ce_alias {full_name} {
    set canonical [string trimleft $full_name {|}]
    regsub -all {(^|\|)[^|:]+:} $canonical {\1} canonical
    regsub {^apf_top\|} $canonical {} canonical
    return [regexp {^ic\|system_core\|engine\|u_dcs_board\|u_adsp\|g_ce_ram[.|]dm_store\|ram\|auto_generated\|ram_block[0-9a-z]+~PORT_B_WRITE_ENABLE_REG(~[^|]*)?$} $canonical]
}
if {![info exists dcs_ce_regs] || [get_collection_size $dcs_ce_regs] < 100} {
    error "DCS DM output CE/2: existing audited DCS destination collection absent"
}
set dcs_dm_output_names {}
foreach_in_collection object [get_registers -nowarn {*|u_adsp|*}] {
    set name [get_register_info -name $object]
    if {[dcs_dm_output_ce_alias $name]} {lappend dcs_dm_output_names $name}
}
set dcs_dm_output_names [lsort -unique $dcs_dm_output_names]
set dcs_dm_output_deferred 0
if {[llength $dcs_dm_output_names]==0 && [dcs_sdc_is_fitter]} {
    # Before final RAM mapping, these pseudo-nodes do not exist. Applying no
    # exception is conservative; NEVER accept this branch in quartus_sta.
    set dcs_dm_output_deferred 1
    post_message -type info "DCS DM output CE/2: Fitter pre-fit has0 RAM aliases; no DM exception applied. Post-fit STA must resolve32."
} else {
    if {[llength $dcs_dm_output_names] != 32} {
        error "DCS DM output CE/2: expected 32 reviewed aliases, found [llength $dcs_dm_output_names]; re-audit new fit"
    }
    set dcs_dm_output_sources [get_registers -nowarn $dcs_dm_output_names]
    if {[get_collection_size $dcs_dm_output_sources] != 32} {
        error "DCS DM output CE/2: real collection does not resolve to exactly 32 aliases"
    }
    foreach_in_collection object $dcs_dm_output_sources {
        if {![dcs_dm_output_ce_alias [get_register_info -name $object]]} {
            error "DCS DM output CE/2: resolved an unreviewed source"
        }
    }
    set dcs_dm_output_log [open dcs-dm-output-ce-sources.txt w]
    foreach name $dcs_dm_output_names {puts $dcs_dm_output_log $name}
    close $dcs_dm_output_log
    set_multicycle_path -setup -end -from $dcs_dm_output_sources -to $dcs_ce_regs 2
    set_multicycle_path -hold -end -from $dcs_dm_output_sources -to $dcs_ce_regs 1
    post_message -type info "DCS DM output CE/2: 32 reviewed DM aliases added as sources only"
}

# Version2: Quartus fitter may read SDC before physical FSM names exist.
# Defer ONLY this optional extension during quartus_fit; ordinary timing stays
# conservative there. STA (and unknown callers) must pass every strict guard.
# Do not use top-level return: later constraints in a concatenated SDC must run.
proc tms_instruction_sdc_is_fitter {} {
    set names {}
    foreach var {::TimingAnalyzerInfo(nameofexecutable) ::TimeQuestInfo(nameofexecutable) ::quartus(nameofexecutable)} {
        if {[info exists $var]} {lappend names [set $var]}
    }
    set names [lsort -unique $names]
    if {[llength $names] > 1} {error "TMS SDC: conflicting executable identities $names"}
    return [expr {[llength $names] == 1 && [lindex $names 0] eq {quartus_fit}}]
}
set tms_instruction_fitter_stage [tms_instruction_sdc_is_fitter]
if {$tms_instruction_fitter_stage} {
    post_message -type info {TMS instruction request extension deferred during quartus_fit; required with strict physical-name guards in quartus_sta}
} else {
    # Private, narrow conditional-capture extension. Apply only after the existing
    # CPU CE4 constraints. Exact wave9 proof: capture-physical-proof.json and PROOF.txt.
    # The only launchers here are instruction-word FFs (including fitted copies).
    # The four endpoints ignore every instruction-dependent request term when
    # cpu_ce=0. m_req/scst still accept ACK/reset/state changes at full system rate;
    # NONE of those other launchers receives an exception.
    set tms_instruction_capture_sources [get_registers -nowarn {ic|system_core|engine|u_core|instr_word_q*}]
    set tms_instruction_capture_targets [get_registers -nowarn {
        ic|system_core|engine|mem_srt_r
        ic|system_core|engine|u_memcdc|m_req
        ic|system_core|engine|u_memcdc|scst.00
        ic|system_core|engine|u_memcdc|scst.01
    }]
    set tms_instruction_bits {}
    foreach_in_collection reg $tms_instruction_capture_sources {
        set name [get_register_info -name $reg]
        if {![regexp {instr_word_q\[([0-9]+)\](~DUPLICATE[0-9]*)?$} $name unused bit]} {
            error "Unexpected TMS instruction launch register: $name"
        }
        if {$bit < 0 || $bit > 15} {error "Invalid instruction bit: $name"}
        lappend tms_instruction_bits $bit
    }
    if {[llength [lsort -unique $tms_instruction_bits]] != 16} {
        error "Missing instruction launch bits; re-audit the new fit"
    }
    if {[get_collection_size $tms_instruction_capture_targets] != 4} {
        error "Expected the four individually audited request destinations; re-audit renamed FSM"
    }
    puts "TMS conditional request capture: [get_collection_size $tms_instruction_capture_sources] instruction FFs -> 4 exact targets"
    set_multicycle_path -setup -end 4 -from $tms_instruction_capture_sources -to $tms_instruction_capture_targets
    set_multicycle_path -hold -end 3 -from $tms_instruction_capture_sources -to $tms_instruction_capture_targets
}

# Read-only capture at the END of core SDC, in read_sdc's actual local scope.
# No helper proc/global dependency and no new timing command. Every list resets.
set tms_capture_groups [list \
    tms_ce_ffs $tms_ce_ffs \
    tms_ce_io_targets $tms_ce_io_targets \
    tms_shared_graphics_ffs $tms_shared_graphics_ffs \
    tms_io_ce $tms_io_ce \
    tms_io_nonraster_ce $tms_io_nonraster_ce \
    tms_adapter_capture $tms_adapter_capture \
    tms_io_autonomous_targets $tms_io_autonomous_targets]
if {!$tms_instruction_fitter_stage} {
    lappend tms_capture_groups \
        tms_instruction_capture_sources $tms_instruction_capture_sources \
        tms_instruction_capture_targets $tms_instruction_capture_targets
}
set tms_capture_file [open tms-ce-collections.txt w]
foreach {tms_capture_label tms_capture_objects} $tms_capture_groups {
    if {[get_collection_size $tms_capture_objects] == 0} {
        close $tms_capture_file
        error "TMS collection capture: empty $tms_capture_label"
    }
    puts $tms_capture_file "COLLECTION $tms_capture_label"
    foreach_in_collection tms_capture_reg $tms_capture_objects {
        puts $tms_capture_file [get_register_info -name $tms_capture_reg]
    }
}
close $tms_capture_file
if {$tms_instruction_fitter_stage} {
    puts {TMS collection capture:7 groups; instruction extension deferred in Fitter}
} else {
    puts {TMS collection capture:9 exact nonempty groups for post-fit physical audit}
}
