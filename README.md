 wget https://raw.githubusercontent.com/baiyuns/tools/master/cn.sh && bash cn.sh

 wget https://raw.githubusercontent.com/baiyuns/tools/master/atport.sh && bash atport.sh

  wget https://raw.githubusercontent.com/baiyuns/tools/master/waftp.sh && bash waftp.sh

------------------------------
curl https://raw.githubusercontent.com/baiyuns/tools/master/cfddns.sh > /root/cfddns.sh && chmod +x /root/cfddns.sh

nano cfddns.sh

./cfddns.sh

crontab -e
*/2 * * * * /root/cfddns.sh >/dev/null 2>&1

# 如果需要日志，替换上一行代码
*/2 * * * * /root/cfddns.sh >> /var/log/cfddns.log 2>&1
