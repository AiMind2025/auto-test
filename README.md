# CV 算子自动化测试工具

## 概述

自动化遍历测试 CV 算子，支持：
- **19 个算子**遍历测试（尺寸笛卡尔积）
- 每 10 个组合提取一次新增日志（分文件存储）
- 每个算子执行完毕后，从容器打包 `/home/paas/ascend/` 和 `/home/paas/var/log/mindxsdk/` 到宿主机
- 自动查找 ccom 容器
- 算子耗时统计 + 汇总报告

---

## 脚本文件

| 文件 | 说明 | 适用场景 |
|------|------|----------|
| `test_all_operators.sh` | 多算子版本（19个算子） | 全量测试 |
| `test_add_operator.sh` | 单算子版本（仅 Add） | 单算子调试 |

---

## 一、多算子脚本（推荐）

### 命令格式

```bash
./test_all_operators.sh <目标IP> <日志ID> [步长] [最大组合数] [容器ID]
```

### 参数说明

| 参数 | 位置 | 默认值 | 说明 |
|------|------|--------|------|
| 目标IP | 1 | **必填** | 测试服务 IP 地址 |
| 日志ID | 2 | **必填** | 容器日志目录 ID |
| 步长 | 3 | `5` | 标准算子递增步长（Resize 固定 40） |
| 最大组合数 | 4 | `0`（全部） | `>0` 时限制每个算子的执行数量 |
| 容器ID | 5 | 自动查找 | 留空自动搜索 ccom 容器 |

### 运行示例

```bash
# 默认步长5，跑全部
./test_all_operators.sh 172.18.0.4 0

# 步长20（减少组合数）
./test_all_operators.sh 172.18.0.4 0 20

# 每个算子只跑100个（快速验证）
./test_all_operators.sh 172.18.0.4 0 5 100

# 指定容器
./test_all_operators.sh 172.18.0.4 0 5 0 2fe5937ad00a
```

### 算子列表

#### 标准算子（17个）

遍历 imageRows(1~721) × imageCols(1~1280)，步长10时每算子 **9,344** 个组合。

| # | 算子名 | 固定参数 |
|---|--------|----------|
| 1 | TestConvertToPerformance | XMatType=16FC1, convertedXMatType=8UC3 |
| 2 | TestRotatePerformance | angle=90 |
| 3 | TestAddPerformance | (无额外) |
| 4 | TestSubtractPerformance | size=3 |
| 5 | TestDividePerformance | scale=0.5 |
| 6 | TestMultiplyPerformance | scale=2.0 |
| 7 | TestCvtColorPerformance | mode=9 |
| 8 | TestWarpAffinePerformance | XMatType=32FC3, width=400, height=400 |
| 9 | TestMaskImgFusionPerformance | (无额外) |
| 10 | TestAddWeightedPerformance | (无额外) |
| 11 | TestMergePerformance | XMatType=8UC1, size=3 |
| 12 | TestSplitPerformance | size=3 |
| 13 | TestBlendImagePerformance | (无额外) |
| 14 | TestBlendCaptionPerformance | captionBgOpacity=0.8 |
| 15 | TestErodePerformance | (无额外) |
| 16 | TestThresholdPerformance | (无额外) |
| 17 | TestMinPerformance | (无额外) |

#### 特殊算子（2个）

4 维遍历（步长固定 40），每算子约 **393,729** 个组合。

| # | 算子名 | 遍历维度 |
|---|--------|----------|
| 18 | TestResizePerformance | inputImage_Rows/Cols × resizedImage_Rows/Cols |
| 19 | TestResizeMaskPerformance | inputImage_Rows/Cols × resizemaskedImage_Rows/Cols |

### 执行流程

```
for 每个算子 (19个):
    ├── 记录开始时间
    ├── 遍历全部尺寸组合，发送 curl 请求
    ├── 每 10 个组合 → 提取日志到独立文件
    ├── 提取剩余日志
    ├── 打包 /home/paas/ascend/ → ./logs_archive/{算子名}/
    └── 打包 /home/paas/var/log/mindxsdk/ → ./logs_archive/{算子名}/

显示汇总报告（每个算子的成功/失败/耗时）
```

