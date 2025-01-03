`include "lib/defines.vh"
//ID段，Instruction Decode，负责对指令进行译码，并生成控制信号和数据信号
//从IF阶段接收指令数据，从WB阶段接收写回数据，并将译码结果传递到EX阶段
//还负责分支判断和流水线控制，生成分支信号和流水线暂停请求信号
module ID(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,// 流水线暂停信号
    
    output wire stallreq,// 流水线暂停请求信号

    //添加四个数据通路信号
    output wire stallreq_for_id,     // 对id的停止请求
    input wire [37:0] ex_to_id_bus,
    input wire [37:0] mem_to_id_bus,
    input wire [37:0] wb_to_id_bus,


    // 高低位寄存器相关指令
    input wire [65:0] ex_to_id_2,
    input wire[65:0] mem_to_id_2, 
    input wire[65:0] wb_to_id_2, 


    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,// 从IF阶段传递到ID阶段的总线

    input wire [31:0] inst_sram_rdata, // 从指令SRAM读取的指令数据, 从 inst_sram_rdata 中读取指令，并对指令进行译码，生成控制信号和数据信号。

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus, // 从WB阶段传递到rf：register file寄存器文件的总线

    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus, // 从ID阶段传递到EX阶段的总线

    output wire [`BR_WD-1:0] br_bus, // 分支信号总线,根据指令的类型和条件，判断是否需要分支，并生成分支信号 br_bus

    //定义stallreq_for_id需要用的
    input wire inst_is_load,

    // WB 写回 id 的高低位信号(寄存器)
    input wire [65:0] wb_to_id_wf,


    //定义inst_stall需要用的
    input wire ready_ex_to_id
);
    // _r代表他是寄存器，用于存储 if_to_id_bus 的值，以便在 ID 阶段使用
    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;
    //这是当前需要译码的指令
    wire [31:0] inst;
    //这是当前指令的程序计数器（PC）值，从 if_to_id_bus 中提取，表示当前指令的地址
    wire [31:0] id_pc;
    //这是指令 SRAM 的使能信号（Chip Enable），从 if_to_id_bus 中提取，用于控制指令 SRAM 是否工作
    wire ce;

    //写回阶段（WB）对寄存器文件的写使能信号，如果为高电平（1），表示需要将数据写入寄存器文件
    wire wb_rf_we;
    //写回阶段（WB）对寄存器文件的写地址，指定了需要写入的寄存器地址（通常是 32 个寄存器中的一个）
    wire [4:0] wb_rf_waddr;
    //写回阶段（WB）对寄存器文件的写数据，它是要写入寄存器文件的数据
    wire [31:0] wb_rf_wdata;

    //新添加的stall寄存器
    reg [31:0] inst_stall;
    reg inst_stall_en;
    //新添加的stall线网
    wire [31:0]inst_stall1;
    wire inst_stall_en1;
    





    //在时钟的上升沿更新 if_to_id_bus_r 寄存器的值
    always @ (posedge clk) begin
        //rst 是复位信号，通常用于初始化或重置电路的状态，如果 rst 为高电平（1），表示系统处于复位状态
        if (rst) begin
            //if_to_id_bus_r 被初始化为全 0
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        // else if (flush) begin
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        //`Stop 和 `NoStop 是宏定义，分别表示暂停和继续
        //如果 stall[1] 为暂停（Stop）且 stall[2] 为继续（NoStop），表示流水线需要暂停。
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            //如果流水线需要暂停，if_to_id_bus_r 被清零
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end

        //如果 stall[1] 为继续（NoStop），表示流水线不需要暂停
        else if (stall[1]==`NoStop) begin
            //如果流水线不需要暂停，if_to_id_bus_r 更新为 if_to_id_bus 的值
            if_to_id_bus_r <= if_to_id_bus;
        end
    end
    
    //新添加的时序逻辑
    always @ (posedge clk) begin
        inst_stall_en<=1'b0;
        inst_stall <=32'b0;
        if(stall[1] == 1'b1 & ready_ex_to_id ==1'b0)begin
        inst_stall <= inst;
        inst_stall_en<=1'b1;
        end
    end
    //新定义
    assign inst_stall1 = inst_stall;
    assign inst_stall_en1 = inst_stall_en ;

    //对inst的新定义
    assign inst = inst_stall_en1 ? inst_stall1  :inst_sram_rdata;
    //对inst的原来定义
    //assign inst = inst_sram_rdata;
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;
    assign {
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    wire [5:0] opcode;//操作码
    //reg source 源寄存器 1 的地址，reg target 源寄存器 2 的地址，
    //reg destination 目标寄存器的地址，Shift Amount 移位指令中的移位量
    wire [4:0] rs,rt,rd,sa;
    wire [5:0] func;//功能码（6 位），用于进一步区分指令的操作
    wire [15:0] imm;//立即数（16 位），用于立即数指令
    wire [25:0] instr_index;//跳转指令中的跳转地址（26 位）
    wire [19:0] code;//指令中的特殊字段（20 位），用于某些指令
    wire [4:0] base;//基址寄存器地址（5 位），用于基址寻址指令
    wire [15:0] offset;//偏移量（16 位），用于基址寻址或分支指令
    wire [2:0] sel;//选择信号（3 位），用于某些指令的特殊操作

    wire [63:0] op_d, func_d;//操作码和功能码的解码结果（64 位），用于生成控制信号
    //寄存器值和移位量的解码结果（32 位），用于后续操作
    wire [31:0] rs_d, rt_d, rd_d, sa_d;

    wire [2:0] sel_alu_src1;//ALU 操作数 1 的选择信号（3 位）
    wire [3:0] sel_alu_src2;//ALU 操作数 2 的选择信号（4 位）
    //ALU 操作的控制信号（12 位），用于指定 ALU 的操作类型（如加、减、与、或等）
    wire [11:0] alu_op;

    wire data_ram_en;//数据存储器的使能信号（1 位）
    wire [3:0] data_ram_wen;//数据存储器的写使能信号（4 位），用于控制字节写入

    wire [3:0] data_ram_read;
    
    wire rf_we;//寄存器文件的写使能信号（1 位）
    wire [4:0] rf_waddr;//寄存器文件的写地址（5 位）
    wire sel_rf_res;//寄存器文件写数据的选择信号（1 位）
    wire [2:0] sel_rf_dst;//寄存器文件写地址的选择信号（3 位）

    wire [31:0] rdata1, rdata2;//读取的数据，分别对应 rs 和 rt 的值

    // write
    wire w_hi_we;//高位寄存器的写使能信号（1 位）
    wire w_lo_we;//低位寄存器的写使能信号（1 位）
    wire [31:0]hi_i;//写入寄存器数据
    wire [31:0]lo_i;
    // read
    wire r_hi_we;//高位寄存器的读使能信号（1 位）
    wire r_lo_we;//低位寄存器的读使能信号（1 位）
    wire [31:0]hi_o;//读取寄存器数据 
    wire [31:0]lo_o; 


    wire [1:0] lo_hi_r;
    wire [1:0] lo_hi_w;


    wire inst_lsa;//对高低位寄存器加载或存储的控制

    //打包寄存器写能信号yu数据
    assign 
    {
        w_hi_we,
        w_lo_we,
        hi_i,
        lo_i
    } = wb_to_id_wf;

    //寄存器文件模块实例化，
    //相当于一个独立于其他模块的数据备份模块，方便对信号和数据进行传递
regfile u_regfile(
    // ？？？？？？？？？？？？？？

    .inst   (inst   ),  





    .clk    (clk    ),            // 时钟信号，控制寄存器文件的同步操作
    .raddr1 (rs ),                // 将源寄存器 1 地址（rs）连接到寄存器文件模块的 raddr1 端口，用于读取第一个操作数
    .rdata1 (rdata1 ),            // 寄存器文件模块将第一个寄存器的值通过 rdata1 传输到外部
    .raddr2 (rt ),                // 将源寄存器 2 地址（rt）连接到寄存器文件模块的 raddr2 端口，用于读取第二个操作数
    .rdata2 (rdata2 ),            // 寄存器文件模块将第二个寄存器的值通过 rdata2 传输到外部
    .we     (wb_rf_we     ),      // 写使能信号，控制是否写数据到寄存器文件
    .waddr  (wb_rf_waddr  ),      // 写入寄存器的地址，指定写入数据的寄存器的地址
    .wdata  (wb_rf_wdata  ),      // 要写入的数据，指定要写入寄存器的数据
    // 添加三个数据通路信号
    .ex_to_id_bus(ex_to_id_bus),  // 来自执行阶段（EX）的数据到 ID 阶段的信号
    .mem_to_id_bus(mem_to_id_bus),// 来自内存阶段（MEM）的数据到 ID 阶段的信号
    .wb_to_id_bus(wb_to_id_bus),  // 来自写回阶段（WB）的数据到 ID 阶段的信号
    // 添加高低位寄存器相关
    .ex_to_id_2(ex_to_id_2),      // 执行阶段（EX）到 ID 阶段的高低位寄存器信号
    .mem_to_id_2(mem_to_id_2),    // 内存阶段（MEM）到 ID 阶段的高低位寄存器信号
    .wb_to_id_2(wb_to_id_2),      // 写回阶段（WB）到 ID 阶段的高低位寄存器信号
    // 高低位寄存器写操作
    .w_hi_we(w_hi_we),            // 高位写使能信号
    .w_lo_we(w_lo_we),            // 低位写使能信号
    .hi_i(hi_i),                  // 写入到高位寄存器的数据
    .lo_i(lo_i),                  // 写入到低位寄存器的数据
    // 高低位寄存器读操作
    .r_hi_we(lo_hi_r[0]),         // 从高位寄存器读取的写使能信号（通过 lo_hi_r[0] 控制是否从 lo 寄存器读取）
    .r_lo_we(lo_hi_r[1]),         // 从低位寄存器读取的写使能信号（通过 lo_hi_r[1] 控制是否从 hi 寄存器读取）
    .hi_o(hi_o),                  // 从高位寄存器输出的数据
    .lo_o(lo_o),                  // 从低位寄存器输出的数据
    // 是否加载高位或低位寄存器的数据
    .inst_lsa(inst_lsa)           // 用于指示当前指令是否需要操作高低位寄存器的标志
);


    //这些 assign 语句从指令 inst 中提取不同的字段，用于后续的译码和控制信号生成
    assign opcode = inst[31:26];
    assign rs = inst[25:21];
    assign rt = inst[20:16];
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];
    assign sel = inst[2:0];

    //新定义的stallreq_for_id
    assign stallreq_for_id = (inst_is_load == 1'b1 && (rs == ex_to_id_bus[36:32] || rt == ex_to_id_bus[36:32] ));



    //这些信号用于判断指令的类型
    //这些信号通常通过 指令译码 生成  assign inst_ori = (opcode == 6'b001101);
    wire inst_ori, inst_lui, inst_addiu, inst_beq, inst_subu, inst_jr, inst_jal, inst_addu, inst_bne, inst_sll, inst_or,
         inst_lw, inst_sw, inst_xor ,inst_sltu, inst_slt, inst_slti, inst_sltiu, inst_j, inst_add, inst_addi ,inst_sub,
         inst_and , inst_andi, inst_nor, inst_xori, inst_sllv, inst_sra, inst_bgez, inst_bltz, inst_bgtz, inst_blez,
         inst_bgezal,inst_bltzal, inst_jalr, inst_mflo, inst_mfhi, inst_mthi, inst_mtlo, inst_div, inst_divi, inst_mult,
         inst_multu, inst_lb, inst_lbu, inst_lh, inst_lhu, inst_sb, inst_sh;
    //这些信号用于判断 ALU 的操作类型
    //这些信号通常通过 指令译码 和 功能码（func） 生成  assign op_add = (func == 6'b100000); 
    wire op_add, op_sub, op_slt, op_sltu;
    wire op_and, op_nor, op_or, op_xor;
    wire op_sll, op_srl, op_sra, op_lui;

    //解码器模块的作用是将输入的二进制编码转换为独热码，
    //将 6 位二进制opcode输入转换为 64 位独热码输出
    decoder_6_64 u0_decoder_6_64(
    	.in  (opcode  ),
        .out (op_d )
    );
    //将 6 位二进制func输入转换为 64 位独热码输出
    decoder_6_64 u1_decoder_6_64(
    	.in  (func  ),
        .out (func_d )
    );
    //将 5 位二进制rs输入转换为 32 位独热码输出
    decoder_5_32 u0_decoder_5_32(
    	.in  (rs  ),
        .out (rs_d )
    );
    //将 5 位二进制rt输入转换为 32 位独热码输出
    decoder_5_32 u1_decoder_5_32(
    	.in  (rt  ),
        .out (rt_d )
    );

    //判断当前指令的操作码是哪一种指令，是为1，不是为0
    //ori对应操作码为001101，以此类推
    assign inst_ori     = op_d[6'b00_1101];
    assign inst_lui     = op_d[6'b00_1111];
    assign inst_addiu   = op_d[6'b00_1001];
    assign inst_beq     = op_d[6'b00_0100];
    assign inst_subu    = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0011];
    assign inst_jr      = op_d[6'b00_0000] & (inst[20:11]==10'b0000000000) & (sa==5'b0_0000) & func_d[6'b00_1000];
    assign inst_jal     = op_d[6'b00_0011];
    assign inst_addu    = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0001];
    assign inst_sll     = op_d[6'b00_0000] & rs_d[5'b0_0000] & func_d[6'b00_0000];
    assign inst_bne     = op_d[6'b00_0101];
    assign inst_or      = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0101];
    
    assign inst_lw      = op_d[6'b10_0011];
    assign inst_sw      = op_d[6'b10_1011];
    assign inst_xor     = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0110];
    assign inst_sltu    = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_1011];
    assign inst_slt     = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_1010];
    assign inst_slti    = op_d[6'b00_1010];
    assign inst_sltiu   = op_d[6'b00_1011];
    assign inst_j       = op_d[6'b00_0010];
    assign inst_add     = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0000];
    assign inst_addi    = op_d[6'b00_1000];
    assign inst_sub     = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0010];     
    assign inst_and     = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0100];
    assign inst_andi    = op_d[6'b00_1100];
    assign inst_nor     = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b10_0111];
    assign inst_xori    = op_d[6'b00_1110];
    assign inst_sllv    = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b00_0100];
    assign inst_sra     = op_d[6'b00_0000] & (rs==5'b0_0000) & func_d[6'b00_0011];
    assign inst_srav    = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b00_0111];   
    assign inst_srl     = op_d[6'b00_0000] & (rs==5'b0_0000) & func_d[6'b00_0010];
    assign inst_srlv    = op_d[6'b00_0000] & (sa==5'b0_0000) & func_d[6'b00_0110];  
    assign inst_bgez    = op_d[6'b00_0001] & (rt==5'b0_0001);
    assign inst_bltz    = op_d[6'b00_0001] & (rt==5'b0_0000);
    assign inst_bgtz    = op_d[6'b00_0111] & (rt==5'b0_0000);
    assign inst_blez    = op_d[6'b00_0110] & (rt==5'b0_0000);
    assign inst_bgezal  = op_d[6'b00_0001] & (rt==5'b1_0001);
    assign inst_bltzal  = op_d[6'b00_0001] & (rt==5'b1_0000);
    assign inst_jalr    = op_d[6'b00_0000] & (rt==5'b0_0000) & (sa==5'b0_0000) & func_d[6'b00_1001];
    
    assign inst_mflo    = op_d[6'b00_0000] & (inst[25:16]==10'b0000000000) & (sa==5'b0_0000) & func_d[6'b01_0010];
    assign inst_mfhi    = op_d[6'b00_0000] & (inst[25:16]==10'b0000000000) & (sa==5'b0_0000) & func_d[6'b01_0000];
    assign inst_mthi    = op_d[6'b00_0000] & (inst[20:6]==10'b000000000000000)  & func_d[6'b01_0001];
    assign inst_mtlo    = op_d[6'b00_0000] & (inst[20:6]==10'b000000000000000)  & func_d[6'b01_0011];
    assign inst_div     = op_d[6'b00_0000] & (inst[15:6]==10'b0000000000) & func_d[6'b01_1010];
    assign inst_divu    = op_d[6'b00_0000] & (inst[15:6]==10'b0000000000) & func_d[6'b01_1011];
    assign inst_mult    = op_d[6'b00_0000] & (inst[15:6]==10'b0000000000) & func_d[6'b01_1000];
    assign inst_multu   = op_d[6'b00_0000] & (inst[15:6]==10'b0000000000) & func_d[6'b01_1001];
    
    assign inst_lb      = op_d[6'b10_0000];
    assign inst_lbu     = op_d[6'b10_0100];
    assign inst_lh      = op_d[6'b10_0001];
    assign inst_lhu     = op_d[6'b10_0101];      
    assign inst_sb      = op_d[6'b10_1000];
    assign inst_sh      = op_d[6'b10_1001];
    
    assign inst_lsa     = op_d[6'b01_1100] & inst[10:8]==3'b111 & inst[5:0]==6'b11_0111;

    //选择 ALU（算术逻辑单元）的操作数来源
    //sel_alu_src1用于选择 ALU 的第一个操作数（reg1）的来源，
    //sel_alu_src1 是一个 3 位信号，每一位表示一种选择方式

    // rs to reg1
    //如果为 1，表示 ALU 的第一个操作数来自 rs（源寄存器 1）
    //当指令是 OR 立即数指令（inst_ori）或无符号加立即数指令（inst_addiu）时，sel_alu_src1[0] 为 1
    assign sel_alu_src1[0] = inst_ori | inst_addiu | inst_subu | inst_addu | inst_or | inst_lw | inst_sw | inst_xor | inst_sltu | inst_slt
                                | inst_slti | inst_sltiu | inst_add | inst_addi | inst_sub | inst_and | inst_andi | inst_nor | inst_xori
                                | inst_sllv | inst_srav | inst_srlv | inst_mthi | inst_mtlo | inst_div | inst_divu | inst_mult | inst_multu
                                | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_sb | inst_sh | inst_lsa;

    // pc to reg1
    //如果为 1，表示 ALU 的第一个操作数来自程序计数器（pc）
    assign sel_alu_src1[1] = inst_jal | inst_bgezal |inst_bltzal | inst_jalr;

    // sa_zero_extend to reg1
    //如果为 1，表示 ALU 的第一个操作数来自 sa（移位量）的零扩展值
    assign sel_alu_src1[2] = inst_sll | inst_sra | inst_srl;

    //sel_alu_src2用于选择 ALU 的第二个操作数（reg2）的来源，
    //sel_alu_src2 是一个 4 位信号，每一位表示一种选择方式

    // rt to reg2
    //如果为 1，表示 ALU 的第二个操作数来自 rt（源寄存器 2）
    assign sel_alu_src2[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor | inst_sltu | inst_slt | inst_add | inst_sub | inst_and |
                              inst_nor | inst_sllv | inst_sra | inst_srav | inst_srl | inst_srlv | inst_div | inst_divu | inst_mult | inst_multu | inst_lsa;
    
    // imm_sign_extend to reg2
    //如果为 1，表示 ALU 的第二个操作数来自立即数的符号扩展值
    //当指令是加载高位立即数指令（inst_lui）或无符号加立即数指令（inst_addiu）时，sel_alu_src2[1] 为 1
    assign sel_alu_src2[1] = inst_lui | inst_addiu | inst_lw | inst_sw | inst_slti | inst_sltiu | inst_addi | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_sb | inst_sh;

    // 32'b8 to reg2
    //如果为 1，表示 ALU 的第二个操作数是常数 32'b8,(32 位宽的二进制数，其值为 8)
    assign sel_alu_src2[2] = inst_jal | inst_bgezal | inst_bltzal | inst_jalr;

    // imm_zero_extend to reg2
    //如果为 1，表示 ALU 的第二个操作数来自立即数的零扩展值
    //当指令是 OR 立即数指令（inst_ori）时，sel_alu_src2[3] 为 1
    assign sel_alu_src2[3] = inst_ori | inst_andi | inst_xori;

    // 低位寄存器到目标
    assign lo_hi_r[0] = inst_mflo;

    // 高位寄存器到目标
    assign lo_hi_r[1] = inst_mfhi;
   

    // 生成 ALU（算术逻辑单元）的操作控制信号 alu_op
    assign op_add = inst_addiu | inst_jal | inst_addu | inst_lw | inst_sw | inst_add | inst_addi | inst_bgezal | inst_bltzal
         | inst_jalr | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_sb | inst_sh | inst_lsa;
    assign op_sub = inst_subu | inst_sub;
    assign op_slt = inst_slt | inst_slti;
    assign op_sltu = inst_sltu | inst_sltiu;
    assign op_and = inst_and | inst_andi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xor | inst_xori;
    assign op_sll = inst_sll | inst_sllv;
    assign op_srl = inst_srl | inst_srlv;
    assign op_sra = inst_sra | inst_srav ;
    assign op_lui = inst_lui;
    //根据指令类型生成 ALU 的具体操作类型（如加法、减法、逻辑与、逻辑或等），
    //并将这些操作类型组合成一个 12 位的控制信号 alu_op
    //alu_op：一个 12 位的控制信号，用于指定 ALU 的具体操作类型
    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};


    //生成数据存储器和寄存器文件的控制信号
    // load and store enable
    //这里固定为 0，表示当前指令不涉及数据存储器的读写操作
    assign data_ram_en = inst_lw | inst_sw | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_sb | inst_sh;

    // write enable
    //这里固定为 0，表示当前指令不涉及数据存储器的读写操作
    assign data_ram_wen = inst_sw ? 4'b1111 : 4'b0000;

    assign data_ram_read    =  inst_lw  ? 4'b1111 :
                               inst_lb  ? 4'b0001 :
                               inst_lbu ? 4'b0010 :
                               inst_lh  ? 4'b0011 :
                               inst_lhu ? 4'b0100 :
                               inst_sb  ? 4'b0101 :
                               inst_sh  ? 4'b0111 :
                               4'b0000;
    


    // regfile store enable
    //如果当前指令是 OR 立即数指令（inst_ori）、加载高位立即数指令（inst_lui）或无符号加立即数指令（inst_addiu），
    //则 rf_we 为 1，表示需要向寄存器文件写入数据。
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu | inst_jal |inst_addu | inst_sll | inst_or | inst_xor | inst_lw | inst_sltu
      | inst_slt | inst_slti | inst_sltiu | inst_add | inst_addi | inst_sub | inst_and | inst_andi | inst_nor | inst_sllv | inst_xori | inst_sra
      | inst_srav | inst_srl | inst_srlv | inst_bgezal | inst_bltzal | inst_jalr  | inst_mfhi | inst_mflo | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_lsa;


    //选择寄存器文件的写地址（rf_waddr）和写数据来源（sel_rf_res）
    //它通过一系列控制信号（sel_rf_dst）决定将结果写入哪个寄存器，
    //并通过 sel_rf_res 选择写数据的来源
    //sel_rf_dst ：一个 3 位信号，用于选择寄存器文件的写地址来源

    //写地址选择信号
    // store in [rd]
    //sel_rf_dst[0]：选择 rd 作为写地址
    assign sel_rf_dst[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor | inst_sltu | inst_slt | inst_add | inst_sub | inst_and | inst_nor
                             | inst_sllv | inst_sra | inst_srav | inst_srl | inst_srlv | inst_jalr | inst_mflo | inst_mfhi | inst_lsa;
    // store in [rt]
    //sel_rf_dst[1]：选择 rt 作为写地址
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu | inst_lw | inst_slti | inst_sltiu | inst_addi | inst_andi | inst_xori | inst_lb | inst_lbu | inst_lh | inst_lhu;
    // store in [31]
    //sel_rf_dst[2]：选择 31 号寄存器（通常是返回地址寄存器）作为写地址
    assign sel_rf_dst[2] = inst_jal | inst_bgezal | inst_bltzal ;

    //low和high的写入信号
    assign lo_hi_w[0] = inst_mtlo;
    assign lo_hi_w[1] = inst_mthi;


    //写地址生成
    // sel for regfile address
    //rf_waddr ：寄存器文件的写地址，表示结果将写入哪个寄存器
    //根据 sel_rf_dst 的值选择写地址：
    //如果 sel_rf_dst[0] 为 1，则 rf_waddr = rd。
    //如果 sel_rf_dst[1] 为 1，则 rf_waddr = rt。
    //如果 sel_rf_dst[2] 为 1，则 rf_waddr = 5'd31
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    //写数据来源选择
    // 0 from alu_res ; 1 from ld_res
    //sel_rf_res：选择寄存器文件写数据的来源
    //如果为 0，表示写数据来自 ALU 的结果（alu_res）。
    //如果为 1，表示写数据来自加载指令的结果（ld_res）。
    //这里固定为 0，表示写数据来自 ALU 的结果。
    assign sel_rf_res = (inst_lw | inst_lb | inst_lbu) ? 1'b1 : 1'b0; 

    //将译码阶段（ID）生成的各种信号打包成一个总线信号 id_to_ex_bus,将其传递到执行阶段（EX）
    assign id_to_ex_bus = {
        id_pc,          // 158:127//程序计数器
        inst,           // 126:95//指令
        alu_op,         // 94:83//ALU 操作控制信号
        sel_alu_src1,   // 82:80//操作数选择信号
        sel_alu_src2,   // 79:76//操作数选择信号
        data_ram_en,    // 75//数据存储器控制信号
        data_ram_wen,   // 74:71//数据存储器控制信号
        rf_we,          // 70//寄存器文件控制信号
        rf_waddr,       // 69:65//寄存器数据
        sel_rf_res,     // 64//寄存器文件写数据来源选择
        //问题：为什么 rdata1 是 rs 的值，而不是 wdata 的结果？
        //答：在regfile中，读写操作是独立的，reg_array[rdata1]和
        //reg_array[wdata1]装的是不同的内容，一个是指令中rs的值，一个是wb计算结果的值
        rdata1,         // 63:32//从寄存器文件读取的第一个数据,传的应该是指令中的rs
        rdata2,          // 31:0//从寄存器文件读取的第二个数据,传的应该是指令中的rt

        // 高低位寄存器读写
        lo_hi_r,
        lo_hi_w,
        lo_o,
        hi_o,

        data_ram_read
    };


    wire br_e;//分支使能信号，表示是否满足分支条件。
    wire [31:0] br_addr;//分支目标地址，表示分支指令的目标地址
    wire rs_eq_rt;//表示 rs 和 rt 的值是否相等
    wire rs_ge_z;//表示 rs 的值是否大于或等于零（未使用）
    wire rs_gt_z;//表示 rs 的值是否大于零（未使用）
    wire rs_le_z;//表示 rs 的值是否小于或等于零（未使用）
    wire rs_lt_z;//表示 rs 的值是否小于零（未使用）
    wire [31:0] pc_plus_4;//表示当前指令地址加 4，即下一条指令的地址

    wire re_bne_rt;

    assign pc_plus_4 = id_pc + 32'h4;

    assign rs_eq_rt = (rdata1 == rdata2);
    assign re_bne_rt = (rdata1 != rdata2);
    assign re_bgez_rt = (rdata1[31] == 1'b0);
    assign re_bltz_rt = (rdata1[31] == 1'b1);     
    assign re_blez_rt = (rdata1[31] == 1'b1 || rdata1 == 32'b0);
    assign re_bgtz_rt = (rdata1[31] == 1'b0 && rdata1 != 32'b0);

    //br_e 为 1 表示当前指令是分支相等指令且 rs 和 rt 的值相等，满足分支条件
    assign br_e = (inst_beq && rs_eq_rt) | inst_jr | inst_jal | (inst_bne && re_bne_rt) | inst_j |(inst_bgez && re_bgez_rt)
                     | (inst_bltz && re_bltz_rt) |(inst_bgtz && re_bgtz_rt) | (inst_blez && re_blez_rt) | (inst_bgezal && re_bgez_rt)
                     | (inst_bltzal && re_bltz_rt) | inst_jalr;
   
    //计算分支目标地址
    //如果寄存器 rs 的值等于寄存器 rt 的值则转移，否则顺序执行。
    //beq指令转移地址为：pc+4+（16位的offset拓展为32位，并左移两位）
    assign br_addr = inst_beq ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) : 
    inst_jr ? (rdata1) :
    inst_jal ? ({pc_plus_4[31:28],inst[25:0],2'b0}):
    inst_bne ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :
    inst_bgez ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :   
    inst_bgtz ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :  
    inst_bltz ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :   
    inst_blez ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :
    inst_bgezal ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :
    inst_bltzal ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) :  
    inst_j   ?  ({pc_plus_4[31:28],inst[25:0],2'b0}):
    inst_jalr ? (rdata1) :
    32'b0;

    assign br_bus = {
        br_e,
        br_addr
    };
    


endmodule