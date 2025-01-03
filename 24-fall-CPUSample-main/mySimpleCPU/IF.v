

`include "lib/defines.vh"
module IF(
    input wire clk, // 时钟信号
    input wire rst, // 复位信号
    //在defines.vh定义的宏StallBus=6
    input wire [`StallBus-1:0] stall, // 流水线暂停信号

    // input wire flush,
    // input wire [31:0] new_pc,

    input wire [`BR_WD-1:0] br_bus,  // 分支信号总线

    output wire [`IF_TO_ID_WD-1:0] if_to_id_bus, // 输出到ID阶段的信号总线
//SRAM：静态随机存取存储器（相当于cpu缓存），对应的DRAM是动态随机存取存储器（电脑内存条）
// inst_sram_en 表示 "Instruction SRAM Enable"，即指令存储器的使能信号
// 当使能信号为高电平（1）时，SRAM处于工作状态，可以响应读写请求
// 当使能信号为低电平（0）时，SRAM处于关闭状态，不响应任何读写请求
    output wire inst_sram_en,   // 指令SRAM使能信号
    output wire [3:0] inst_sram_wen,   // 指令SRAM写使能信号
    output wire [31:0] inst_sram_addr,  // 指令SRAM地址
    output wire [31:0] inst_sram_wdata // 指令SRAM写数据
);
    reg [31:0] pc_reg;   // 程序计数器
    reg ce_reg;   // 指令SRAM使能寄存器
    wire [31:0] next_pc;  // 下一条指令地址
    wire br_e;  // 分支是否有效
    wire [31:0] br_addr;  // 分支目标地址

// 将输入的 br_bus 信号解码为 br_e 和 br_addr
// br_e 表示分支是否有效
// br_addr 表示分支目标地址
    assign {
        br_e,
        br_addr
    } = br_bus;

// 程序计数器更新逻辑
// 在时钟上升沿触发
// 如果复位信号 rst 为高，程序计数器 pc_reg 被初始化为 32'hbfbf_fffc
// 如果流水线没有暂停（stall[0] == NoStop），程序计数器更新为 next_pc`
    always @ (posedge clk) begin
        // 如果 rst 为高电平（1），表示系统处于复位状态
        // rst不经常等于1，大部分时间都是不复位的
        if (rst) begin
            pc_reg <= 32'hbfbf_fffc;
        end
        // 如果 stall[0] 等于 NoStop，表示流水线没有暂停，程序计数器可以正常更新
        else if (stall[0]==`NoStop) begin
            // 程序计数器 pc_reg 更新为 next_pc 的值
            //<=是非阻塞赋值，用于在时序逻辑中赋值
            pc_reg <= next_pc;
        end
    end

// 指令SRAM使能信号更新逻辑
// 在时钟上升沿触发
// 如果复位信号 rst 为高，指令SRAM使能信号 ce_reg 关闭
// 如果流水线没有暂停（stall[0] == NoStop`），指令SRAM使能信号打开
    always @ (posedge clk) begin
        if (rst) begin
            // 此时ce_reg赋为0，表示指令存储器不能读写
            ce_reg <= 1'b0;
        end
        else if (stall[0]==`NoStop) begin
            // 此时ce_reg赋为1，表示指令存储器现在可以读写
            ce_reg <= 1'b1;
        end
    end

// 计算下一条指令地址
// 如果分支有效（br_e 为高），下一条指令地址为分支目标地址 br_addr
// 否则，下一条指令地址为当前地址 pc_reg 加 4（因为指令是 32 位对齐的）
    assign next_pc = br_e ? br_addr 
                   : pc_reg + 32'h4;


// 输出信号赋值 
// inst_sram_en 是指令SRAM的使能信号，直接连接到 ce_reg
// inst_sram_wen 是指令SRAM的写使能信号，始终为 0（表示只读）
// inst_sram_addr 是指令SRAM的地址，直接连接到 pc_reg
// inst_sram_wdata 是写入指令SRAM的数据，始终为 0（表示不写数据）
// if_to_id_bus 是输出到 ID 阶段的信号总线，包含 ce_reg 和 pc_reg
    assign inst_sram_en = ce_reg;
    assign inst_sram_wen = 4'b0;
    assign inst_sram_addr = pc_reg;
    assign inst_sram_wdata = 32'b0;
    assign if_to_id_bus = {
        ce_reg,//当前指令是否可以读
        pc_reg//当前指令的地址
    };

endmodule