#!/bin/bash
# 多算子自动化测试脚本
# 用法: ./test_all_operators.sh <目标IP> <日志ID> [步长] [最大组合数] [容器ID]
# 示例: ./test_all_operators.sh 172.18.0.4 0              # 默认步长5
#       ./test_all_operators.sh 172.18.0.4 0 5            # 步长5
#       ./test_all_operators.sh 172.18.0.4 0 10 100       # 每个算子只跑100个
#       ./test_all_operators.sh 172.18.0.4 0 10 0 2fe5937ad00a

TARGET_IP="${1:-}"
LOG_ID="${2:-}"
STEP="${3:-5}"       # 标准算子步长，默认5
MAX_STEPS="${4:-0}"   # 0=不限制
CONTAINER_ID="${5:-}" # 留空自动查找

RESIZE_STEP=40        # Resize类算子步长固定40

if [ -z "$TARGET_IP" ] || [ -z "$LOG_ID" ]; then
    echo "用法: $0 <目标IP> <日志ID> [步长] [最大组合数] [容器ID]"
    echo "示例: $0 172.18.0.4 0"
    echo "      $0 172.18.0.4 0 10 100"
    exit 1
fi

# ============================================================
# 自动查找 ccom 容器
# ============================================================
find_ccom_container() {
    docker ps --format "{{.ID}} {{.Image}}" | grep -i ccom | grep -v pause | head -1 | awk '{print $1}'
}

if [ -z "$CONTAINER_ID" ]; then
    echo "[*] 自动查找 ccom 容器..."
    CONTAINER_ID=$(find_ccom_container)
    if [ -n "$CONTAINER_ID" ]; then
        echo "   ✓ 找到容器: $CONTAINER_ID"
    else
        echo "   ✗ 未找到 ccom 容器，将跳过打包步骤"
    fi
fi

# ============================================================
# 路径配置
# ============================================================
LOG_FILE="/opt/container/log/${LOG_ID}/CoreMindCCommonServiceDemo/CDemoLog/CoreMindCCommonServiceDemo.log"
CONTAINER_ASCEND_DIR="/home/paas/ascend"
CONTAINER_MINDXSDK_DIR="/home/paas/var/log/mindxsdk"
BASE_RESULTS_DIR="./test_results"
BASE_ARCHIVE_DIR="./logs_archive"
API_URL="http://${TARGET_IP}:2580/testing/task/create"

echo ""
echo "=================================================="
echo " 多算子自动化测试"
echo "=================================================="
echo "[*] 目标IP: $TARGET_IP"
echo "[*] 日志ID: $LOG_ID"
echo "[*] 标准步长: $STEP"
echo "[*] Resize步长: $RESIZE_STEP"
if [ -n "$CONTAINER_ID" ]; then
    echo "[*] 容器ID: $CONTAINER_ID"
fi
echo "[*] 监控日志: $LOG_FILE"
echo ""

# ============================================================
# 通用函数
# ============================================================
get_file_size() {
    if [ -f "$1" ]; then
        stat -c%s "$1" 2>/dev/null || wc -c < "$1" | tr -d ' '
    else
        echo 0
    fi
}

