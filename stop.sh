#!/bin/bash

echo
echo "Cleaning up... One moment please"
airmon-ng stop wlan0mon > /dev/null
airmon-ng stop wlan1mon > /dev/null
airmon-ng stop wlan2mon > /dev/null
echo " [*] Monitor interfaces down"
for i in $(ps aux|grep autopixie.sh |cut -d " " -f7);do kill $i;done 2>/dev/null
echo " [*] Autopixie scripts stopped"
killall wash 2> /dev/null
echo " [*] WPS Sniffing stopped"
NICS=$(iwconfig 2>/dev/null | grep wl | cut -d ' ' -f 1)
for CARD in $NICS
do
	ifconfig $CARD up
done
echo " [*] Wireless cards restored"

[[ -f target.txt ]] && targets=$(cat target.txt 2>/dev/null |sort -u |wc -l) || targets=0
[[ -f recovered.txt ]] && recovered=$(cat recovered.txt 2>/dev/null |grep PSK |wc -l) || recovered=0
[[ -f pins.txt ]] && pins=$(cat pins.txt 2>/dev/null |sort -u |wc -l) || pins=0
[[ -f blacklist.txt ]] && notvuln=$(cat blacklist.txt |sort -u |grep Not |wc -l) || notvuln=0

success=$(( $recovered + $pins ))
vulnrate=$(awk "BEGIN { pc=100*${success}/${targets}; i=int(pc); print (pc-i<0.5)?i:i+1}")
[[ $vulnrate == *nan* ]] && vulnrate=0
echo "Found $targets WPS enabled networks, $success of which were vulnerable"
echo "Exploit rate of $vulnrate%"
