#!/bin/bash
token='PUT_YOUR_TOKEN_HERE'
sparkID[1]='UID OF SPARK 1'
sparkID[2]='UID OF SPARK 2'
sparkID[3]='UID OF SPARK 3'
sparkID[4]='UID OF SPARK 4'
sparkID[5]='UID OF SPARK 5'
sparkID[6]='UID OF SPARK 6'
sparkResponses=/tmp/sparkVals
watchdogFile="/tmp/scriptWatchdog"
logFile="/var/log/lampServer"
pollSpeed=0.2

# INITIALIZATION
if [[ ! -p $sparkResponses ]]; then
    echo "$(date +"%Y%b%d %r") -  no pipe found at init: creating pipe" >> $logFile
    mkfifo $sparkResponses
fi
trap "rm -f $sparkResponses" EXIT
exec 3<> $sparkResponses
numOfSparks=${#sparkID[@]}
for i in `seq 1 $numOfSparks`;
do
    sparkPID[i]='999999999'
done
lampState='0';
lastLampState='0'

# RUN
while true
do
    touch $watchdogFile
    for i in `seq 1 $numOfSparks`
    do        # the pipe disappears sometimes...dunno why. wat?
        if [[ ! -p $sparkResponses ]]; then
	    echo "$(date +"%Y%b%d %r") -  Error: no pipe found. Creating pipe" >> $logFile
            mkfifo $sparkResponses
        fi
        deviceId=$((lampState >> 10))
        cmd=$((lampState >> 8 & 3))
        color=$((lampState & 255))
        if ! ps -p ${sparkPID[i]} > /dev/null
        then
            echo "Sending cmd: $cmd color: $color from Spark $deviceId to Spark $i PID"
            curl -N --max-time 2 -s https://api.spark.io/v1/devices/${sparkID[i]}/poll -d access_token=$token -d "args=$lampState" | grep return | cut -d ":" -f 2 | cut -d " " -f 2 >&3 &
            sparkPID[i]=$!
        fi
    done
    lampState=""
    while [[ -z "$lampState" ]]
    do
        if read -t 0.01 lampState <$sparkResponses
        then
            if [ "1$lampState" -eq "10" ]
            then
                lampState=$lastLampState
            fi
	    if 	[ "$((lampState >> 10))" -eq "0" ]
	    then
		echo "*********** ERRONEOUS DATA **************"
	    fi
            if [ "`expr $lampState % 1024 `" != "`expr $lastLampState % 1024`" ] &&
		[ "$((lampState >> 10))" -gt "0" ]
            then
                # echo "lamp state has changed to $lampState. Destroying all life forms."
		deviceId=$((lampState >> 10))
		cmd=$((lampState >> 8 & 3))
		color=$((lampState & 255))
		echo "$(date +"%Y%b%d %r") -  Received state: $lampState cmd: $cmd color: $color from Spark $deviceId." >> $logFile
		echo "Received state: $lampState cmd: $cmd color: $color from Spark $deviceId."
                for i in `seq 1 $numOfSparks`
                do
                    kill ${sparkPID[i]}
                done
                herrGarbage="nothing"
                while [ -n "$herrGarbage" ]
                do
                    read -t 0.01 herrGarbage <$sparkResponses
                    if [ -n "$herrGarbage" ]
                    then
                        #echo "emptying queue: $herrGarbage"
			deviceId=$((herrGarbage >> 10))
			cmd=$((herrGarbage >> 8 & 3))
			color=$((herrGarbage & 255))
			echo "$(date +"%Y%b%d %r") Dumping state: $herrGarbage cmd: $cmd color: $color from Spark $deviceId." >> $logFile
			echo "Dumping state: $herrGarbage cmd: $cmd color: $color from Spark $deviceId."
                    fi
                done
                lastLampState=$lampState
            else
                lampState=""
            fi
        else
            lampState=$lastLampState
        fi
    done
    sleep $pollSpeed
done