fetch_new_logs() {
    local log_path="$1"
    local start_pos="$2"
    local batch_file="$3"
    local size_info="$4"

    if [ ! -f "$log_path" ]; then
        return 0
    fi

    local current_size
    current_size=$(get_file_size "$log_path")

    if [ "$current_size" -lt "$start_pos" ]; then
        start_pos=0
    fi

    if [ "$current_size" -gt "$start_pos" ]; then
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

send_request() {
    local payload="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL" \
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

pack_container_dir() {
    local container_dir="$1"
    local pack_suffix="$2"
    local operator_name="$3"
    local container="$4"

    if [ -z "$container" ]; then
        return 0
    fi

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local archive_dir="${BASE_ARCHIVE_DIR}/${operator_name}"
    mkdir -p "$archive_dir"

    local pack_name="${pack_suffix}_${timestamp}.tar.gz"
    local container_tmp="/tmp/${pack_name}"
    local local_pack="${archive_dir}/${pack_name}"

    echo "   [*] 打包 ${container_dir}/ ..."

    if ! docker exec "$container" test -d "$container_dir" 2>/dev/null; then
        echo "   [警告] 目录不存在: $container_dir"
        return 0
    fi

    local tar_result
    tar_result=$(docker exec "$container" tar -czf "$container_tmp" -C "$(dirname "$container_dir")" "$(basename "$container_dir")" 2>&1)
    if [ $? -ne 0 ]; then
        echo "   ✗ 打包失败: $tar_result"
        return 1
    fi

    docker cp "${container}:${container_tmp}" "$local_pack" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "   ✓ $(du -h "$local_pack" | cut -f1)"
        docker exec "$container" rm -f "$container_tmp" 2>/dev/null
    else
        echo "   ✗ docker cp 失败"
        return 1
    fi
}

# ============================================================
# 算子定义（19个）
# ============================================================

# 算子短名（用于目录名）
OPERATOR_SHORT_NAMES=(
    "ConvertTo" "Rotate" "Add" "Subtract" "Divide"
    "Multiply" "CvtColor" "WarpAffine" "MaskImgFusion" "AddWeighted"
    "Merge" "Split" "BlendImage" "BlendCaption" "Erode"
    "Threshold" "Min"
    "Resize" "ResizeMask"
)

# 算子函数名
OPERATOR_FUNC_NAMES=(
    "TestConvertToPerformance"
    "TestRotatePerformance"
    "TestAddPerformance"
    "TestSubtractPerformance"
    "TestDividePerformance"
    "TestMultiplyPerformance"
    "TestCvtColorPerformance"
    "TestWarpAffinePerformance"
    "TestMaskImgFusionPerformance"
    "TestAddWeightedPerformance"
    "TestMergePerformance"
    "TestSplitPerformance"
    "TestBlendImagePerformance"
    "TestBlendCaptionPerformance"
    "TestErodePerformance"
    "TestThresholdPerformance"
    "TestMinPerformance"
    "TestResizePerformance"
    "TestResizeMaskPerformance"
)

# 算子描述
OPERATOR_DESCRIPTIONS=(
    "测试ConvertTo算子的性能"
    "测试Rotate算子的性能"
    "测试Add算子的性能"
    "测试Subtract算子的性能"
    "测试Divide算子的性能"
    "测试Multiply算子的性能"
    "测试CvtColor算子的性能"
    "测试WarpAffine算子的性能"
    "测试MaskImgFusion算子的性能"
    "测试AddWeighted算子的性能"
    "测试Merge算子的性能"
    "测试Split算子的性能"
    "测试BlendImage算子的性能"
    "测试BlendCaption算子的性能"
    "测试Erode算子的性能"
    "测试Threshold算子的性能"
    "测试Min算子的性能"
    "测试Resize算子的性能"
    "测试ResizeMask算子的性能"
)

# 标准算子的固定扩展参数（17个，对应前17个算子）
OPERATOR_EXTRA_PARAMS=(
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"16FC1","convertedXMatType":"8UC3","frameCount":"100"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","angle":"90","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1000","size":"3"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","scale":"0.5","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1","scale":"2.0"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","mode":"9","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"32FC3","width":"400","height":"400","frameCount":"1000"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC1","frameCount":"1","size":"3"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1000","size":"3"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","captionBgOpacity":"0.8","frameCount":"1000"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1000"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1000"'
    '"imageRows":"__ROWS__","imageCols":"__COLS__","XMatType":"8UC3","frameCount":"1"'
)

# 算子类型: S=标准, R=Resize, M=ResizeMask
OPERATOR_TYPES=(
    "S" "S" "S" "S" "S" "S" "S" "S" "S" "S"
    "S" "S" "S" "S" "S" "S" "S"
    "R" "M"
)

TOTAL_OPERATORS=${#OPERATOR_FUNC_NAMES[@]}

# 标准尺寸范围
ROW_START=1
ROW_END=721
COL_START=1
COL_END=1280

echo "[*] 算子总数: $TOTAL_OPERATORS"
echo "[*] 标准算子: 17个 (步长$STEP, 每算子 $((  (ROW_END-ROW_START)/STEP+1 )) × $((  (COL_END-COL_START)/STEP+1 )) = $(( ((ROW_END-ROW_START)/STEP+1) * ((COL_END-COL_START)/STEP+1) )) 组合)"
echo "[*] Resize算子: 2个 (步长$RESIZE_STEP, 4维遍历)"
echo ""

# ============================================================
# 生成标准算子 payload
# ============================================================
build_standard_payload() {
    local func_name="$1"
    local description="$2"
    local extra_params="$3"
    local rows="$4"
    local cols="$5"

    local params="${extra_params//__ROWS__/$rows}"
    params="${params//__COLS__/$cols}"

    echo "{\"testingJobList\":[{\"testingFuncName\":\"${func_name}\",\"testingExtParam\":{${params},\"isPerformance\":\"false\"}}],\"testingTaskDescription\":\"${description}\",\"testingType\":\"SINGLE\"}"
}

# ============================================================
# 生成 Resize payload
# ============================================================
build_resize_payload() {
    local func_name="$1"
    local description="$2"
    local in_rows="$3"
    local in_cols="$4"
    local out_rows="$5"
    local out_cols="$6"
    local out_prefix="$7"  # "resizedImage" 或 "resizemaskedImage"

    echo "{\"testingJobList\":[{\"testingFuncName\":\"${func_name}\",\"testingExtParam\":{\"inputImage_Rows\":\"${in_rows}\",\"inputImage_Cols\":\"${in_cols}\",\"inputImage_XMatType\":\"8UC3\",\"${out_prefix}_Rows\":\"${out_rows}\",\"${out_prefix}_Cols\":\"${out_cols}\",\"${out_prefix}_XMatType\":\"8UC3\",\"frameCount\":\"1000\",\"isPerformance\":\"false\"}}],\"testingTaskDescription\":\"${description}\",\"testingType\":\"SINGLE\"}"
}

# ============================================================
# 运行单个标准算子
# ============================================================
run_standard_operator() {
    local idx="$1"
    local func_name="${OPERATOR_FUNC_NAMES[$idx]}"
    local short_name="${OPERATOR_SHORT_NAMES[$idx]}"
    local description="${OPERATOR_DESCRIPTIONS[$idx]}"
    local extra_params="${OPERATOR_EXTRA_PARAMS[$idx]}"

    local results_dir="${BASE_RESULTS_DIR}/${short_name}"
    rm -rf "$results_dir"
    mkdir -p "$results_dir"

    local row_count=$(( (ROW_END - ROW_START) / STEP + 1 ))
    local col_count=$(( (COL_END - COL_START) / STEP + 1 ))
    local total=$((row_count * col_count))

    if [ "$MAX_STEPS" -gt 0 ] && [ "$MAX_STEPS" -lt "$total" ]; then
        total=$MAX_STEPS
    fi

    echo "=================================================="
    echo " 算子 [$((idx+1))/$TOTAL_OPERATORS]: $short_name"
    echo " 函数: $func_name"
    echo " 尺寸: Rows ${ROW_START}~${ROW_END}, Cols ${COL_START}~${COL_END}, 步长${STEP}"
    echo " 组合: $total"
    echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================="

    local last_log_pos=$(get_file_size "$LOG_FILE")
    local success=0
    local fail=0
    local step=0
    local op_start=$(date +%s)

    for ((ri=0; ri<row_count; ri++)); do
        local r=$((ROW_START + ri * STEP))
        for ((ci=0; ci<col_count; ci++)); do
            local c=$((COL_START + ci * STEP))
            ((step++))

            [ "$step" -gt "$total" ] && break 2

            local payload
            payload=$(build_standard_payload "$func_name" "$description" "$extra_params" "$r" "$c")

            printf "  [%d/%d] R=%d C=%d " "$step" "$total" "$r" "$c"

            if send_request "$payload"; then
                echo "✓"
                ((success++))
            else
                echo "✗"
                ((fail++))
            fi

            if [ $((step % 10)) -eq 0 ]; then
                local bn=$((step / 10))
                local batch_file
                batch_file=$(printf "%s/batch_%03d.log" "$results_dir" "$bn")
                echo "   └─ 批次 $bn → batch_${bn}.log"
                last_log_pos=$(fetch_new_logs "$LOG_FILE" "$last_log_pos" "$batch_file" "批次 $bn, R=$r, C=$c")
            fi
        done
    done

    # 最后一批
    if [ $((step % 10)) -ne 0 ] && [ "$step" -gt 0 ]; then
        local bn=$((step / 10 + 1))
        local batch_file
        batch_file=$(printf "%s/batch_%03d.log" "$results_dir" "$bn")
        fetch_new_logs "$LOG_FILE" "$last_log_pos" "$batch_file" "最终批次" > /dev/null
    fi

    local op_end=$(date +%s)
    local duration=$((op_end - op_start))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    echo "  [完成] $short_name: 成功=$success, 失败=$fail, 耗时=${minutes}分${seconds}秒"

    # 打包
    echo ""
    pack_container_dir "$CONTAINER_ASCEND_DIR" "ascend" "$short_name" "$CONTAINER_ID"
    pack_container_dir "$CONTAINER_MINDXSDK_DIR" "mindxsdk" "$short_name" "$CONTAINER_ID"

    # 记录汇总
    SUMMARY_LINES+=("$short_name | 成功=$success 失败=$fail | ${minutes}分${seconds}秒")
}

# ============================================================
# 运行 Resize 类算子（4维遍历）
# ============================================================
run_resize_operator() {
    local idx="$1"
    local func_name="${OPERATOR_FUNC_NAMES[$idx]}"
    local short_name="${OPERATOR_SHORT_NAMES[$idx]}"
    local description="${OPERATOR_DESCRIPTIONS[$idx]}"

    local out_prefix
    if [ "${OPERATOR_TYPES[$idx]}" = "R" ]; then
        out_prefix="resizedImage"
    else
        out_prefix="resizemaskedImage"
    fi

    local results_dir="${BASE_RESULTS_DIR}/${short_name}"
    rm -rf "$results_dir"
    mkdir -p "$results_dir"

    local rs_step=$RESIZE_STEP
    local in_row_count=$(( (ROW_END - ROW_START) / rs_step + 1 ))
    local in_col_count=$(( (COL_END - COL_START) / rs_step + 1 ))
    local out_row_count=$in_row_count
    local out_col_count=$in_col_count
    local total=$((in_row_count * in_col_count * out_row_count * out_col_count))

    if [ "$MAX_STEPS" -gt 0 ] && [ "$MAX_STEPS" -lt "$total" ]; then
        total=$MAX_STEPS
    fi

    echo "=================================================="
    echo " 算子 [$((idx+1))/$TOTAL_OPERATORS]: $short_name"
    echo " 函数: $func_name"
    echo " 4维遍历: 步长${rs_step}"
    echo " 组合: $total"
    echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================="

    local last_log_pos=$(get_file_size "$LOG_FILE")
    local success=0
    local fail=0
    local step=0
    local op_start=$(date +%s)

    for ((ir=0; ir<in_row_count; ir++)); do
        local in_r=$((ROW_START + ir * rs_step))
        for ((ic=0; ic<in_col_count; ic++)); do
            local in_c=$((COL_START + ic * rs_step))
            for ((orr=0; orr<out_row_count; orr++)); do
                local out_r=$((ROW_START + orr * rs_step))
                for ((orc=0; orc<out_col_count; orc++)); do
                    local out_c=$((COL_START + orc * rs_step))
                    ((step++))

                    [ "$step" -gt "$total" ] && break 4

                    local payload
                    payload=$(build_resize_payload "$func_name" "$description" "$in_r" "$in_c" "$out_r" "$out_c" "$out_prefix")

                    printf "  [%d/%d] in=(%d,%d) out=(%d,%d) " "$step" "$total" "$in_r" "$in_c" "$out_r" "$out_c"

                    if send_request "$payload"; then
                        echo "✓"
                        ((success++))
                    else
                        echo "✗"
                        ((fail++))
                    fi

                    if [ $((step % 10)) -eq 0 ]; then
                        local bn=$((step / 10))
                        local batch_file
                        batch_file=$(printf "%s/batch_%03d.log" "$results_dir" "$bn")
                        echo "   └─ 批次 $bn"
                        last_log_pos=$(fetch_new_logs "$LOG_FILE" "$last_log_pos" "$batch_file" "批次 $bn, in=($in_r,$in_c) out=($out_r,$out_c)")
                    fi
                done
                [ "$step" -gt "$total" ] && break 3
            done
            [ "$step" -gt "$total" ] && break 2
        done
        [ "$step" -gt "$total" ] && break 1
    done

    # 最后一批
    if [ $((step % 10)) -ne 0 ] && [ "$step" -gt 0 ]; then
        local bn=$((step / 10 + 1))
        local batch_file
        batch_file=$(printf "%s/batch_%03d.log" "$results_dir" "$bn")
        fetch_new_logs "$LOG_FILE" "$last_log_pos" "$batch_file" "最终批次" > /dev/null
    fi

    local op_end=$(date +%s)
    local duration=$((op_end - op_start))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    echo ""
    echo "  [完成] $short_name: 成功=$success, 失败=$fail, 耗时=${minutes}分${seconds}秒"

    echo ""
    pack_container_dir "$CONTAINER_ASCEND_DIR" "ascend" "$short_name" "$CONTAINER_ID"
    pack_container_dir "$CONTAINER_MINDXSDK_DIR" "mindxsdk" "$short_name" "$CONTAINER_ID"

    SUMMARY_LINES+=("$short_name | 成功=$success 失败=$fail | ${minutes}分${seconds}秒")
}

# ============================================================
# 主流程
# ============================================================
SUMMARY_LINES=()
GLOBAL_START=$(date +%s)

echo ""
echo "开始执行 $TOTAL_OPERATORS 个算子..."
echo ""

for ((i=0; i<TOTAL_OPERATORS; i++)); do
    op_type="${OPERATOR_TYPES[$i]}"

    case "$op_type" in
        "S")
            run_standard_operator "$i"
            ;;
        "R"|"M")
            run_resize_operator "$i"
            ;;
    esac

    echo ""
    echo ""
done

GLOBAL_END=$(date +%s)
GLOBAL_DURATION=$((GLOBAL_END - GLOBAL_START))
GLOBAL_MIN=$((GLOBAL_DURATION / 60))
GLOBAL_SEC=$((GLOBAL_DURATION % 60))

# ============================================================
# 汇总报告
# ============================================================
echo ""
echo "============================================================"
echo " 全部算子执行完毕！"
echo " 总耗时: ${GLOBAL_MIN}分${GLOBAL_SEC}秒"
echo "============================================================"
echo ""
echo " 算子汇总:"
echo " --------------------------------------------------------"
printf " | %-18s | %-22s | %-12s |\n" "算子" "结果" "耗时"
echo " --------------------------------------------------------"
for line in "${SUMMARY_LINES[@]}"; do
    IFS='|' read -r name result time <<< "$line"
    printf " | %-18s | %-22s | %-12s |\n" "$name" "$result" "$time"
done
echo " --------------------------------------------------------"
echo ""
echo " 日志目录: ${BASE_RESULTS_DIR}/"
echo " 打包目录: ${BASE_ARCHIVE_DIR}/"
echo "============================================================"
