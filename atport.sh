#!/usr/bin/env bash
echo -e "Please input your server main ip"
		stty erase '^H' && read -p "(such as 8.8.8.8):" main_ip
		[[ -z "${main_ip}" ]] && echo -e "cancel..." && exit 1
echo -e "Please input how many /24 you want to use, max is 5"
		stty erase '^H' && read -p "(such as 1):" user_ip_num
		[[ -z "${user_ip_num}" ]] && echo -e "cancel..." && exit 1
iptables -t nat -F
iptables -t nat -A POSTROUTING -o br0 -j SNAT --to ${main_ip}
user_ip_head="10.0."
for (( c = 1; c <= ${user_ip_num}; c++ ));do
	for (( d = 1; d <= 255; d++ ));do
		user_ip=${user_ip_head}${c}"."${d}
		if (("$d" < 10)); then
			ssh_port="6"${c}"00"${d}
			user_port_first=${c}"00"${d}"0"
			user_port_last=${c}"00"${d}"9"
		elif (("$d" < 100)); then
			ssh_port="6"${c}"0"${d}
			user_port_first=${c}"0"${d}"0"
			user_port_last=${c}"0"${d}"9"
		else
			ssh_port="6"${c}${d}
			user_port_first=${c}${d}"0"
			user_port_last=${c}${d}"9"
		fi
		iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${ssh_port} -j DNAT --to-destination ${user_ip}:22
		iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${user_port_first}:${user_port_last} -j DNAT --to-destination ${user_ip}
		iptables -t nat -A PREROUTING -p udp -m udp --dport ${user_port_first}:${user_port_last} -j DNAT --to-destination ${user_ip}	
	done
	iptables -t nat -A POSTROUTING -s 10.0.${c}.0/24 -j MASQUERADE
done
service iptables save
service iptables restart
echo -e "It seems done"
