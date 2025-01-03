`include "lib/defines.vh"
module EX(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,//流水线暂停信号，用于控制流水线的暂停和继续
    //从译码阶段（ID）传递到执行阶段（EX）的总线信号，包含指令、操作数、控制信号等信息。
    input wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,
    //从执行阶段（EX）传递到访存阶段（MEM）的总线信号，包含执行结果、控制信号等信息。
    output wire [`EX_TO_MEM_WD-1:0] ex_to_mem_bus,

    // 新添加的 ex to id bus的信息，，用于反馈执行阶段的信息（如数据旁路）
    output wire [37:0] ex_to_id_bus,


    //如果指令涉及数据存储器访问（如 Load/Store），
    //生成相应的控制信号（data_sram_en, data_sram_wen, data_sram_addr, data_sram_wdata）
    //数据存储器（SRAM）的使能信号，控制数据存储器是否工作。
    output wire data_sram_en,
    //数据存储器的写使能信号，控制数据存储器的字节写入。
    //4'b1111 表示写入 4 个字节。
    //4'b0001 表示写入 1 个字节。
    output wire [3:0] data_sram_wen,
    //数据存储器的地址信号，指定要访问的内存地址。
    output wire [31:0] data_sram_addr,
    //数据存储器的写数据信号，指定要写入内存的数据。
    output wire [31:0] data_sram_wdata,

    // 新添加的 stallreq_for_ex信号
    output wire stallreq_for_ex,

    //新添加的inst_is_load,输出给id，被stallreq_for_id使用
    output wire inst_is_load,

    //定义inst_stall需要用的
    input wire ready_ex_to_id
);

    reg [`ID_TO_EX_WD-1:0] id_to_ex_bus_r;

    always @ (posedge clk) begin
        if (rst) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        // else if (flush) begin
        //     id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        // end
        else if (stall[2]==`Stop && stall[3]==`NoStop) begin
            id_to_ex_bus_r <= `ID_TO_EX_WD'b0;
        end
        else if (stall[2]==`NoStop) begin
            id_to_ex_bus_r <= id_to_ex_bus;
        end
    end

    wire [31:0] ex_pc, inst;
    wire [11:0] alu_op;
    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire data_ram_en;
    wire [3:0] data_ram_wen;

    wire [3:0] data_ram_read;

    wire rf_we;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [31:0] rf_rdata1, rf_rdata2;
    reg is_in_delayslot;

    assign {
        ex_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        rf_rdata1,         // 63:32
        rf_rdata2,          // 31:0
        data_ram_read
    } = id_to_ex_bus_r;

    wire [31:0] imm_sign_extend, imm_zero_extend, sa_zero_extend;
    assign imm_sign_extend = {{16{inst[15]}},inst[15:0]};
    assign imm_zero_extend = {16'b0, inst[15:0]};
    assign sa_zero_extend = {27'b0,inst[10:6]};

    wire [31:0] alu_src1, alu_src2;
    wire [31:0] alu_result, ex_result;

    assign alu_src1 = sel_alu_src1[1] ? ex_pc :
                      sel_alu_src1[2] ? sa_zero_extend : rf_rdata1;

    assign alu_src2 = sel_alu_src2[1] ? imm_sign_extend :
                      sel_alu_src2[2] ? 32'd8 :
                      sel_alu_src2[3] ? imm_zero_extend : rf_rdata2;
    
    alu u_alu(
    	.alu_control (alu_op ),
        .alu_src1    (alu_src1    ),
        .alu_src2    (alu_src2    ),
        .alu_result  (alu_result  )
    );

    assign ex_result = alu_result;

    assign data_sram_en = data_ram_en ;
    assign data_sram_wen = (data_ram_read==4'b0101 && ex_result[1:0] == 2'b00 )? 4'b0001: 
                            (data_ram_read==4'b0101 && ex_result[1:0] == 2'b01 )? 4'b0010:
                            (data_ram_read==4'b0101 && ex_result[1:0] == 2'b10 )? 4'b0100:
                            (data_ram_read==4'b0101 && ex_result[1:0] == 2'b11 )? 4'b1000:
                            (data_ram_read==4'b0111 && ex_result[1:0] == 2'b00 )? 4'b0011:
                            (data_ram_read==4'b0111 && ex_result[1:0] == 2'b10 )? 4'b1100:
                            data_ram_wen;
    assign data_sram_addr = ex_result ;
    assign data_sram_wdata = data_sram_wen==4'b1111 ? rf_rdata2 : 
                              data_sram_wen==4'b0001 ? {24'b0,rf_rdata2[7:0]} :
                              data_sram_wen==4'b0010 ? {16'b0,rf_rdata2[7:0],8'b0} :
                              data_sram_wen==4'b0100 ? {8'b0,rf_rdata2[7:0],16'b0} :
                              data_sram_wen==4'b1000 ? {rf_rdata2[7:0],24'b0} :
                              data_sram_wen==4'b0011 ? {16'b0,rf_rdata2[15:0]} :
                              data_sram_wen==4'b1100 ? {rf_rdata2[15:0],16'b0} :
                              32'b0;



    assign ex_to_mem_bus = {
        ex_pc,          // 75:44
        data_ram_en,    // 43
        data_ram_wen,   // 42:39
        sel_rf_res,     // 38
        rf_we,          // 37
        rf_waddr,       // 36:32
        ex_result,     // 31:0
        data_ram_read
    };

    // 新添加ex to id bus的信息
    assign ex_to_id_bus = {
        rf_we,          // 37 寄存器文件写能信号
        rf_waddr,       // 36:32 寄存器文件写地址
        ex_result       // 31:0
    };

    //新添加的inst_is_load,输出给id，被stallreq_for_id使用
    assign inst_is_load =  (inst[31:26] == 6'b10_0011) ? 1'b1 :1'b0;


    // MUL part
    wire [63:0] mul_result;
    wire mul_signed; // 有符号乘法标�?

    mul u_mul(
    	.clk        (clk            ),
        .resetn     (~rst           ),
        .mul_signed (mul_signed     ),
        .ina        (      ), // 乘法源操作数1
        .inb        (      ), // 乘法源操作数2
        .result     (mul_result     ) // 乘法结果 64bit
    );

    // DIV part
    wire [63:0] div_result;
    wire inst_div, inst_divu;
    wire div_ready_i;
    reg stallreq_for_div;
    //stallreq_for_ex修改过
    assign stallreq_for_ex = stallreq_for_div;
    //assign stallreq_for_ex = (stallreq_for_div & div_ready_i==1'b0) | (mul_begin & mul_ready_i==1'b0);

    //新添加的ready_ex_to_id为了使用inst_stall
    //assign ready_ex_to_id = div_ready_i | mul_ready_i;
    //mul_ready_i是mul_plus中的，目前未定义
    assign ready_ex_to_id = div_ready_i ;

    reg [31:0] div_opdata1_o;
    reg [31:0] div_opdata2_o;
    reg div_start_o;
    reg signed_div_o;

    div u_div(
    	.rst          (rst          ),
        .clk          (clk          ),
        .signed_div_i (signed_div_o ),
        .opdata1_i    (div_opdata1_o    ),
        .opdata2_i    (div_opdata2_o    ),
        .start_i      (div_start_o      ),
        .annul_i      (1'b0      ),
        .result_o     (div_result     ), // 除法结果 64bit
        .ready_o      (div_ready_i      )
    );

    always @ (*) begin
        if (rst) begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
        end
        else begin
            stallreq_for_div = `NoStop;
            div_opdata1_o = `ZeroWord;
            div_opdata2_o = `ZeroWord;
            div_start_o = `DivStop;
            signed_div_o = 1'b0;
            case ({inst_div,inst_divu})
                2'b10:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b1;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                2'b01:begin
                    if (div_ready_i == `DivResultNotReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStart;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `Stop;
                    end
                    else if (div_ready_i == `DivResultReady) begin
                        div_opdata1_o = rf_rdata1;
                        div_opdata2_o = rf_rdata2;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                    else begin
                        div_opdata1_o = `ZeroWord;
                        div_opdata2_o = `ZeroWord;
                        div_start_o = `DivStop;
                        signed_div_o = 1'b0;
                        stallreq_for_div = `NoStop;
                    end
                end
                default:begin
                end
            endcase
        end
    end

    // mul_result �? div_result 可以直接使用   
    
endmodule