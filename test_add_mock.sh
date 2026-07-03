#!/bin/bash
# Add 算子测试脚本 - 模拟版本（日志分文件存储）

TARGET_IP="${1:-172.18.0.4}"
LOG_ID="${2:-0}"
STEP="${3:-5}"
MAX_STEPS="${4:-35}"

# 模拟日志路径
LOG_FILE="/d/projects/current/mock_log/CoreMindCCommonServiceDemo/CDemoLog/CoreMindCCommonServiceDemo.log"
# 日志输出目录（每个批次一个文件）
OUTPUT_DIR="./test_results"
# 容器打包目录（模拟）
CONTAINER_ASCEND_DIR="/d/projects/current/mock_ascend"
CONTAINER_MINDSDK_DIR="/d/projects/current/mock_mindsdk"
PACK_OUTPUT_DIR="./logs_archive"
OPERATOR_NAME="TestAddPerformance"

echo "[*] Add 算子测试 - 模拟版本"
echo "[*] 目标IP: $TARGET_IP (模拟)"
echo "[*] 步长: $STEP"
echo "[*] 日志分目录: ${OUTPUT_DIR}/"
echo "[*] 验证模式: 只跑前 $MAX_STEPS 个组合"
echo ""

# 打包 ascend 目录（模拟版本）
pack_ascend_logs() {
    local operator_name="$1"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')

    mkdir -p "$PACK_OUTPUT_DIR"
    local pack_name="${PACK_OUTPUT_DIR}/${operator_name}_ascend_${timestamp}.tar.gz"

    if [ -d "$CONTAINER_ASCEND_DIR" ]; then
        echo "[*] 打包 ascend 目录 → $pack_name"
        tar -czf "$pack_name" -C "$(dirname "$CONTAINER_ASCEND_DIR")" "$(basename "$CONTAINER_ASCEND_DIR")" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "   ✓ 打包成功 ($(du -h "$pack_name" | cut -f1))"
        else
            echo "   ✗ 打包失败"
        fi
    else
        echo "[警告] ascend 目录不存在: $CONTAINER_ASCEND_DIR"
    fi
}

# 打包 mindsdk 目录（模拟版本）
pack_mindsdk_logs() {
    local operator_name="$1"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')

    mkdir -p "$PACK_OUTPUT_DIR"
    local pack_name="${PACK_OUTPUT_DIR}/${operator_name}_mindsdk_${timestamp}.tar.gz"

    if [ -d "$CONTAINER_MINDSDK_DIR" ]; then
        echo "[*] 打包 mindsdk 目录 → $pack_name"
        tar -czf "$pack_name" -C "$(dirname "$CONTAINER_MINDSDK_DIR")" "$(basename "$CONTAINER_MINDSDK_DIR")" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "   ✓ 打包成功 ($(du -h "$pack_name" | cut -f1))"
        else
            echo "   ✗ 打包失败"
        fi
    else
        echo "[警告] mindsdk 目录不存在: $CONTAINER_MINDSDK_DIR"
    fi
}

get_file_size() {
    if [ -f "$1" ]; then
        stat -c%s "$1" 2>/dev/null || wc -c < "$1" | tr -d ' '
    else
        echo 0
    fi
}

# 提取新增日志到独立文件
fetch_new_logs() {
    local log_path="$1"
    local start_pos="$2"
    local batch_num="$3"
    local size_info="$4"

    if [ ! -f "$log_path" ]; then
        return 0
    fi

    local current_size
    current_size=$(get_file_size "$log_path")

    if [ "$current_size" -gt "$start_pos" ]; then
        local batch_file
        batch_file=$(printf "%s/batch_%03d.log" "$OUTPUT_DIR" "$batch_num")
        {
            echo "============================================================"
            echo "测试尺寸: $size_info"
            echo "============================================================"
            tail -c +$((start_pos + 1)) "$log_path"
            echo "============================================================"
        } > "$batch_file"
    fi

    echo "$current_size"
}

# 模拟请求
mock_request() {
    sleep 0.1
    local rand=$((RANDOM % 100))
    [ "$rand" -lt 95 ] && return 0 || return 1
}

ROW_START=1; ROW_END=721
COL_START=1; COL_END=1280
ROW_STEP=$STEP
COL_STEP=$STEP

row_count=$(( (ROW_END - ROW_START) / ROW_STEP + 1 ))
col_count=$(( (COL_END - COL_START) / COL_STEP + 1 ))
total_steps=$((row_count * col_count))

echo "[*] Rows: $ROW_START ~ $ROW_END (共${row_count}个)"
echo "[*] Cols: $COL_START ~ $COL_END (共${col_count}个)"
echo "[*] 总组合: $total_steps → 实际跑: $MAX_STEPS"
echo ""

# 清空输出目录
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

last_log_position=$(get_file_size "$LOG_FILE")

success_count=0
fail_count=0
current_step=0

echo "=================================================="
echo "[开始] 算子: $OPERATOR_NAME"
echo "[时间] $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
echo ""

for ((ri=0; ri<row_count; ri++)); do
    r=$((ROW_START + ri * ROW_STEP))
    for ((ci=0; ci<col_count; ci++)); do
        c=$((COL_START + ci * COL_STEP))
        ((current_step++))

        [ "$current_step" -gt "$MAX_STEPS" ] && break 2

        printf "[%d/%d] Rows=%d, Cols=%d " "$current_step" "$MAX_STEPS" "$r" "$c"

        if mock_request; then
            echo "✓"
            ((success_count++))
        else
            echo "✗"
            ((fail_count++))
        fi

        if [ $((current_step % 10)) -eq 0 ]; then
            batch_num=$((current_step / 10))
            echo "   └─ 批次 $batch_num: 提取日志 → batch_${batch_num}.log"
            last_log_position=$(fetch_new_logs "$LOG_FILE" "$last_log_position" "$batch_num" "批次 $batch_num, Rows=$r, Cols=$c")
        fi
    done
done

if [ $((current_step % 10)) -ne 0 ]; then
    batch_num=$((current_step / 10 + 1))
    echo "   └─ 最终批次 $batch_num: 提取日志 → batch_${batch_num}.log"
    fetch_new_logs "$LOG_FILE" "$last_log_position" "$batch_num" "最终批次" > /dev/null
fi

# 算子执行完毕，统计耗时
echo ""
echo "=================================================="
echo "[完成] 算子: $OPERATOR_NAME"
echo "[统计] 成功: $success_count, 失败: $fail_count, 总计: $current_step"
echo "=================================================="

# 打包 ascend 和 mindsdk 目录
echo ""
pack_ascend_logs "$OPERATOR_NAME"
echo ""
pack_mindsdk_logs "$OPERATOR_NAME"

echo ""
echo "=================================================="
echo "日志目录: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"
echo "打包目录: $PACK_OUTPUT_DIR/"
ls -lh "$PACK_OUTPUT_DIR/"
echo "=================================================="
