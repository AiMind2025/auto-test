#!/bin/bash
# Add 算子测试脚本 - 正式版本（带容器打包）
# 用法: ./test_add_operator.sh <目标IP> <日志ID> [步长] [最大组合数] [容器ID]
# 示例: ./test_add_operator.sh 172.18.0.4 0              # 步长5，跑全部
#       ./test_add_operator.sh 172.18.0.4 0 10           # 步长10
#       ./test_add_operator.sh 172.18.0.4 0 5 100        # 步长5，只跑100个
#       ./test_add_operator.sh 172.18.0.4 0 5 0 2fe5937ad00a  # 指定容器

TARGET_IP="${1:-}"
LOG_ID="${2:-}"
STEP="${3:-5}"       # 步长，默认5
MAX_STEPS="${4:-0}"  # 0 表示不限制
CONTAINER_ID="${5:-}"  # 容器ID或名称

if [ -z "$TARGET_IP" ] || [ -z "$LOG_ID" ]; then
    echo "用法: $0 <目标IP> <日志ID> [步长] [最大组合数] [容器ID]"
    echo "示例: $0 172.18.0.4 0"
    echo "      $0 172.18.0.4 0 10           # 步长10"
    echo "      $0 172.18.0.4 0 5 100 2fe5937ad00a"
    exit 1
fi

# 日志路径
LOG_FILE="/opt/container/log/${LOG_ID}/CoreMindCCommonServiceDemo/CDemoLog/CoreMindCCommonServiceDemo.log"
# 日志输出目录（每个批次一个文件）
OUTPUT_DIR="./test_results"

# 需要打包的目录配置
CONTAINER_ASCEND_DIR="/home/paas/ascend"  # 容器内 ascend 目录
CONTAINER_MINDSDK_DIR="/home/paas/var/log/mindsdk"  # 容器内 mindsdk 日志目录
PACK_OUTPUT_DIR="./logs_archive"

# 算子名称
OPERATOR_NAME="TestAddPerformance"

# API 配置
API_URL="http://${TARGET_IP}:2580/testing/task/create"

echo "[*] Add 算子测试"
echo "[*] 目标IP: $TARGET_IP"
echo "[*] 日志ID: $LOG_ID"
echo "[*] API地址: $API_URL"
echo "[*] 监控日志: $LOG_FILE"
echo "[*] 日志目录: ${OUTPUT_DIR}/"
if [ -n "$CONTAINER_ID" ]; then
    echo "[*] 容器ID: $CONTAINER_ID"
    echo "[*] 打包目录1: ${CONTAINER_ASCEND_DIR}/ → ${PACK_OUTPUT_DIR}/"
    echo "[*] 打包目录2: ${CONTAINER_MINDSDK_DIR}/ → ${PACK_OUTPUT_DIR}/"
fi
echo ""

# 获取文件大小
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
        echo "   [警告] 日志文件不存在: $log_path"
        return 0
    fi

    local current_size
    current_size=$(get_file_size "$log_path")

    if [ "$current_size" -lt "$start_pos" ]; then
        # 日志轮转，从头读取
        start_pos=0
    fi

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

# 从容器中打包 /home/paas/ascend/ 目录并复制到宿主机
pack_container_ascend() {
    local operator_name="$1"
    local container="$2"

    if [ -z "$container" ]; then
        echo "[跳过] 未指定容器ID，跳过 ascend 打包"
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    mkdir -p "$PACK_OUTPUT_DIR"

    local pack_name="${operator_name}_ascend_${timestamp}.tar.gz"
    local container_tmp="/tmp/${pack_name}"
    local local_pack="${PACK_OUTPUT_DIR}/${pack_name}"

    echo "[*] 打包容器内 ${CONTAINER_ASCEND_DIR}/ ..."

    # 1. 在容器内打包
    docker exec "$container" tar -czf "$container_tmp" -C "$(dirname "$CONTAINER_ASCEND_DIR")" "$(basename "$CONTAINER_ASCEND_DIR")" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "   ✗ 容器内打包失败"
        return 1
    fi

    # 2. 复制到宿主机
    docker cp "${container}:${container_tmp}" "$local_pack" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "   ✓ 已保存: $local_pack ($(du -h "$local_pack" | cut -f1))"
        # 清理容器内临时文件
        docker exec "$container" rm -f "$container_tmp" 2>/dev/null
    else
        echo "   ✗ docker cp 失败"
        return 1
    fi
}

