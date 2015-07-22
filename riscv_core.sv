////////////////////////////////////////////////////////////////////////////////
// Company:        IIS @ ETHZ - Federal Institute of Technology               //
//                 DEI @ UNIBO - University of Bologna                        //
//                                                                            //
// Engineer:       Renzo Andri - andrire@student.ethz.ch                      //
//                                                                            //
// Additional contributions by:                                               //
//                 Igor Loi - igor.loi@unibo.it                               //
//                 Andreas Traber - atraber@student.ethz.ch                   //
//                                                                            //
//                                                                            //
// Create Date:    24/3/2015                                                  //
// Design Name:    RiscV Minion                                               //
// Module Name:    riscv_core.sv                                              //
// Project Name:   RISCV                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    RiscV core                                                 //
//                                                                            //
//                                                                            //
// Revision:                                                                  //
//                                                                            //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

`include "defines.sv"


module riscv_core
(
  // Clock and Reset
  input  logic        clk,
  input  logic        rst_n,

  // Core ID, Cluster ID and boot address are considered more or less static
  input  logic [31:0] boot_addr_i,
  input  logic [4:0]  core_id_i,
  input  logic [4:0]  cluster_id_i,

  // Instruction memory interface
  output logic [31:0] instr_addr_o,
  output logic        instr_req_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_grant_i,
  input  logic        instr_rvalid_i,

  // Data memory interface
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  output logic        data_we_o,
  output logic        data_req_o,
  output logic [3:0]  data_be_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_gnt_i,
  input  logic        data_r_valid_i,

  // Interrupt inputs
  input  logic        irq_i,                 // level-triggered IR line
  input  logic        irq_nm_i,              // level-triggered IR line for non-maskable IRQ

  // Debug Interface
  input  logic        dbginf_stall_i,
  output logic        dbginf_bp_o,
  input  logic        dbginf_strobe_i,
  output logic        dbginf_ack_o,
  input  logic        dbginf_we_i,
  input  logic [15:0] dbginf_addr_i,
  input  logic [31:0] dbginf_data_i,
  output logic [31:0] dbginf_data_o,

  // CPU Control Signals
  input  logic        fetch_enable_i,
  output logic        core_busy_o
);


  // IF/ID signals
  logic [31:0]   instr_rdata_id;    // Instruction  sampled nsude the PC stage
  logic [31:0]   current_pc_if;     // Current Program counter
  logic [31:0]   current_pc_id;     // Current Program counter
  logic          force_nop_id;
  logic [2:0]    pc_mux_sel_id;     // Mux selector for next PC
  logic          pc_mux_boot;       // load boot address as PC
  logic [1:0]    exc_pc_mux_id;     // Mux selector for exception PC

  logic          compressed_instr;

  logic          useincr_addr_ex;   // Active when post increment
  logic          data_misaligned;   // Active when post increment


  // Forwarding

  // Jump and branch target and decision (EX->IF)
  logic [31:0] jump_target;
  logic  [1:0] jump_in_id;
  logic  [1:0] jump_in_ex;
  logic        branch_decision;


  // Stalling
  logic          stall_if;          // Stall instruction fetch(deassert request)
  logic          stall_id;          // Stall PC stage and instr memory and data memo
  logic          stall_ex;          // Stall EX Stage
  logic          stall_wb;          // Stall write back stage


  // Register Data
  logic [31:0]   regfile_rb_data_ex;    // from id stage to load/store unit and ex stage
  logic [31:0]   regfile_rb_data_wb;    // from ex stage to sp register


  // ALU Control
  logic [`ALU_OP_WIDTH-1:0] alu_operator_ex;
  logic [31:0]              alu_operand_a_ex;
  logic [31:0]              alu_operand_b_ex;
  logic [31:0]              alu_operand_c_ex;

  logic [1:0]               vector_mode_ex;
  logic [1:0]               alu_cmp_mode_ex;
  logic [1:0]               alu_vec_ext_ex;

  // Multiplier Control
  logic            mult_en_ex;
  logic [1:0]      mult_sel_subword_ex;
  logic [1:0]      mult_signed_mode_ex;
  logic            mult_use_carry_ex;
  logic            mult_mac_en_ex;

  // Register Write Control
  logic [4:0]      regfile_waddr_ex;
  logic            regfile_wdata_mux_sel_ex;
  logic            regfile_we_ex;
  logic [4:0]      regfile_waddr_fw_wb_o;        // From WB to ID
  logic            regfile_we_wb;
  logic [31:0]     regfile_wdata;
  logic            regfile_wdata_mux_sel_wb;

  logic [4:0]      regfile_alu_waddr_ex;
  logic            regfile_alu_we_ex;


  logic [4:0]      regfile_alu_waddr_fw;
  logic            regfile_alu_we_fw;
  logic [31:0]     regfile_alu_wdata_fw;

  // CSR control
  logic            csr_access_ex;
  logic  [1:0]     csr_op_ex;

  logic  [1:0]     csr_op;
  logic [11:0]     csr_addr;
  logic [31:0]     csr_rdata;
  logic [31:0]     csr_wdata;

  // Data Memory Control:  From ID stage (id-ex pipe) <--> load store unit
  logic            data_we_ex;
  logic [1:0]      data_type_ex;
  logic            data_sign_ext_ex;
  logic [1:0]      data_reg_offset_ex;
  logic            data_req_ex;
  logic [31:0]     data_addr_ex;
  logic            data_misaligned_ex;
  logic [31:0]     data_rdata_int;
  logic [31:0]     lsu_data_reg;
  logic            data_ack_int;

  // Signals between instruction core interface and pipe (if and id stages)
  logic [31:0]     instr_rdata_int;  // read instruction from the instruction core interface to if_stage
  logic            instr_req_int;    // Id stage asserts a req to instruction core interface
  logic            instr_ack_int;    // instr core interface acks the request now (read data is available)
  logic [31:0]     instr_addr_int;   // adress sent to the inst core interface from if_Stage

  // Interrupts
  logic            irq_enable;
  logic [31:0]     epcr;
  logic            save_pc_if;
  logic            save_pc_id;
  logic            save_sr;
  logic            restore_sr;

  // hwloop data from ALU
  logic [31:0]                    hwlp_cnt_ex;        // from id to ex stage (hwloop_regs)
  logic [2:0]                     hwlp_we_ex;         // from id to ex stage (hwloop_regs)
  logic [1:0]                     hwlp_regid_ex;      // from id to ex stage (hwloop_regs)
  logic                           hwlp_wb_mux_sel_ex; // from id to ex stage (hwloop_regs)
  logic [31:0]                    hwlp_start_data_ex; // hwloop data to write to hwloop_regs
  logic [31:0]                    hwlp_end_data_ex;   // hwloop data to write to hwloop_regs
  logic [31:0]                    hwlp_cnt_data_ex;   // hwloop data to write to hwloop_regs

  // spr access to hwloops
  logic [31:0]                    sp_hwlp_start;
  logic [31:0]                    sp_hwlp_end;
  logic [31:0]                    sp_hwlp_cnt;
  logic [2:0]                     sp_hwlp_we;
  logic [1:0]                     sp_hwlp_regid;

  // Access to hwloop registers
  logic [31:0]                    hwlp_start_data;
  logic [31:0]                    hwlp_end_data;
  logic [31:0]                    hwlp_cnt_data;
  logic [2:0]                     hwlp_we;
  logic [1:0]                     hwlp_regid;


  // hwloop controller signals
  logic [`HWLOOP_REGS-1:0] [31:0] hwlp_start_addr;  // to hwloop controller
  logic [`HWLOOP_REGS-1:0] [31:0] hwlp_end_addr;    // to hwloop controller
  logic [`HWLOOP_REGS-1:0] [31:0] hwlp_counter;     // to hwloop controller
  logic [`HWLOOP_REGS-1:0]        hwlp_dec_cnt;     // from hwloop controller to hwloop regs
  logic [31:0]                    hwlp_targ_addr;   // from hwloop controller to if stage


  // Debug Unit
  logic               dbg_stall;
  logic               dbg_flush_pipe;
  logic               pipe_flushed;
  logic               dbg_trap;
  logic               dbg_st_en;       // single-step trace mode enabled
  logic [1:0]         dbg_dsr;         // Debug Stop Register

  logic               dbg_reg_mux;
  logic               dbg_sp_mux;
  logic               dbg_reg_we;
  logic [11:0]        dbg_reg_addr;
  logic [31:0]        dbg_reg_wdata;
  logic [31:0]        dbg_reg_rdata;
  logic [31:0]        dbg_rdata;

  logic [31:0]        dbg_npc;
  logic               dbg_set_npc;

