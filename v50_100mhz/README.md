# JFIX_DUAL_OOO

以 JFIX 原始模块为基础独立实现的双发射乱序核。原始输入保存在 baseline，来源和哈希保留；LOAD1 未修改。

## 当前选定版本：v50_100mhz

单核、双取指/重命名/整数发射、最多双退休；ROB8、PRF40，三个单写 PRF bank 和最后写者选择。固定片上 ROM 同步双查询；PHT128 PC 索引。MUL 独立预选择、原 ROB 槽交付；串行结果快速前递与延后一拍 PRF 写入分离。CRC/Matrix、CSR、异常、中断与外设保留。

| 指标 | 当前结果 |
|---|---:|
| Performance 仿真周期 / retired | 682114 / 820249 |
| CoreMark/MHz（3迭代 A/B 推导） | 4.39809 |
| LUT / FF | 12790 / 5314 |
| 配置频率 | 100 MHz |
| 布局布线估计频率 / setup WNS | 102.1662 MHz / +0.212 ns |
| CoreMark/LUT（100MHz投影） | 0.034387 |

尚未同时达到约一万 LUT、约4.5 CM/MHz 的目标。≥10秒正式上板成绩尚未完成；报告估计频率不等于已验证的实际工作频率。同步时钟域 setup/hold 检查通过；异步按键/UART等端口的无延迟约束告警仍在，不将其当作同步接口时序已验证。

## 阅读与使用

- result.md：完整消融和失败实验；docs/ARCHITECTURE.md：结构及验收边界。
- candidates/v50_100mhz：独立板级工程、RTL、镜像、IP、输入哈希及 PDS 报告。打开其中 Pango_Cpu_board.pds。
- verification：带实验后缀的日志及输入哈希；evidence：源快照和报告。
- source_manifest.json：当前活动源码哈希；baseline_manifest.json：原始输入哈希。

```powershell
$env:JFIX_SIM_SUFFIX='my_run'
python tools/run_sim.py ooo_core_tb
python tools/run_sim.py ooo_fault_tb
python tools/run_sim.py ooo_irq_tb
python tools/run_sim.py ooo_platform_tb
python tools/run_sim.py ooo_platform_irq_tb
python tools/run_sim.py ooo_fetch_fault_tb
python tools/run_sim.py coremark_tb
python tools/run_sim.py coremark_tb MODE=1
$env:JFIX_PDS_STAGE='pds_unique'
python tools/run_pds.py report_timing
python tools/collect_pds_results.py
```

器件 PG2L200H-6/FBB676，PLL100MHz、计数器50MHz、输入27MHz。XSim/PDS位置可由 VIVADO_BIN/PDS_SHELL 覆盖。固定ROM配置不支持动态代码修改，FENCE.I仍非法。
