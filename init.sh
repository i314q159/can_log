#!/usr/bin/env bash

USER_NAME="admin"
CAN_LOG="/home/$USER_NAME/can_log"

if [ ! -e $CAN_LOG ]; then
	mkdir -pv $CAN_LOG
fi

cat >$CAN_LOG/can_log.sh <<'EOF'
#!/usr/bin/env bash

CAN_CHANNEL="can0"
CAN_FILTER=",100:7ffffff"
LOG_BASE_DIR="/home/admin/can_log"

# 4个3600秒为间隔分日志
ROTATE_INTERVAL=$((3600 * 4))

if [ ! -e $LOG_BASE_DIR ]; then
	mkdir -pv "$LOG_BASE_DIR"
fi

# 电流解析函数
# parse_current() {
# 	local b2=$1 b3=$2
# 	local hex_val="${b2}${b3}"
# 	local val=$((16#$hex_val))
# 	((val >= 32768)) && val=$((val - 65536))
# 	echo "scale=2; $val * 10 / 1000" | bc
# }

current_file=""
current_start_time=0
interval=$ROTATE_INTERVAL

while IFS= read -r line; do
	# 仅处理长度=8的帧
	if [[ ! "$line" =~ \[8\] ]]; then
		continue
	fi

	# 解析字段（candump 典型格式： can0 100 [8] 11 22 33 44 55 66 77 88）
	# 将行拆分为数组，字段索引从0开始
	# fields=($line)

	# 字段索引：0=can0, 1=ID, 2=[8], 3=字节1, 4=字节2, 5=字节3, 6=字节4, 7=字节5, 8=字节6, 9=字节7, 10=字节8
	# 原脚本使用 $6 和 $7，即数组索引5和6，对应第3和第4个数据字节
	# 加三就对了，can0, ID, [8]

	# b2="${fields[5]}" # 原脚本的 b2
	# b3="${fields[6]}" # 原脚本的 b3
	# cur=$(parse_current "$b2" "$b3")

	now=$(date +%s)
	slot=$((now / interval))

	if [[ -z "$current_file" ]] || [[ $slot -ne $((current_start_time / interval)) ]]; then
		if [[ -n "$current_file" ]]; then
			exec 3>&-
		fi

		time_str=$(date +"%Y-%m-%d_%H:%M:%S")
		current_file="${LOG_BASE_DIR}/can0_${time_str}.log"

		# >&3为追加模式
		exec 3>>"$current_file"

		current_start_time=$now
		echo "# 日志文件开始于 $(date)" >&3
	fi

	echo "$(date +"%Y-%m-%d_%H:%M:%S") $line" >&3

	# 处理结果可以组合输出
	# echo "$(date +"%Y-%m-%d_%H:%M:%S") $line | current: $cur A" >&3
done < <(candump "${CAN_CHANNEL}${CAN_FILTER}")

exec 3>&-
EOF

chown -R $USER_NAME:$USER_NAME $CAN_LOG
sudo -u $USER_NAME chmod +x $CAN_LOG/can_log.sh

cat >/etc/systemd/system/canlog.service <<EOF
[Unit]
Description=Can Log
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=5
StartLimitInterval=0

User=admin
WorkingDirectory=$CAN_LOG/
ExecStart=$CAN_LOG/can_log.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now canlog.service