# 从容器中打包 /home/paas/var/log/mindsdk/ 目录并复制到宿主机
pack_container_mindsdk() {
    local operator_name="$1"
    local container="$2"

    if [ -z "$container" ]; then
        echo "[跳过] 未指定容器ID，跳过 mindsdk 打包"
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    mkdir -p "$PACK_OUTPUT_DIR"

    local pack_name="${operator_name}_mindsdk_${timestamp}.tar.gz"
    local container_tmp="/tmp/${pack_name}"
    local local_pack="${PACK_OUTPUT_DIR}/${pack_name}"

    echo "[*] 打包容器内 ${CONTAINER_MINDSDK_DIR}/ ..."

    # 1. 在容器内打包
    docker exec "$container" tar -czf "$container_tmp" -C "$(dirname "$CONTAINER_MINDSDK_DIR")" "$(basename "$CONTAINER_MINDSDK_DIR")" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "   ✗ 容器内打包失败"
        return 1
    fi

    # 2. 复制到宿主机
    docker cp "${container}:${container_tmp}" "$local_pack" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "   ✓ 已保存: $local_pack ($(du -h "$local_pack" | cut -f1))"
        # 清理容器内临时文件
        docker exec "$container" rm -f "$container_tmp" 2>/dev/null
    else
        echo "   ✗ docker cp 失败"
        return 1
    fi
}

# 发送真实请求
send_request() {
    local ip="$1"
    local rows="$2"
    local cols="$3"

    local payload="{\"testingJobList\":[{\"testingFuncName\":\"TestAddPerformance\",\"testingExtParam\":{\"imageRows\":\"${rows}\",\"imageCols\":\"${cols}\",\"XMatType\":\"8UC3\",\"frameCount\":\"1\",\"isPerformance\":\"false\"}}],\"testingTaskDescription\":\"cv add operator\",\"testingType\":\"SINGLE\"}"

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://${ip}:2580/testing/task/create" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null)

    if [ "$http_code" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# 尺寸范围
ROW_START=1
ROW_END=721
COL_START=1
COL_END=1280
ROW_STEP=$STEP
COL_STEP=$STEP

# 计算各维度数量
row_count=$(( (ROW_END - ROW_START) / ROW_STEP + 1 ))
col_count=$(( (COL_END - COL_START) / COL_STEP + 1 ))
total_steps=$((row_count * col_count))

echo "[*] Rows: $ROW_START ~ $ROW_END (步长$ROW_STEP, 共${row_count}个)"
echo "[*] Cols: $COL_START ~ $COL_END (步长$COL_STEP, 共${col_count}个)"
echo "[*] 总组合数: $total_steps (笛卡尔积: $row_count × $col_count)"
echo ""

# 如果设置了 MAX_STEPS，调整实际执行数
actual_steps=$total_steps
if [ "$MAX_STEPS" -gt 0 ] && [ "$MAX_STEPS" -lt "$total_steps" ]; then
    actual_steps=$MAX_STEPS
    echo "[*] 验证模式: 只跑前 $actual_steps 个组合"
    echo ""
fi

# 清空输出目录
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# 记录日志文件初始位置
last_log_position=$(get_file_size "$LOG_FILE")
echo "[*] 日志文件初始大小: $last_log_position bytes"
echo ""

success_count=0
fail_count=0
current_step=0
start_time=$(date +%s)

# 笛卡尔积：外层遍历 Rows，内层遍历 Cols
for ((ri=0; ri<row_count; ri++)); do
    r=$((ROW_START + ri * ROW_STEP))
    for ((ci=0; ci<col_count; ci++)); do
        c=$((COL_START + ci * COL_STEP))
        ((current_step++))

        # 检查是否达到限制
        if [ "$actual_steps" -lt "$total_steps" ] && [ "$current_step" -gt "$actual_steps" ]; then
            break 2
        fi

        printf "[%d/%d] Rows=%d, Cols=%d " "$current_step" "$actual_steps" "$r" "$c"

        if send_request "$TARGET_IP" "$r" "$c"; then
            echo "✓"
            ((success_count++))
        else
            echo "✗ 失败"
            ((fail_count++))
        fi

        # 每10个尺寸提取一次日志
        if [ $((current_step % 10)) -eq 0 ]; then
            batch_num=$((current_step / 10))
            echo "   └─ 批次 $batch_num: 提取日志 → batch_${batch_num}.log"
            last_log_position=$(fetch_new_logs "$LOG_FILE" "$last_log_position" "$batch_num" "批次 $batch_num, 尺寸: Rows=$r, Cols=$c")
        fi
    done
done

# 处理最后一批
if [ $((current_step % 10)) -ne 0 ] && [ "$current_step" -gt 0 ]; then
    batch_num=$((current_step / 10 + 1))
    echo "   └─ 最终批次 $batch_num: 提取日志 → batch_${batch_num}.log"
    fetch_new_logs "$LOG_FILE" "$last_log_position" "$batch_num" "最终批次, 尺寸: Rows=$ROW_END, Cols=$COL_END" > /dev/null
fi

# 算子执行完毕，打包容器内 ascend 和 mindsdk 目录
echo ""
pack_container_ascend "$OPERATOR_NAME" "$CONTAINER_ID"
echo ""
pack_container_mindsdk "$OPERATOR_NAME" "$CONTAINER_ID"

end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

echo ""
echo "=================================================="
echo "测试完成!"
echo "成功: $success_count, 失败: $fail_count"
echo "耗时: ${minutes}分${seconds}秒"
echo "日志目录: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/" 2>/dev/null
echo "打包目录: $PACK_OUTPUT_DIR/"
ls -lh "$PACK_OUTPUT_DIR/" 2>/dev/null
echo "=================================================="