`ifdef TCDM_ADDR_PRECAL
  logic [31:0]         alu_adder_ex;
`endif


  // TODO: Temporary assignments while not everything from OR10N is implemented (e.g. debug unit)
  assign dbg_dsr        = 2'b0;
  assign dbg_st_en      = 1'b0;
  assign dbg_sp_mux     = 1'b0;
  assign dbg_flush_pipe = 1'b0;


    //////////////////////////////////////////////////
    //   ___ _____   ____ _____  _    ____ _____    //
    //  |_ _|  ___| / ___|_   _|/ \  / ___| ____|   //
    //   | || |_    \___ \ | | / _ \| |  _|  _|     //
    //   | ||  _|    ___) || |/ ___ \ |_| | |___    //
    //  |___|_|     |____/ |_/_/   \_\____|_____|   //
    //                                              //
    //////////////////////////////////////////////////
    if_stage if_stage_i
    (
       // Global signals reset and clock
      .clk                 ( clk                  ),   // Clock
      .rst_n               ( rst_n                ),   // active low reset

      // Boot address for exception vector offsets
      .boot_addr_i         ( boot_addr_i          ),

      // outputs to ID stage
      .instr_rdata_id_o    ( instr_rdata_id       ),   // Output of IF Pipeline stage
      .current_pc_if_o     ( current_pc_if        ),   // current pc
      .current_pc_id_o     ( current_pc_id        ),   // current pc

      //Input - OUtput from-to  instruction memory
      .instr_rdata_i       ( instr_rdata_int      ),   // From Instr memory
      .instr_addr_o        ( instr_addr_int       ),   // address for instruction fetch to instr memory/cache

      // Forwrding ports - control signals
      .force_nop_i         ( force_nop_id         ),   // select incoming instr or NOP
      .exception_pc_reg_i  ( epcr                 ),   // Exception PC register
      .pc_from_hwloop_i    ( hwlp_targ_addr       ),   // pc from hwloop start address
      .pc_mux_sel_i        ( pc_mux_sel_id        ),   // sel for pc multiplexer
      .pc_mux_boot_i       ( pc_mux_boot          ),   // load boot address as PC
      .exc_pc_mux_i        ( exc_pc_mux_id        ),   // selector for exception multiplexer

      // from debug unit
      .dbg_pc_from_npc     ( dbg_npc              ),
      .dbg_set_npc         ( dbg_set_npc          ),

      // Jump and branch target and decision
      .jump_in_id_i        ( jump_in_id           ),
      .jump_in_ex_i        ( jump_in_ex           ),
      .branch_decision_i   ( branch_decision      ),
      .jump_target_i       ( jump_target          ),

      .compressed_instr_i  ( compressed_instr     ),

      // pipeline stalls
      .stall_if_i          ( stall_if             ),
      .stall_id_i          ( stall_id             )
    );


    ///////////////////////////////////////////////////////////////////////////////////
    //  ___ _   _ ____ _____ ____     ____ ___  ____  _____   ___ _   _ _____ _____  //
    // |_ _| \ | / ___|_   _|  _ \   / ___/ _ \|  _ \| ____| |_ _| \ | |_   _|  ___| //
    //  | ||  \| \___ \ | | | |_) | | |  | | | | |_) |  _|    | ||  \| | | | | |_    //
    //  | || |\  |___) || | |  _ <  | |__| |_| |  _ <| |___   | || |\  | | | |  _|   //
    // |___|_| \_|____/ |_| |_| \_\  \____\___/|_| \_\_____| |___|_| \_| |_| |_|     //
    //                                                                               //
    ///////////////////////////////////////////////////////////////////////////////////
    instr_core_interface        instr_core_interface_i
    (
      .clk                 ( clk             ),
      .rst_n               ( rst_n           ),

      .stall_if_i          ( stall_if        ),

      .req_i               ( instr_req_int   ),
      .addr_i              ( instr_addr_int  ),
      .ack_o               ( instr_ack_int   ),
      .rdata_o             ( instr_rdata_int ),

      .instr_req_o         ( instr_req_o     ),
      .instr_addr_o        ( instr_addr_o    ),
      .instr_gnt_i         ( instr_grant_i   ),
      .instr_r_valid_i     ( instr_rvalid_i  ),
      .instr_r_rdata_i     ( instr_rdata_i   ),

      .drop_request_i      ( 1'b0 )
    );


    /////////////////////////////////////////////////
    //   ___ ____    ____ _____  _    ____ _____   //
    //  |_ _|  _ \  / ___|_   _|/ \  / ___| ____|  //
    //   | || | | | \___ \ | | / _ \| |  _|  _|    //
    //   | || |_| |  ___) || |/ ___ \ |_| | |___   //
    //  |___|____/  |____/ |_/_/   \_\____|_____|  //
    //                                             //
    /////////////////////////////////////////////////
    id_stage id_stage_i
    (
      .clk                          ( clk                           ),
      .rst_n                        ( rst_n                         ),

      // Processor Enable
      .fetch_enable_i               ( fetch_enable_i                ),

      .jump_in_id_o                 ( jump_in_id                    ),
      .jump_in_ex_o                 ( jump_in_ex                    ),

      .core_busy_o                  ( core_busy_o                   ),

      // Interface to instruction memory
      .instr_rdata_i                ( instr_rdata_id                ),
      .instr_req_o                  ( instr_req_int                 ),
      .instr_gnt_i                  ( instr_grant_i                 ),
      .instr_ack_i                  ( instr_ack_int                 ),

      .pc_mux_sel_o                 ( pc_mux_sel_id                 ),
      .pc_mux_boot_o                ( pc_mux_boot                   ),
      .exc_pc_mux_o                 ( exc_pc_mux_id                 ),
      .force_nop_o                  ( force_nop_id                  ),

      .current_pc_if_i              ( current_pc_if                 ),
      .current_pc_id_i              ( current_pc_id                 ),

      .compressed_instr_o           ( compressed_instr              ),

      // STALLS
      .stall_if_o                   ( stall_if                      ),
      .stall_id_o                   ( stall_id                      ),
      .stall_ex_o                   ( stall_ex                      ),
      .stall_wb_o                   ( stall_wb                      ),

      // From the Pipeline ID/EX
      .regfile_rb_data_ex_o         ( regfile_rb_data_ex            ),

      .alu_operand_a_ex_o           ( alu_operand_a_ex              ),
      .alu_operand_b_ex_o           ( alu_operand_b_ex              ),
      .alu_operand_c_ex_o           ( alu_operand_c_ex              ),
      .alu_operator_ex_o            ( alu_operator_ex               ),

      .vector_mode_ex_o             ( vector_mode_ex                ), // from ID to EX stage
      .alu_cmp_mode_ex_o            ( alu_cmp_mode_ex               ), // from ID to EX stage
      .alu_vec_ext_ex_o             ( alu_vec_ext_ex                ), // from ID to EX stage

      .mult_en_ex_o                 ( mult_en_ex                    ), // from ID to EX stage
      .mult_sel_subword_ex_o        ( mult_sel_subword_ex           ), // from ID to EX stage
      .mult_signed_mode_ex_o        ( mult_signed_mode_ex           ), // from ID to EX stage
      .mult_use_carry_ex_o          ( mult_use_carry_ex             ), // from ID to EX stage
      .mult_mac_en_ex_o             ( mult_mac_en_ex                ), // from ID to EX stage

      .regfile_waddr_ex_o           ( regfile_waddr_ex              ),
      .regfile_wdata_mux_sel_ex_o   ( regfile_wdata_mux_sel_ex      ),
      .regfile_we_ex_o              ( regfile_we_ex                 ),

      .regfile_alu_we_ex_o          ( regfile_alu_we_ex             ),
      .regfile_alu_waddr_ex_o       ( regfile_alu_waddr_ex          ),

      // CSR ID/EX
      .csr_access_ex_o              ( csr_access_ex                 ),
      .csr_op_ex_o                  ( csr_op_ex                     ),

      // hwloop signals
      .hwloop_we_ex_o               ( hwlp_we_ex                    ),
      .hwloop_regid_ex_o            ( hwlp_regid_ex                 ),
      .hwloop_wb_mux_sel_ex_o       ( hwlp_wb_mux_sel_ex            ),
      .hwloop_cnt_o                 ( hwlp_cnt_ex                   ),
      .hwloop_dec_cnt_o             ( hwlp_dec_cnt                  ),
      .hwloop_targ_addr_o           ( hwlp_targ_addr                ),

      .prepost_useincr_ex_o         ( useincr_addr_ex               ),
      .data_misaligned_i            ( data_misaligned               ),

      .data_we_ex_o                 ( data_we_ex                    ), // to   load store unit
      .data_type_ex_o               ( data_type_ex                  ), // to   load store unit
      .data_sign_ext_ex_o           ( data_sign_ext_ex              ), // to   load store unit
      .data_reg_offset_ex_o         ( data_reg_offset_ex            ), // to   load store unit
      .data_req_ex_o                ( data_req_ex                   ), // to   load store unit
      .data_misaligned_ex_o         ( data_misaligned_ex            ), // to   load store unit
      .data_ack_i                   ( data_ack_int                  ), // from load store unit
      .data_rvalid_i                ( data_r_valid_i                ),

      // Interrupt Signals
      .irq_i                        ( irq_i                         ), // incoming interrupts
      .irq_nm_i                     ( irq_nm_i                      ), // incoming interrupts
      .irq_enable_i                 ( irq_enable                    ), // global interrupt enable
      .save_pc_if_o                 ( save_pc_if                    ), // control signal to save pc
      .save_pc_id_o                 ( save_pc_id                    ), // control signal to save pc
      .save_sr_o                    ( save_sr                       ), // control signal to save status register
      .restore_sr_o                 ( restore_sr                    ), // restore status register

      // from hwloop regs
      .hwloop_start_addr_i          ( hwlp_start_addr               ),
      .hwloop_end_addr_i            ( hwlp_end_addr                 ),
      .hwloop_counter_i             ( hwlp_counter                  ),

      // Debug Unit Signals
      .dbg_flush_pipe_i             ( dbg_flush_pipe                ),
      .pipe_flushed_o               ( pipe_flushed                  ),
      .dbg_st_en_i                  ( dbg_st_en                     ),
      .dbg_dsr_i                    ( dbg_dsr                       ),
      .dbg_stall_i                  ( dbg_stall                     ),
      .dbg_trap_o                   ( dbg_trap                      ),
      .dbg_reg_mux_i                ( dbg_reg_mux                   ),
      .dbg_reg_we_i                 ( dbg_reg_we                    ),
      .dbg_reg_addr_i               ( dbg_reg_addr[4:0]             ),
      .dbg_reg_wdata_i              ( dbg_reg_wdata                 ),
      .dbg_reg_rdata_o              ( dbg_reg_rdata                 ),
      .dbg_set_npc_i                ( dbg_set_npc                   ),

      // Forward Signals
      .regfile_alu_waddr_fw_i       ( regfile_alu_waddr_fw          ),
      .regfile_alu_we_fw_i          ( regfile_alu_we_fw             ),
      .regfile_alu_wdata_fw_i       ( regfile_alu_wdata_fw          ),

      .regfile_waddr_wb_i           ( regfile_waddr_fw_wb_o         ),  // Write address ex-wb pipeline
      .regfile_we_wb_i              ( regfile_we_wb                 ),  // write enable for the register file
      .regfile_wdata_wb_i           ( regfile_wdata                 )   // write data to commit in the register file
`ifdef TCDM_ADDR_PRECAL
      ,
      .alu_adder_o                  ( alu_adder_ex                  )
`endif
    );


    /////////////////////////////////////////////////////
    //   _______  __  ____ _____  _    ____ _____      //
    //  | ____\ \/ / / ___|_   _|/ \  / ___| ____|     //
    //  |  _|  \  /  \___ \ | | / _ \| |  _|  _|       //
    //  | |___ /  \   ___) || |/ ___ \ |_| | |___      //
    //  |_____/_/\_\ |____/ |_/_/   \_\____|_____|     //
    //                                                 //
    /////////////////////////////////////////////////////
    ex_stage  ex_stage_i
    (
      // Global signals: Clock and active low asynchronous reset
      .clk                        ( clk                          ),
      .rst_n                      ( rst_n                        ),

      // Alu signals from ID stage
      .alu_operator_i             ( alu_operator_ex              ), // from ID/EX pipe registers
      .alu_operand_a_i            ( alu_operand_a_ex             ), // from ID/EX pipe registers
      .alu_operand_b_i            ( alu_operand_b_ex             ), // from ID/EX pipe registers
      .alu_operand_c_i            ( alu_operand_c_ex             ), // from ID/EX pipe registers

      .vector_mode_i              ( vector_mode_ex               ), // from ID/EX pipe registers
      .alu_cmp_mode_i             ( alu_cmp_mode_ex              ), // from ID/EX pipe registers
      .alu_vec_ext_i              ( alu_vec_ext_ex               ), // from ID/EX pipe registers

      // Multipler
      .mult_en_i                  ( mult_en_ex                   ),
      .mult_sel_subword_i         ( mult_sel_subword_ex          ),
      .mult_signed_mode_i         ( mult_signed_mode_ex          ),
      .mult_use_carry_i           ( mult_use_carry_ex            ),
      .mult_mac_en_i              ( mult_mac_en_ex               ),

      // interface with CSRs
      .csr_access_i               ( csr_access_ex                ),
      .csr_rdata_i                ( csr_rdata                    ),

      // input from ID stage
      .stall_ex_i                 ( stall_ex                     ),
      .stall_wb_i                 ( stall_wb                     ),

      .prepost_useincr_i          ( useincr_addr_ex              ),

      // From ID Stage: Regfile control signals
      .regfile_waddr_i            ( regfile_waddr_ex             ),
      .regfile_wdata_mux_sel_i    ( regfile_wdata_mux_sel_ex     ),
      .regfile_we_i               ( regfile_we_ex                ),

      .regfile_alu_we_i           ( regfile_alu_we_ex            ),
      .regfile_alu_waddr_i        ( regfile_alu_waddr_ex         ),

      // From ID stage: hwloop wb reg signals
      .hwloop_wb_mux_sel_i        ( hwlp_wb_mux_sel_ex           ),
      .hwloop_pc_plus4_i          ( current_pc_id                ),
      .hwloop_cnt_i               ( hwlp_cnt_ex                  ),

      //From ID stage.Controller
      .regfile_rb_data_i          ( regfile_rb_data_ex           ),

      // Output of ex stage pipeline
      .regfile_waddr_wb_o         ( regfile_waddr_fw_wb_o        ),
      .regfile_wdata_mux_sel_wb_o ( regfile_wdata_mux_sel_wb     ),
      .regfile_we_wb_o            ( regfile_we_wb                ),
      .regfile_rb_data_wb_o       ( regfile_rb_data_wb           ),

      .data_addr_ex_o             ( data_addr_ex                 ),

      // To hwloop regs
      .hwloop_start_data_o        ( hwlp_start_data_ex           ),
      .hwloop_end_data_o          ( hwlp_end_data_ex             ),
      .hwloop_cnt_data_o          ( hwlp_cnt_data_ex             ),

      // To IF: Jump and branch target and decision
      .jump_target_o              ( jump_target                  ),
      .branch_decision_o          ( branch_decision              ),

      // To ID stage: Forwarding signals
      .regfile_alu_waddr_fw_o     ( regfile_alu_waddr_fw         ),
      .regfile_alu_we_fw_o        ( regfile_alu_we_fw            ),
      .regfile_alu_wdata_fw_o     ( regfile_alu_wdata_fw         )

`ifdef TCDM_ADDR_PRECAL
      ,
      .alu_adder_i                ( alu_adder_ex                 )
`endif
    );


    /////////////////////////////////////////////////////////
    //  __        ______    ____ _____  _    ____ _____    //
    //  \ \      / / __ )  / ___|_   _|/ \  / ___| ____|   //
    //   \ \ /\ / /|  _ \  \___ \ | | / _ \| |  _|  _|     //
    //    \ V  V / | |_) |  ___) || |/ ___ \ |_| | |___    //
    //     \_/\_/  |____/  |____/ |_/_/   \_\____|_____|   //
    //                                                     //
    /////////////////////////////////////////////////////////
    wb_stage  wb_stage_i
    (
      // Mux selector of regfile wdata
      .regfile_wdata_mux_sel_i ( regfile_wdata_mux_sel_wb  ),
      // Mux inputs
      .data_rdata_i            ( data_rdata_int            ),
      .lsu_data_reg_i          ( lsu_data_reg              ),
      // Mux output
      .regfile_wdata_o         ( regfile_wdata             )
    );


    ////////////////////////////////////////////////////////////////////////////////////////
    //    _     ___    _    ____    ____ _____ ___  ____  _____   _   _ _   _ ___ _____   //
    //   | |   / _ \  / \  |  _ \  / ___|_   _/ _ \|  _ \| ____| | | | | \ | |_ _|_   _|  //
    //   | |  | | | |/ _ \ | | | | \___ \ | || | | | |_) |  _|   | | | |  \| || |  | |    //
    //   | |__| |_| / ___ \| |_| |  ___) || || |_| |  _ <| |___  | |_| | |\  || |  | |    //
    //   |_____\___/_/   \_\____/  |____/ |_| \___/|_| \_\_____|  \___/|_| \_|___| |_|    //
    //                                                                                    //
    ////////////////////////////////////////////////////////////////////////////////////////
    load_store_unit  load_store_unit_i
    (
      .clk                   ( clk                    ),
      .rst_n                 ( rst_n                  ),

      // signal from ex stage
      .data_we_ex_i          ( data_we_ex              ),
      .data_type_ex_i        ( data_type_ex            ),
      .data_wdata_ex_i       ( regfile_rb_data_ex      ),
      .data_reg_offset_ex_i  ( data_reg_offset_ex      ),

      .data_sign_ext_ex_i    ( data_sign_ext_ex        ),  // sign extension
      .data_rdata_ex_o       ( data_rdata_int          ),
      .lsu_data_reg_o        ( lsu_data_reg            ),
      .data_req_ex_i         ( data_req_ex             ),
      .data_addr_ex_i        ( data_addr_ex            ),
      .data_ack_int_o        ( data_ack_int            ),  // ack used in controller to stall

      .data_misaligned_ex_i  ( data_misaligned_ex      ), // from ID/EX pipeline
      .data_misaligned_o     ( data_misaligned         ),

      //output to data memory
      .data_be_o             ( data_be_o               ),
      .data_wdata_o          ( data_wdata_o            ),
      .data_rdata_i          ( data_rdata_i            ),
      .data_rvalid_i         ( data_r_valid_i          ),
      .data_addr_o           ( data_addr_o             ),
      .data_we_o             ( data_we_o               ),
      .data_req_o            ( data_req_o              ),
      .data_gnt_i            ( data_gnt_i              ),

      .ex_stall_i            ( stall_ex                )
    );


    //////////////////////////////////////
    //        ____ ____  ____           //
    //       / ___/ ___||  _ \ ___      //
    //      | |   \___ \| |_) / __|     //
    //      | |___ ___) |  _ <\__ \     //
    //       \____|____/|_| \_\___/     //
    //                                  //
    //   Control and Status Registers   //
    //////////////////////////////////////
    cs_registers cs_registers_i
    (
      .clk                     ( clk                   ),
      .rst_n                   ( rst_n                 ),

      // Core and Cluster ID from outside
      .core_id_i               ( core_id_i             ),
      .cluster_id_i            ( cluster_id_i          ),

      // Interface to Special register (SRAM LIKE)
      .csr_addr_i              ( csr_addr              ),
      .csr_wdata_i             ( csr_wdata             ),
      .csr_op_i                ( csr_op                ),
      .csr_rdata_o             ( csr_rdata             ),

      // HWLoop signals
      .hwlp_start_addr_i       ( hwlp_start_addr       ),
      .hwlp_end_addr_i         ( hwlp_end_addr         ),
      .hwlp_counter_i          ( hwlp_counter          ),

      .hwlp_start_o            ( sp_hwlp_start         ),
      .hwlp_end_o              ( sp_hwlp_end           ),
      .hwlp_counter_o          ( sp_hwlp_cnt           ),
      .hwlp_regid_o            ( sp_hwlp_regid         ),
      .hwlp_we_o               ( sp_hwlp_we            ),

      .curr_pc_if_i            ( current_pc_if         ), // from IF stage
      .curr_pc_id_i            ( current_pc_id         ), // from IF stage
      .save_pc_if_i            ( save_pc_if            ),
      .save_pc_id_i            ( save_pc_id            ),
      .epcr_o                  ( epcr                  ),
      .irq_enable_o            ( irq_enable            ),

      .npc_o                   ( dbg_npc               ), // PC from debug unit
      .set_npc_o               ( dbg_set_npc           )  // set PC to new value
    );

    // Mux for SPR access through Debug Unit
    assign csr_addr      = (dbg_sp_mux == 1'b0) ? alu_operand_b_ex[11:0] : dbg_reg_addr;
    assign csr_wdata     = (dbg_sp_mux == 1'b0) ? alu_operand_a_ex : dbg_reg_wdata;
    assign csr_op        = (dbg_sp_mux == 1'b0) ? csr_op_ex
                                                : (dbg_reg_we == 1'b1 ? `CSR_OP_WRITE : `CSR_OP_NONE);
    assign dbg_rdata     = (dbg_sp_mux == 1'b0) ? dbg_reg_rdata    : csr_rdata;


    /*
    sp_registers sp_registers_i
    (
      .clk                     ( clk                   ),
      .rst_n                   ( rst_n                 ),

      // Core and Cluster ID from outside
      .core_id_i               ( core_id_i             ),
      .cluster_id_i            ( cluster_id_i          ),

      // Interface to Special register (SRAM LIKE)
      .sp_addr_i               ( sp_addr               ),
      .sp_wdata_i              ( sp_wdata              ),
      .sp_op_i                 ( sp_op                 ),
      .sp_rdata_o              ( sp_rdata              ),

      // Stall direct write
      .enable_direct_write_i   ( stall_wb              ),

      // HWLoop signals
      .hwlp_start_addr_i       ( hwlp_start_addr       ),
      .hwlp_end_addr_i         ( hwlp_end_addr         ),
      .hwlp_counter_i          ( hwlp_counter          ),

      .hwlp_start_o            ( sp_hwlp_start         ),
      .hwlp_end_o              ( sp_hwlp_end           ),
      .hwlp_counter_o          ( sp_hwlp_cnt           ),
      .hwlp_regid_o            ( sp_hwlp_regid         ),
      .hwlp_we_o               ( sp_hwlp_we            ),

      .curr_pc_if_i            ( current_pc_if         ), // from IF stage
      .curr_pc_id_i            ( current_pc_id         ), // from IF stage
      .save_pc_if_i            ( save_pc_if            ),
      .save_pc_id_i            ( save_pc_id            ),
      .save_sr_i               ( save_sr               ),
      .restore_sr_i            ( restore_sr            ),
      .epcr_o                  ( epcr                  ),
      .irq_enable_o            ( irq_enable            ),

      .npc_o                   ( dbg_npc               ), // PC from debug unit
      .set_npc_o               ( dbg_set_npc           )  // set PC to new value
    );

    // Mux for SPR access through Debug Unit
    assign sp_addr       = (dbg_sp_mux == 1'b0) ? sp_addr_wb         : dbg_reg_addr;
    assign sp_wdata      = (dbg_sp_mux == 1'b0) ? regfile_rb_data_wb : dbg_reg_wdata;
    assign sp_op         = (dbg_sp_mux == 1'b0) ? sp_op_wb
                                                : (dbg_reg_we == 1'b1 ? `CSR_OP_WRITE : `CSR_OP_NONE);
    assign dbg_rdata     = (dbg_sp_mux == 1'b0) ? dbg_reg_rdata      : sp_rdata;
    */


    /*

    //////////////////////////////////////////////
    //      Hardware Loop Registers             //
    //////////////////////////////////////////////
    hwloop_regs hwloop_regs_i
    (
      .clk                     ( clk                 ),
      .rst_n                   ( rst_n               ),

      // from ex stage
      .hwloop_start_data_i     ( hwlp_start_data     ),
      .hwloop_end_data_i       ( hwlp_end_data       ),
      .hwloop_cnt_data_i       ( hwlp_cnt_data       ),
      .hwloop_we_i             ( hwlp_we             ),
      .hwloop_regid_i          ( hwlp_regid          ),

      // from controller
      .stall_id_i              ( stall_id            ),

      // to hwloop controller
      .hwloop_start_addr_o     ( hwlp_start_addr     ),
      .hwloop_end_addr_o       ( hwlp_end_addr       ),
      .hwloop_counter_o        ( hwlp_counter        ),

      // from hwloop controller
      .hwloop_dec_cnt_i        ( hwlp_dec_cnt        )
    );

   // write to hwloop registers via SPR or instructions
   assign hwlp_start_data = (hwlp_we_ex[0] == 1'b1) ? hwlp_start_data_ex : sp_hwlp_start;
   assign hwlp_end_data   = (hwlp_we_ex[1] == 1'b1) ? hwlp_end_data_ex   : sp_hwlp_end;
   assign hwlp_cnt_data   = (hwlp_we_ex[2] == 1'b1) ? hwlp_cnt_data_ex   : sp_hwlp_cnt;
   assign hwlp_regid      = (|hwlp_we_ex)           ? hwlp_regid_ex      : sp_hwlp_regid;
   assign hwlp_we         = hwlp_we_ex | sp_hwlp_we;


    /////////////////////////////////////////////////////////////
    //  ____  _____ ____  _   _  ____   _   _ _   _ ___ _____  //
    // |  _ \| ____| __ )| | | |/ ___| | | | | \ | |_ _|_   _| //
    // | | | |  _| |  _ \| | | | |  _  | | | |  \| || |  | |   //
    // | |_| | |___| |_) | |_| | |_| | | |_| | |\  || |  | |   //
    // |____/|_____|____/ \___/ \____|  \___/|_| \_|___| |_|   //
    //                                                         //
    /////////////////////////////////////////////////////////////
    debug_unit debug_unit_i
    (
      .clk             ( clk             ),
      .rst_n           ( rst_n           ),

      // Debug Interface
      .dbginf_stall_i  ( dbginf_stall_i  ),
      .dbginf_bp_o     ( dbginf_bp_o     ),
      .dbginf_strobe_i ( dbginf_strobe_i ),
      .dbginf_ack_o    ( dbginf_ack_o    ),
      .dbginf_we_i     ( dbginf_we_i     ),
      .dbginf_addr_i   ( dbginf_addr_i   ),
      .dbginf_data_i   ( dbginf_data_i   ),
      .dbginf_data_o   ( dbginf_data_o   ),

      // To/From Core
      .dbg_st_en_o     ( dbg_st_en       ),
      .dbg_dsr_o       ( dbg_dsr         ),
      .stall_core_o    ( dbg_stall       ),
      .flush_pipe_o    ( dbg_flush_pipe  ),
      .pipe_flushed_i  ( pipe_flushed    ),
      .trap_i          ( dbg_trap        ),

      // register file access
      .regfile_mux_o   ( dbg_reg_mux     ),
      .sp_mux_o        ( dbg_sp_mux      ),
      .regfile_we_o    ( dbg_reg_we      ),
      .regfile_addr_o  ( dbg_reg_addr    ),
      .regfile_wdata_o ( dbg_reg_wdata   ),
      .regfile_rdata_i ( dbg_rdata       )
    );

  */

  assign dbg_reg_mux = 0;
  assign dbg_stall = 0;


  // Execution trace generation
  // synopsys translate_off
  `ifdef TRACE_EXECUTION
  integer f;
  string fn;
  logic [31:0] instr;
  logic        compressed;
  logic [31:0] pc;
  logic  [5:0] rd, rs1, rs2;
  logic [31:0] rs1_value, rs2_value;
  logic [31:0] imm;
  string mnemonic;

  // open/close output file for writing
  initial
  begin
    #1
    $sformat(fn, "trace_core_%h.log", core_id_i);
    $display("Output file: %s", fn);
    f = $fopen(fn, "w");
  end

  final
  begin
    $fclose(f);
  end

  // log execution
  always @(posedge clk)
  begin
    #1

    // get current PC and instruction
    instr      = id_stage_i.instr[31:0];
    compressed = id_stage_i.compressed_instr_o;
    pc         = id_stage_i.current_pc_id_i;

    // get register values
    rd         = instr[`REG_D];
    rs1        = instr[`REG_S1];
    rs1_value  = id_stage_i.operand_a_fw_id; //r[rs1];
    rs2        = instr[`REG_S2];
    rs2_value  = id_stage_i.operand_b_fw_id; //r[rs2];

    if (id_stage_i.stall_id_o == 1'b0 && id_stage_i.controller_i.ctrl_fsm_cs == id_stage_i.controller_i.DECODE)
    begin
      mnemonic = "";
      imm = 0;

      $fwrite(f, "%t:\t0x%h\t0x%h\t", $time, pc, instr);
      if (compressed)
        //$fwrite(f, "C (0x%4h)\t", id_stage_i.instr_rdata_i[15:0]);
        $fwrite(f, "C\t");
      else
        $fwrite(f, "I\t");

      // use casex instead of case inside due to ModelSim bug
      casex (instr)
        // Aliases
        32'h00_00_00_13:   printMnemonic("NOP");
        // Regular opcodes
        `INSTR_CUSTOM0:    printMnemonic("CUSTOM0");
        `INSTR_CUSTOM1:    printMnemonic("CUSTOM1");
        `INSTR_LUI:        printIInstr("LUI");
        `INSTR_AUIPC:      printIInstr("AUIPC");
        `INSTR_JAL:        printUJInstr("JAL");
        `INSTR_JALR:       printIInstr("JALR");
        // BRANCH
        `INSTR_BEQ:        printSBInstr("BEQ");
        `INSTR_BNE:        printSBInstr("BNE");
        `INSTR_BLT:        printSBInstr("BLT");
        `INSTR_BGE:        printSBInstr("BGE");
        `INSTR_BLTU:       printSBInstr("BLTU");
        `INSTR_BGEU:       printSBInstr("BGEU");
        // LOAD
        `INSTR_LB:         printILInstr("LB");
        `INSTR_LH:         printILInstr("LH");
        `INSTR_LW:         printILInstr("LW");
        `INSTR_LBU:        printILInstr("LBU");
        `INSTR_LHU:        printILInstr("LHU");
        // STORE
        `INSTR_SB:         printSInstr("SB");
        `INSTR_SH:         printSInstr("SH");
        `INSTR_SW:         printSInstr("SW");
        // OPIMM
        `INSTR_ADDI:       printIInstr("ADDI");
        `INSTR_SLTI:       printIInstr("SLTI");
        `INSTR_SLTIU:      printIInstr("SLTIU");
        `INSTR_XORI:       printIInstr("XORI");
        `INSTR_ORI:        printIInstr("ORI");
        `INSTR_ANDI:       printIInstr("ANDI");
        `INSTR_SLLI:       printIInstr("SLLI");
        `INSTR_SRLI:       printIInstr("SRLI");
        `INSTR_SRAI:       printIInstr("SRAI");
        // OP
        `INSTR_ADD:        printRInstr("ADD");
        `INSTR_SUB:        printRInstr("SUB");
        `INSTR_SLL:        printRInstr("SLL");
        `INSTR_SLT:        printRInstr("SLT");
        `INSTR_SLTU:       printRInstr("SLTU");
        `INSTR_XOR:        printRInstr("XOR");
        `INSTR_SRL:        printRInstr("SRL");
        `INSTR_SRA:        printRInstr("SRA");
        `INSTR_OR:         printRInstr("OR");
        `INSTR_AND:        printRInstr("AND");
        // FENCE
        `INSTR_FENCE:      printMnemonic("FENCE");
        `INSTR_FENCEI:     printMnemonic("FENCEI");
        // SYSTEM (CSR manipulation)
        `INSTR_CSRRW:      printCSRInstr("CSRRW");
        `INSTR_CSRRS:      printCSRInstr("CSRRS");
        `INSTR_CSRRC:      printCSRInstr("CSRRC");
        `INSTR_CSRRWI:     printCSRInstr("CSRRWI");
        `INSTR_CSRRSI:     printCSRInstr("CSRRSI");
        `INSTR_CSRRCI:     printCSRInstr("CSRRCI");
        // SYSTEM (others)
        `INSTR_ECALL:      printMnemonic("ECALL");
        `INSTR_EBREAK:     printMnemonic("EBREAK");
        `INSTR_ERET:       printMnemonic("ERET");
        `INSTR_WFI:        printMnemonic("WFI");
        `INSTR_RDCYCLE:    printRDInstr("RDCYCLE");
        `INSTR_RDCYCLEH:   printRDInstr("RDCYCLEH");
        `INSTR_RDTIME:     printRDInstr("RDTIME");
        `INSTR_RDTIMEH:    printRDInstr("RDTIMEH");
        `INSTR_RDINSTRET:  printRDInstr("RDINSTRET");
        `INSTR_RDINSTRETH: printRDInstr("RDINSTRETH");
        // RV32M
        `INSTR_MUL:        printRInstr("MUL");
        /*
        `INSTR_MULH:       printRInstr("MULH");
        `INSTR_MULHSU:     printRInstr("MULHSU");
        `INSTR_MULHU:      printRInstr("MULHU");
        */
        default:           printMnemonic("Unknown instruction");
      endcase // unique case (instr)
    end
  end // always @ (posedge clk)

  function void printMnemonic(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      $fdisplay(f, "%s", mnemonic);
    end
  endfunction // printMnemonic

  function void printRInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      $fdisplay(f, "%s\tx%0d, x%0d (0x%h), x%0d (0x%h)", mnemonic,
                rd, rs1, rs1_value, rs2, rs2_value);
    end
  endfunction // printRInstr

  function void printIInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      imm = id_stage_i.imm_i_type;
      $fdisplay(f, "%s\tx%0d, x%0d (0x%h), 0x%0d (imm)", mnemonic,
                rd, rs1, rs1_value, imm);
    end
  endfunction // printIInstr

  function void printILInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      imm = id_stage_i.imm_i_type;
      $fdisplay(f, "%s\tx%0d, x%0d (0x%h), 0x%0d (imm) (-> 0x%h)", mnemonic,
                rd, rs1, rs1_value, imm, imm+rs1_value);
    end
  endfunction // printILInstr

  function void printSInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      imm = id_stage_i.imm_s_type;
      $fdisplay(f, "%s\tx%0d (0x%h), x%0d (0x%h), 0x%h (imm) (-> 0x%h)", mnemonic,
                rs1, rs1_value, rs2, rs2_value, imm, imm+rs1_value);
    end
  endfunction // printSInstr

  function void printSBInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      imm = id_stage_i.imm_sb_type;
      $fdisplay(f, "%s\tx%0d (0x%h), x%0d (0x%h), 0x%h (-> 0x%h)", mnemonic,
                rs1, rs1_value, rs2, rs2_value, imm, imm+pc);
    end
  endfunction // printSBInstr

  function void printUJInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      imm = id_stage_i.imm_uj_type;
      $fdisplay(f, "%s\tx%0d, 0x%h (-> 0x%h)", mnemonic, rd, imm, imm+pc);
    end
  endfunction // printUJInstr

  function void printRDInstr(input string mnemonic);
    begin
      riscv_core.mnemonic = mnemonic;
      $fdisplay(f, "%s\tx%0d", mnemonic, rd);
    end
  endfunction // printRDInstr

  function void printCSRInstr(input string mnemonic);
    logic [11:0] csr;
    begin
      riscv_core.mnemonic = mnemonic;
      imm = id_stage_i.imm_z_type;
      csr = instr[31:20];

      if (instr[14] == 1'b0) begin
        $fdisplay(f, "%s\tx%0d, 0x%h (csr), x%0d (0x%h)", mnemonic, rd, csr,
          rs1, rs1_value);
      end else begin
        $fdisplay(f, "%s\tx%0d, 0x%h (csr), 0x%h (imm)", mnemonic, rd, csr, imm);
      end
    end
  endfunction // printCSRInstr

  `endif // TRACE_EXECUTION
  // synopsys translate_on


///////////////////
endmodule // cpu //
///////////////////
