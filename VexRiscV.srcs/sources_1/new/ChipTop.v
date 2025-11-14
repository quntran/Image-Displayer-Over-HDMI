`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// Create Date: 11/01/2025 
// Design Name: 
// Module Name: ChipTop
// Target Devices: Arty Z7-20
// Description: RISC-V + HDMI system top
//////////////////////////////////////////////////////////////////////////////////

module ChipTop (
    input  wire sys_clk,        // 125 MHz board clock
    input  wire sys_resetn,     // active-low reset
    output wire [2:0] hdmi_tx_p,
    output wire [2:0] hdmi_tx_n,
    output wire       hdmi_clk_p,
    output wire       hdmi_clk_n,
    
    input wire hdmi_tx_hpdn,
    output wire [1:0] led
);

    // ===============================================
    // 1. Clock and reset
    // ===============================================
    wire clk_125MHz = sys_clk;
    wire resetn = sys_resetn;
    wire clk_tmds;
    
    reg [25:0] cnt;
    always @(posedge sys_clk) cnt <= cnt + 1;
    assign led[0] = cnt[25];
    
    assign led[1] = ~hdmi_tx_hpdn;

    // ===============================================
    // 2. CPU buses and signals
    // ===============================================
    wire          iBus_cmd_valid;
    wire          iBus_cmd_ready;
    wire  [31:0]  iBus_cmd_payload_pc;
    wire          iBus_rsp_valid;
    wire  [31:0]  iBus_rsp_payload_inst;
    wire          iBus_rsp_payload_error;

    wire          dBus_cmd_valid;
    wire          dBus_cmd_ready;
    wire          dBus_cmd_payload_wr;
    wire  [3:0]   dBus_cmd_payload_mask;
    wire  [31:0]  dBus_cmd_payload_address;
    wire  [31:0]  dBus_cmd_payload_data;
    wire  [1:0]   dBus_cmd_payload_size;
    wire          dBus_rsp_ready;
    wire          dBus_rsp_error;
    wire  [31:0]  dBus_rsp_data;

    // ===============================================
    // 3. Instantiate VexRiscv CPU
    // ===============================================
    VexRiscv cpu_inst (
        .clk(clk_125MHz),
        .reset(~resetn),

        // Instruction bus
        .iBus_cmd_valid(iBus_cmd_valid),
        .iBus_cmd_ready(iBus_cmd_ready),
        .iBus_cmd_payload_pc(iBus_cmd_payload_pc),
        .iBus_rsp_valid(iBus_rsp_valid),
        .iBus_rsp_payload_error(iBus_rsp_payload_error),
        .iBus_rsp_payload_inst(iBus_rsp_payload_inst),

        // Data bus
        .dBus_cmd_valid(dBus_cmd_valid),
        .dBus_cmd_ready(dBus_cmd_ready),
        .dBus_cmd_payload_wr(dBus_cmd_payload_wr),
        .dBus_cmd_payload_mask(dBus_cmd_payload_mask),
        .dBus_cmd_payload_address(dBus_cmd_payload_address),
        .dBus_cmd_payload_data(dBus_cmd_payload_data),
        .dBus_cmd_payload_size(dBus_cmd_payload_size),
        .dBus_rsp_ready(dBus_rsp_ready),
        .dBus_rsp_error(dBus_rsp_error),
        .dBus_rsp_data(dBus_rsp_data),

        // Interrupts
        .timerInterrupt(1'b0),
        .externalInterrupt(1'b0),
        .softwareInterrupt(1'b0),

        // Debug
        .debug_bus_cmd_valid(1'b0),
        .debug_bus_cmd_ready(),
        .debug_bus_cmd_payload_wr(1'b0),
        .debug_bus_cmd_payload_address(8'd0),
        .debug_bus_cmd_payload_data(32'd0),
        .debug_bus_rsp_data(),
        .debug_resetOut(),
        .debugReset(1'b0)
    );

    // ===============================================
    // 4. Instruction Memory (ROM, 64 KB)
    // ===============================================
    reg [31:0] instr_mem [0:511];
    reg [31:0] data_mem [0:(300 * 300)/2 - 1];
    initial $readmemh("/home/quang-tran/project/VexRiscv/firmware.hex", instr_mem);
    reg [31:0] instr_data_reg;
    reg        instr_valid_reg;

    always @(posedge clk_125MHz) begin
        if (~resetn) begin
            instr_valid_reg <= 1'b0;
        end else if (iBus_cmd_valid && iBus_cmd_ready) begin
            // giả sử firmware được link tại 0x80000000
            instr_data_reg  <= instr_mem[(iBus_cmd_payload_pc - 32'h8000_0000) >> 2];
            instr_valid_reg <= 1'b1;
        end else begin
            instr_valid_reg <= 1'b0;
        end
    end

    assign iBus_cmd_ready         = 1'b1;
    assign iBus_rsp_valid         = instr_valid_reg;
    assign iBus_rsp_payload_inst  = instr_data_reg;
    assign iBus_rsp_payload_error = 1'b0;

//     ===============================================
//     5. Data Memory (RAM 64 KB)
//     ===============================================
    
    reg [31:0] dBus_rdata_reg;

    assign dBus_cmd_ready = 1'b1;
    assign dBus_rsp_ready = 1'b1; // CPU coi như nhận phản hồi ngay
    assign dBus_rsp_error = 1'b0;
    assign dBus_rsp_data  = dBus_rdata_reg;
    
    always @(posedge clk_125MHz) begin
        if (dBus_cmd_valid) begin
            if (dBus_cmd_payload_wr) begin
                if (dBus_cmd_payload_mask[0]) data_mem[dBus_cmd_payload_address[17:2] ][7:0]   <= dBus_cmd_payload_data[7:0];
                if (dBus_cmd_payload_mask[1]) data_mem[dBus_cmd_payload_address[17:2] ][15:8]  <= dBus_cmd_payload_data[15:8];
                if (dBus_cmd_payload_mask[2]) data_mem[dBus_cmd_payload_address[17:2] ][23:16] <= dBus_cmd_payload_data[23:16];
                if (dBus_cmd_payload_mask[3]) data_mem[dBus_cmd_payload_address[17:2] ][31:24] <= dBus_cmd_payload_data[31:24];
            end else begin
                dBus_rdata_reg <= data_mem[dBus_cmd_payload_address[17:2]];
            end
        end
    end

    // ===============================================
    // 6. HDMI framebuffer + output
    // ===============================================
    
    wire [15:0] fb_rd_addr;
    wire [15:0] fb_rd_data;
    
    reg [31:0] word_data_reg;
    
    always @(posedge clk_125MHz) begin
        word_data_reg <= data_mem[fb_rd_addr[15:1]];
    end
    
    assign fb_rd_data = fb_rd_addr[0] ? word_data_reg[31:16] : word_data_reg[15:0];

    HDMI_Encode hdmi_en (
         .pixel(fb_rd_data),
	     .clk(sys_clk),  // 125MHz
	     .TMDSp(hdmi_tx_p),
	     .TMDSn(hdmi_tx_n),
	     .TMDSp_clock(hdmi_clk_p),
	     .TMDSn_clock(hdmi_clk_n),
	     .fb_addr(fb_rd_addr)
    );


endmodule