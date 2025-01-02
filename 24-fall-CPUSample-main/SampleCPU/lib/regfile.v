`include "defines.vh"
module regfile(
    input wire clk,
    input wire [4:0] raddr1,
    output wire [31:0] rdata1,
    input wire [4:0] raddr2,
    output wire [31:0] rdata2,
    
    input wire [37:0] ex_to_id_bus,
    input wire [37:0] mem_to_id_bus,
    input wire [37:0] wb_to_id_bus,


    input wire we,
    input wire [4:0] waddr,
    input wire [31:0] wdata
);
    reg [31:0] reg_array [31:0];
    // write
    always @ (posedge clk) begin
        if (we && waddr!=5'b0) begin
            reg_array[waddr] <= wdata;
        end
    end



    wire [31:0] ex_result;
    wire ex_rf_we;
    wire [4:0] ex_rf_waddr;
    assign {
        ex_rf_we,          // 37
        ex_rf_waddr,       // 36:32
        ex_result       // 31:0
    } = ex_to_id_bus;
    wire [31:0] mem_rf_wdata;
    wire mem_rf_we;
    wire [4:0] mem_rf_waddr;
    wire [31:0] bbb;
    assign {
        mem_rf_we,      // 37
        mem_rf_waddr,   // 36:32
        mem_rf_wdata    // 31:0
    } = mem_to_id_bus;
//        wb_to_id
    wire [31:0] wb1_rf_wdata;
    wire wb1_rf_we;
    wire [4:0] wb1_rf_waddr;
    assign {
        wb1_rf_we,      // 37
        wb1_rf_waddr,   // 36:32
        wb1_rf_wdata    // 31:0
    } = wb_to_id_bus;





    // read out 1
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : 
    ((raddr1 == ex_rf_waddr)&& ex_rf_we) ? ex_result : 
    ((raddr1 == mem_rf_waddr)&& mem_rf_we) ? mem_rf_wdata : 
    ((raddr1 == wb1_rf_waddr)&& wb1_rf_we) ? wb1_rf_wdata :
    reg_array[raddr1];

    // read out2
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : 
    ((raddr2 == ex_rf_waddr)&& ex_rf_we) ? ex_result :
    ((raddr2 == mem_rf_waddr)&& mem_rf_we) ? mem_rf_wdata : 
    ((raddr2 == wb1_rf_waddr)&& wb1_rf_we) ? wb1_rf_wdata : 
    reg_array[raddr2];

endmodule