---

## 二、单算子脚本

### 命令格式

```bash
./test_add_operator.sh <目标IP> <日志ID> [步长] [最大组合数] [容器ID]
```

### 运行示例

```bash
# 完整测试
./test_add_operator.sh 172.18.0.4 0

# 快速验证
./test_add_operator.sh 172.18.0.4 0 5 100
```

---

## 三、通用说明

### 尺寸组合

| 维度 | 范围 | 说明 |
|------|------|------|
| Rows | 1 ~ 721 | 图像行数 |
| Cols | 1 ~ 1280 | 图像列数 |

组合方式（笛卡尔积）：
```
(1,1), (1,11), (1,21), ..., (1,1280),
(11,1), (11,11), (11,21), ..., (11,1280),
...
(721,1), (721,11), ..., (721,1280)
```

### 步长与组合数

| 步长 | Rows 数量 | Cols 数量 | 每算子组合数 | 预估耗时 |
|------|-----------|-----------|-------------|----------|
| 5 | 145 | 256 | 37,120 | ~10 小时 |
| 10 | 73 | 128 | 9,344 | ~2.5 小时 |
| 20 | 37 | 64 | 2,368 | ~40 分钟 |
| 50 | 15 | 26 | 390 | ~7 分钟 |

> 预估耗时基于每次请求约 1 秒计算

### 输出文件

```
当前目录/
├── test_results/                    # 日志分文件存储
│   ├── ConvertTo/
│   │   ├── batch_001.log            # 第 1-10 个组合
│   │   ├── batch_002.log            # 第 11-20 个组合
│   │   └── ...
│   ├── Rotate/
│   │   ├── batch_001.log
│   │   └── ...
│   ├── Add/
│   └── ...
└── logs_archive/                    # 容器打包文件
    ├── ConvertTo/
    │   ├── ascend_20260703_175000.tar.gz
    │   └── mindxsdk_20260703_175001.tar.gz
    ├── Rotate/
    └── ...
```

### 日志文件内容示例

```
============================================================
测试尺寸: 批次 1, R=1, C=46
============================================================
[2026-07-03 10:35:00] [INFO] CoreMindCCommonServiceDemo ...
[2026-07-03 10:35:01] [DEBUG] Processing image ...
============================================================
```

### 相关路径

| 路径 | 说明 |
|------|------|
| `/opt/container/log/{日志ID}/.../CoreMindCCommonServiceDemo.log` | 监控的日志文件 |
| `/home/paas/ascend/` | 容器内打包目录 1 |
| `/home/paas/var/log/mindxsdk/` | 容器内打包目录 2 |

### 容器自动查找

不指定容器ID时，自动执行：
```bash
docker ps | grep ccom | grep -v pause
```

---

## 四、注意事项

1. **运行环境**：需在能访问目标 IP 和 Docker 的宿主机上运行
2. **Docker 权限**：打包容器目录需要 Docker 执行权限
3. **日志分文件**：每 10 个组合一个文件，避免单文件过大
4. **增量读取**：日志增量提取，不重复
5. **超时设置**：curl 连接超时 10 秒，最大等待 30 秒
6. **Resize 耗时**：Resize 类算子 4 维遍历，组合数多，耗时较长

---

## 五、常见问题

### 如何快速验证？
```bash
# 每个算子只跑10个
./test_all_operators.sh 172.18.0.4 0 10 10
```

### 如何调整步长？
```bash
# 步长设为 50，组合数大幅减少
./test_all_operators.sh 172.18.0.4 0 50
```

### 不想打包容器目录？
```bash
# 不传容器ID，且未自动找到 ccom 容器时自动跳过打包
./test_all_operators.sh 172.18.0.4 0
```

### 如何查看可用容器？
```bash
docker ps | grep ccom
```

---

## 版本历史

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-07-03 | v2.0 | 多算子脚本，支持19个算子遍历 |
| 2026-07-03 | v1.0 | 单算子脚本，支持 Add 算子测试 |
