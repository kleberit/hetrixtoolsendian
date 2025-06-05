#!/bin/bash
#
# HetrixTools Server Monitoring Agent - Adaptado para Endian Firewall (BusyBox)
#
# Set PATH/Locale
export LC_NUMERIC="C"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ScriptPath=$(dirname "${BASH_SOURCE[0]}")
# Agent Version
Version="2.3.0"
# Load configuration file
if [ -f "$ScriptPath"/hetrixtools.cfg ]
then
    . "$ScriptPath"/hetrixtools.cfg
else
    echo "Arquivo de configuração não encontrado!"
    exit 1
fi
# Script start time
ScriptStartTime=$(date '+[%Y-%m-%d %T')
# Verificar comandos disponíveis
if ! command -v "ss" > /dev/null 2>&1; then
    USE_NETSTAT=1
else
    USE_NETSTAT=0
fi
# Service status function
function servicestatus() {
    if (( $(ps -ef | grep -E "[\/ ]$1([^\/]|$)" | grep -v "grep" | wc -l) > 0 ))
    then
        echo "1"
    else
        if service "$1" status > /dev/null 2>&1
        then
            echo "1"
        else
            echo "0"
        fi
    fi
}
# Function used to perform outgoing PING tests
function pingstatus() {
    local TargetName=$1
    local PingTarget=$2
    if ! [[ "$TargetName" =~ ^[a-zA-Z0-9\.\-_]+$ ]]
    then
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Invalid PING target name value" >> "$ScriptPath"/debug.log; fi
        exit 1
    fi
    if ! [[ "$PingTarget" =~ ^[a-zA-Z0-9\.\-:]+$ ]]
    then
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Invalid PING target value" >> "$ScriptPath"/debug.log; fi
        exit 1
    fi
    if ! [[ "$OutgoingPingsCount" =~ ^[0-9]+$ ]] || (( OutgoingPingsCount < 10 || OutgoingPingsCount > 40 ))
    then
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Invalid PING count value" >> "$ScriptPath"/debug.log; fi
        exit 1
    fi
    PING_OUTPUT=$(ping "$PingTarget" -c "$OutgoingPingsCount" 2>/dev/null)
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T])PING_OUTPUT:\n$PING_OUTPUT" >> "$ScriptPath"/debug.log; fi
    PACKET_LOSS=$(echo "$PING_OUTPUT" | grep -o '[0-9]\+% packet loss' | cut -d'%' -f1)
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T])PACKET_LOSS: $PACKET_LOSS" >> "$ScriptPath"/debug.log; fi
    if [ -z "$PACKET_LOSS" ]
    then
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Unable to extract packet loss" >> "$ScriptPath"/debug.log; fi
        exit 1
    fi
    RTT_LINE=$(echo "$PING_OUTPUT" | grep 'rtt min/avg/max/mdev')
    if [ -n "$RTT_LINE" ]
    then
        AVG_RTT=$(echo "$RTT_LINE" | awk -F'/' '{print $5}')
        AVG_RTT=$(echo "$AVG_RTT" | awk '{print $1 * 1000}' | awk '{printf "%18.0f",$1}' | xargs)
    else
        AVG_RTT="0"
    fi
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T])AVG_RTT: $AVG_RTT" >> "$ScriptPath"/debug.log; fi
    echo "$TargetName,$PingTarget,$PACKET_LOSS,$AVG_RTT;" >> "$ScriptPath"/ping.txt
}
# Check if the agent needs to run Outgoing PING tests
if [ "$1" == "ping" ]
then
    pingstatus "$2" "$3"
    exit 1
fi
# Clear debug.log every day at midnight
if [ -z "$(date +%H | sed 's/^0*//')" ] && [ -z "$(date +%M | sed 's/^0*//')" ] && [ -f "$ScriptPath"/debug.log ]
then
    rm -f "$ScriptPath"/debug.log
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Cleared debug.log" >> "$ScriptPath"/debug.log; fi
fi
# Start timers
START=$(date +%s)
tTIMEDIFF=0
# Get current minute
M=$(date +%M | sed 's/^0*//')
if [ -z "$M" ]
then
    M=0
    if [ -f "$ScriptPath"/hetrixtools_cron.log ]
    then
        rm -f "$ScriptPath"/hetrixtools_cron.log
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Cleared hetrixtools_cron.log" >> "$ScriptPath"/debug.log; fi
    fi
fi
#if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Starting HetrixTools Agent v$Version" >> "$ScriptPath"/debug.log; fi#
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Starting HetrixTools Agent v$Version with SID: $SID" >> "$ScriptPath"/debug.log; fi
# Kill any lingering agent processes
HTProcesses=$(pgrep -f hetrixtools_agent 2>/dev/null | wc -l)
if [ -z "$HTProcesses" ]
then
    HTProcesses=0
fi
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Found $HTProcesses agent processes" >> "$ScriptPath"/debug.log; fi
# Outgoing PING
if [ -n "$OutgoingPings" ]
then
    IFS='|' read -r -a OutgoingPingsArray <<< "$OutgoingPings"
    for i in "${OutgoingPingsArray[@]}"
    do
        IFS=',' read -r -a OutgoingPing <<< "$i"
        bash "$ScriptPath"/hetrixtools_agent_fixed.sh ping "${OutgoingPing[0]}" "${OutgoingPing[1]}" &
    done
fi
# Network interfaces
if [ -n "$NetworkInterfaces" ]
then
    IFS=',' read -r -a NetworkInterfacesArray <<< "$NetworkInterfaces"
else
    NetworkInterfacesArray=()
    for interface in $(cat /proc/net/dev | grep ':' | cut -d':' -f1 | sed 's/ //g')
    do
        if [ "$interface" != "lo" ] && ip link show "$interface" 2>/dev/null | grep -q "state UP"
        then
            NetworkInterfacesArray+=("$interface")
        fi
    done
fi
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Interfaces: ${NetworkInterfacesArray[*]}" >> "$ScriptPath"/debug.log; fi
# Initial network usage
T=$(cat /proc/net/dev)
declare -A aRX
declare -A aTX
declare -A tRX
declare -A tTX
# Loop through network interfaces
for NIC in "${NetworkInterfacesArray[@]}"
do
    aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
    aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
    tRX[$NIC]=0
    tTX[$NIC]=0
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Interface $NIC RX: ${aRX[$NIC]} TX: ${aTX[$NIC]}" >> "$ScriptPath"/debug.log; fi
done
# Port connections
if [ -n "$ConnectionPorts" ]
then
    IFS=',' read -r -a ConnectionPortsArray <<< "$ConnectionPorts"
    declare -A Connections
    if [ "$USE_NETSTAT" -eq 1 ]; then
        netstat_output=$(netstat -ntu 2>/dev/null | awk '{print $4}')
    else
        netstat_output=$(ss -ntu 2>/dev/null | awk '{print $5}')
    fi
    for cPort in "${ConnectionPortsArray[@]}"
    do
        Connections[$cPort]=$(echo "$netstat_output" | grep -c ":$cPort$")
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Port $cPort Connections: ${Connections[$cPort]}" >> "$ScriptPath"/debug.log; fi
    done
fi
# Temperature
declare -A TempArray
declare -A TempArrayCnt
# Check Services
if [ -n "$CheckServices" ]
then
    declare -A SRVCSR
    IFS=',' read -r -a CheckServicesArray <<< "$CheckServices"
    for i in "${CheckServicesArray[@]}"
    do
        SRVCSR[$i]=$(servicestatus "$i")
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Service $i status: ${SRVCSR[$i]}" >> "$ScriptPath"/debug.log; fi
    done
fi
# Disks IOPS - SIMPLIFICADO para evitar erros
declare -A vDISKs
for i in $(df | grep '^/' | awk '{print $(NF)}')
do
    # Usar método mais simples de detecção
    disk_device=$(df "$i" | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
    if [ -n "$disk_device" ]; then
        vDISKs[$i]=$(basename "$disk_device")
    fi
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Disk $i: ${vDISKs[$i]}" >> "$ScriptPath"/debug.log; fi
done
declare -A BlockSize
declare -A IOPSRead
declare -A IOPSWrite
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
    BlockSize[$i]=512  # Valor fixo para simplificar
    IOPSRead[$i]=0
    IOPSWrite[$i]=0
    if [ ! -z "${vDISKs[$i]}" ]
    then
        IOPSRead[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}')
        IOPSWrite[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}')
    fi
    if [ -z "${IOPSRead[$i]}" ]; then IOPSRead[$i]=0; fi
    if [ -z "${IOPSWrite[$i]}" ]; then IOPSWrite[$i]=0; fi
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Disk $i Block Size: ${BlockSize[$i]} IOPS Read: ${IOPSRead[$i]} Write: ${IOPSWrite[$i]}" >> "$ScriptPath"/debug.log; fi
done
# Calculate data sample loops
RunTimes=$(echo "60 / $CollectEveryXSeconds" | bc 2>/dev/null || echo | awk "{print 60 / $CollectEveryXSeconds}")
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Collecting data for $RunTimes loops" >> "$ScriptPath"/debug.log; fi
# Initialize totals
tCPU=0
tCPUwa=0
tCPUst=0
tCPUus=0
tCPUsy=0
tCPUSpeed=0
tloadavg1=0
tloadavg5=0
tloadavg15=0
tRAM=0
tRAMSwap=0
tRAMBuff=0
tRAMCache=0
# Collect data loop
for X in $(seq "$RunTimes")
do
    # Get vmstat
    VMSTAT=$(vmstat "$CollectEveryXSeconds" 2 | tail -1)
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) $VMSTAT" >> "$ScriptPath"/debug.log; fi
    # CPU usage
    if [ -n "$VMSTAT" ]; then
        CPU=$(echo "$VMSTAT" | awk '{print 100 - $15}')
        if [ -n "$CPU" ]; then
            tCPU=$(echo "$tCPU + $CPU" | bc 2>/dev/null || echo | awk "{print $tCPU + $CPU}")
        fi
        # CPU IO wait
        CPUwa=$(echo "$VMSTAT" | awk '{print $16}')
        if [ -n "$CPUwa" ]; then
            tCPUwa=$(echo "$tCPUwa + $CPUwa" | bc 2>/dev/null || echo | awk "{print $tCPUwa + $CPUwa}")
        fi
        # CPU steal time
        CPUst=$(echo "$VMSTAT" | awk '{print $17}')
        if [ -n "$CPUst" ]; then
            tCPUst=$(echo "$tCPUst + $CPUst" | bc 2>/dev/null || echo | awk "{print $tCPUst + $CPUst}")
        fi
        # CPU user time
        CPUus=$(echo "$VMSTAT" | awk '{print $13}')
        if [ -n "$CPUus" ]; then
            tCPUus=$(echo "$tCPUus + $CPUus" | bc 2>/dev/null || echo | awk "{print $tCPUus + $CPUus}")
        fi
        # CPU system time
        CPUsy=$(echo "$VMSTAT" | awk '{print $14}')
        if [ -n "$CPUsy" ]; then
            tCPUsy=$(echo "$tCPUsy + $CPUsy" | bc 2>/dev/null || echo | awk "{print $tCPUsy + $CPUsy}")
        fi
        # RAM usage
        aRAM=$(echo "$VMSTAT" | awk '{print $4 + $5 + $6}')
        bRAM=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
        if [ -n "$aRAM" ] && [ -n "$bRAM" ] && [ "$bRAM" -gt 0 ]; then
            RAM=$(echo "$aRAM * 100 / $bRAM" | bc 2>/dev/null || echo | awk "{print $aRAM * 100 / $bRAM}")
            RAM=$(echo "100 - $RAM" | bc 2>/dev/null || echo | awk "{print 100 - $RAM}")
            tRAM=$(echo "$tRAM + $RAM" | bc 2>/dev/null || echo | awk "{print $tRAM + $RAM}")
        fi
        # RAM swap usage
        aRAMSwap=$(echo "$VMSTAT" | awk '{print $3}')
        cRAM=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')
        if [ -n "$aRAMSwap" ] && [ -n "$cRAM" ] && [ "$cRAM" -gt 0 ]
        then
            RAMSwap=$(echo "$aRAMSwap * 100 / $cRAM" | bc 2>/dev/null || echo | awk "{print $aRAMSwap * 100 / $cRAM}")
        else
            RAMSwap=0
        fi
        if [ -n "$RAMSwap" ]; then
            tRAMSwap=$(echo "$tRAMSwap + $RAMSwap" | bc 2>/dev/null || echo | awk "{print $tRAMSwap + $RAMSwap}")
        fi
        # RAM buffers usage
        aRAMBuff=$(echo "$VMSTAT" | awk '{print $5}')
        if [ -n "$aRAMBuff" ] && [ -n "$bRAM" ] && [ "$bRAM" -gt 0 ]; then
            RAMBuff=$(echo "$aRAMBuff * 100 / $bRAM" | bc 2>/dev/null || echo | awk "{print $aRAMBuff * 100 / $bRAM}")
            tRAMBuff=$(echo "$tRAMBuff + $RAMBuff" | bc 2>/dev/null || echo | awk "{print $tRAMBuff + $RAMBuff}")
        fi
        # RAM cache usage
        aRAMCache=$(echo "$VMSTAT" | awk '{print $6}')
        if [ -n "$aRAMCache" ] && [ -n "$bRAM" ] && [ "$bRAM" -gt 0 ]; then
            RAMCache=$(echo "$aRAMCache * 100 / $bRAM" | bc 2>/dev/null || echo | awk "{print $aRAMCache * 100 / $bRAM}")
            tRAMCache=$(echo "$tRAMCache + $RAMCache" | bc 2>/dev/null || echo | awk "{print $tRAMCache + $RAMCache}")
        fi
    fi
    # CPU clock
    CPUSpeed=$(grep 'cpu MHz' /proc/cpuinfo | awk -F": " '{print $2}' | awk '{printf "%18.0f",$1}' | xargs | sed -e 's/ /+/g')
    if [ -z "$CPUSpeed" ]; then CPUSpeed=0; fi
    if [ -n "$CPUSpeed" ] && [ "$CPUSpeed" != "0" ]; then
        tCPUSpeed=$(echo "$tCPUSpeed + $CPUSpeed" | bc 2>/dev/null || echo | awk "{print $tCPUSpeed + $CPUSpeed}")
    fi
    # CPU Load
    loadavg=$(cat /proc/loadavg)
    if [ -n "$loadavg" ]; then
        loadavg1=$(echo "$loadavg" | awk '{print $1}')
        loadavg5=$(echo "$loadavg" | awk '{print $2}')
        loadavg15=$(echo "$loadavg" | awk '{print $3}')
        if [ -n "$loadavg1" ]; then
            tloadavg1=$(echo "$tloadavg1 + $loadavg1" | bc 2>/dev/null || echo | awk "{print $tloadavg1 + $loadavg1}")
        fi
        if [ -n "$loadavg5" ]; then
            tloadavg5=$(echo "$tloadavg5 + $loadavg5" | bc 2>/dev/null || echo | awk "{print $tloadavg5 + $loadavg5}")
        fi
        if [ -n "$loadavg15" ]; then
            tloadavg15=$(echo "$tloadavg15 + $loadavg15" | bc 2>/dev/null || echo | awk "{print $tloadavg15 + $loadavg15}")
        fi
    fi
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) CPU: $CPU IO wait: $CPUwa Load: $loadavg1 $loadavg5 $loadavg15" >> "$ScriptPath"/debug.log; fi
    # Network usage
    T=$(cat /proc/net/dev)
    END=$(date +%s)
    TIMEDIFF=$(echo "$END - $START" | bc 2>/dev/null || echo | awk "{print $END - $START}")
    if [ -n "$TIMEDIFF" ] && [ "$TIMEDIFF" -gt 0 ]; then
        tTIMEDIFF=$(echo "$tTIMEDIFF + $TIMEDIFF" | bc 2>/dev/null || echo | awk "{print $tTIMEDIFF + $TIMEDIFF}")
    fi
    START=$(date +%s)
    # Loop through network interfaces
    for NIC in "${NetworkInterfacesArray[@]}"
    do
        # Received Traffic
        curr_rx=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
        if [ -n "$curr_rx" ] && [ -n "${aRX[$NIC]}" ] && [ -n "$TIMEDIFF" ] && [ "$TIMEDIFF" -gt 0 ]; then
            RX=$(echo "($curr_rx - ${aRX[$NIC]}) / $TIMEDIFF" | bc 2>/dev/null || echo | awk "{print ($curr_rx - ${aRX[$NIC]}) / $TIMEDIFF}")
            RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
            aRX[$NIC]=$curr_rx
            tRX[$NIC]=$(echo "${tRX[$NIC]} + $RX" | bc 2>/dev/null || echo | awk "{print ${tRX[$NIC]} + $RX}")
            tRX[$NIC]=$(echo "${tRX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
        fi
        # Transferred Traffic
        curr_tx=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
        if [ -n "$curr_tx" ] && [ -n "${aTX[$NIC]}" ] && [ -n "$TIMEDIFF" ] && [ "$TIMEDIFF" -gt 0 ]; then
            TX=$(echo "($curr_tx - ${aTX[$NIC]}) / $TIMEDIFF" | bc 2>/dev/null || echo | awk "{print ($curr_tx - ${aTX[$NIC]}) / $TIMEDIFF}")
            TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
            aTX[$NIC]=$curr_tx
            tTX[$NIC]=$(echo "${tTX[$NIC]} + $TX" | bc 2>/dev/null || echo | awk "{print ${tTX[$NIC]} + $TX}")
            tTX[$NIC]=$(echo "${tTX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
        fi
    done
    # Port connections
    if [ -n "$ConnectionPorts" ]
    then
        if [ "$USE_NETSTAT" -eq 1 ]; then
            netstat_output=$(netstat -ntu 2>/dev/null | awk '{print $4}')
        else
            netstat_output=$(ss -ntu 2>/dev/null | awk '{print $5}')
        fi
        for cPort in "${ConnectionPortsArray[@]}"
        do
            curr_conn=$(echo "$netstat_output" | grep -c ":$cPort$")
            if [ -n "$curr_conn" ]; then
                Connections[$cPort]=$(echo "${Connections[$cPort]} + $curr_conn" | bc 2>/dev/null || echo | awk "{print ${Connections[$cPort]} + $curr_conn}")
            fi
        done
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Port Connections: ${Connections[*]}" >> "$ScriptPath"/debug.log; fi
    fi
    # Temperature usando /sys/class/thermal
    if [ "$(find /sys/class/thermal/thermal_zone*/type 2> /dev/null | wc -l)" -gt 0 ]
    then
        TempArrayIndex=()
        TempArrayVal=()
        for zone in /sys/class/thermal/thermal_zone*/
        do
            if [[ -f "${zone}/type" ]] && [[ -f "${zone}/temp" ]]
            then
                type_value=$(<"${zone}/type")
                temp_value=$(<"${zone}/temp")
                if [[ -n $type_value ]]
                then
                    TempArrayIndex+=("$type_value")
                fi
                if [[ $temp_value =~ ^[0-9]+$ ]]
                then
                    TempArrayVal+=("$temp_value")
                else
                    TempArrayVal+=("0")
                fi
            fi
        done
        TempNameCnt=0
        for TempName in "${TempArrayIndex[@]}"
        do
            TempArray[$TempName]=${TempArray[$TempName]:-0}
            TempArrayCnt[$TempName]=${TempArrayCnt[$TempName]:-0}
            if [[ ${TempArrayVal[$TempNameCnt]} =~ ^[0-9]+$ ]]
            then
                TempArray[$TempName]=$((${TempArray[$TempName]} + ${TempArrayVal[$TempNameCnt]}))
                TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
            fi
            TempNameCnt=$((TempNameCnt + 1))
        done
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Temperature: ${TempArray[*]}" >> "$ScriptPath"/debug.log; fi
    fi
    # Check if minute changed
    MM=$(date +%M | sed 's/^0*//')
    if [ -z "$MM" ]; then MM=0; fi
    if [ "$MM" -ne "$M" ]
    then
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Minute changed, ending loop" >> "$ScriptPath"/debug.log; fi
        break
    fi
done
# Get user running the agent
User=$(whoami)
# Check if system requires reboot
RequiresReboot=0
if [ -f /var/run/reboot-required ]
then
    RequiresReboot=1
fi
# Operating System - adaptado para Endian
if command -v "lsb_release" > /dev/null 2>&1
then
    OS=$(lsb_release -s -d)
elif [ -f /etc/debian_version ]
then
    OS="Debian $(cat /etc/debian_version)"
elif [ -f /etc/redhat-release ]
then
    OS=$(cat /etc/redhat-release)
elif [ -f /etc/os-release ]
then
    OS="$(grep '^PRETTY_NAME=' /etc/os-release | awk -F'"' '{print $2}')"
else
    OS="$(uname -s)"
fi
OS=$(echo -ne "$OS" | base64 | tr -d '\n\r\t ')
# Kernel
Kernel=$(uname -r | base64 | tr -d '\n\r\t ')
# Hostname
Hostname=$(uname -n | base64 | tr -d '\n\r\t ')
# Server uptime
Uptime=$(awk '{print $1}' < /proc/uptime | awk '{printf "%18.0f",$1}' | xargs)
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) User: $User Hostname: $Hostname Uptime: $Uptime" >> "$ScriptPath"/debug.log; fi
# CPU information - usando /proc/cpuinfo
CPUModel=$(grep -m1 -E 'model name|cpu model' /proc/cpuinfo | awk -F": " '{print $NF}' | xargs)
CPUModel=$(echo -ne "$CPUModel" | base64 | tr -d '\n\r\t ')
# CPU sockets
CPUSockets=$(grep -i "physical id" /proc/cpuinfo | sort -u | wc -l)
if [ "$CPUSockets" -eq 0 ]; then CPUSockets=1; fi
# CPU cores
CPUCores=$(grep -c ^processor /proc/cpuinfo)
# CPU threads
CPUThreads=$(grep "siblings" /proc/cpuinfo | head -1 | awk '{print $NF}')
if [ -z "$CPUThreads" ]; then CPUThreads=$CPUCores; fi
# CPU clock speed
if [ -z "$tCPUSpeed" ] || [ "$tCPUSpeed" = "0" ]
then
    CPUSpeed=$(grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{print $4}' | awk '{printf "%18.0f",$1}' | xargs)
    if [ -z "$CPUSpeed" ]; then CPUSpeed=0; fi
else
    if [ "$CPUCores" -gt 0 ] && [ "$X" -gt 0 ]; then
        CPUSpeed=$(echo "$tCPUSpeed / $CPUCores / $X" | bc 2>/dev/null || echo | awk "{print $tCPUSpeed / $CPUCores / $X}" | awk '{printf "%18.0f",$1}' | xargs)
    else
        CPUSpeed=0
    fi
fi
# Average values
if [ "$X" -gt 0 ]; then
    CPU=$(echo "$tCPU / $X" | bc 2>/dev/null || echo | awk "{print $tCPU / $X}")
    CPUwa=$(echo "$tCPUwa / $X" | bc 2>/dev/null || echo | awk "{print $tCPUwa / $X}")
    CPUst=$(echo "$tCPUst / $X" | bc 2>/dev/null || echo | awk "{print $tCPUst / $X}")
    CPUus=$(echo "$tCPUus / $X" | bc 2>/dev/null || echo | awk "{print $tCPUus / $X}")
    CPUsy=$(echo "$tCPUsy / $X" | bc 2>/dev/null || echo | awk "{print $tCPUsy / $X}")
    loadavg1=$(echo "$tloadavg1 / $X" | bc 2>/dev/null || echo | awk "{print $tloadavg1 / $X}")
    loadavg5=$(echo "$tloadavg5 / $X" | bc 2>/dev/null || echo | awk "{print $tloadavg5 / $X}")
    loadavg15=$(echo "$tloadavg15 / $X" | bc 2>/dev/null || echo | awk "{print $tloadavg15 / $X}")
    RAM=$(echo "$tRAM / $X" | bc 2>/dev/null || echo | awk "{print $tRAM / $X}")
    RAMSwap=$(echo "$tRAMSwap / $X" | bc 2>/dev/null || echo | awk "{print $tRAMSwap / $X}")
    RAMBuff=$(echo "$tRAMBuff / $X" | bc 2>/dev/null || echo | awk "{print $tRAMBuff / $X}")
    RAMCache=$(echo "$tRAMCache / $X" | bc 2>/dev/null || echo | awk "{print $tRAMCache / $X}")
else
    CPU=0
    CPUwa=0
    CPUst=0
    CPUus=0
    CPUsy=0
    loadavg1=0
    loadavg5=0
    loadavg15=0
    RAM=0
    RAMSwap=0
    RAMBuff=0
    RAMCache=0
fi
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) CPU Model: $CPUModel Cores: $CPUCores Speed: $CPUSpeed CPU: $CPU Load: $loadavg1" >> "$ScriptPath"/debug.log; fi
# RAM size
RAMSize=$(grep ^MemTotal: /proc/meminfo | awk '{print $2}')
# RAM swap size
RAMSwapSize=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) RAM Size: $RAMSize Usage: $RAM" >> "$ScriptPath"/debug.log; fi
# Disks inodes
INODEs=$(echo -ne "$(df -Ti | sed 1d | grep -v -E 'tmpfs' | awk '{print $(NF)","$3","$4","$5";"}')" | tr -d '\n\r\t ' | base64 | tr -d '\n\r\t ')
# Disks IOPS - SIMPLIFICADO para evitar a linha complexa que estava causando erro
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Starting IOPS calculation" >> "$ScriptPath"/debug.log; fi
IOPS=""
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Processing IOPS for disk: $i (${vDISKs[$i]})" >> "$ScriptPath"/debug.log; fi
    
    # Obter valores atuais
    curr_read=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}')
    curr_write=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}')
    
    # Verificar se os valores são válidos
    if [ -z "$curr_read" ]; then curr_read=0; fi
    if [ -z "$curr_write" ]; then curr_write=0; fi
    
    # Calcular diferenças usando aritmética mais simples
    if [ -n "$tTIMEDIFF" ] && [ "$tTIMEDIFF" -gt 0 ]; then
        read_diff=$(echo "($curr_read - ${IOPSRead[$i]}) * ${BlockSize[$i]} / $tTIMEDIFF" | bc 2>/dev/null || echo "0")
        write_diff=$(echo "($curr_write - ${IOPSWrite[$i]}) * ${BlockSize[$i]} / $tTIMEDIFF" | bc 2>/dev/null || echo "0")
    else
        read_diff=0
        write_diff=0
    fi
    
    # Formatar resultados
    read_diff=$(echo "$read_diff" | awk '{printf "%18.0f",$1}' | xargs 2>/dev/null || echo "0")
    write_diff=$(echo "$write_diff" | awk '{printf "%18.0f",$1}' | xargs 2>/dev/null || echo "0")
    
    IOPS="$IOPS$i,$read_diff,$write_diff;"
    
    if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) IOPS for $i: read=$read_diff write=$write_diff" >> "$ScriptPath"/debug.log; fi
done
IOPS=$(echo -ne "$IOPS" | base64 | tr -d '\n\r\t ')
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) IOPS calculation completed. IOPS: $IOPS" >> "$ScriptPath"/debug.log; fi
# Total network usage and IP addresses
NICS=""
IPv4=""
IPv6=""
for NIC in "${NetworkInterfacesArray[@]}"
do
    # Individual NIC network usage
    if [ "$X" -gt 0 ]; then
        RX=$(echo "${tRX[$NIC]} / $X" | bc 2>/dev/null || echo | awk "{print ${tRX[$NIC]} / $X}")
        RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
        TX=$(echo "${tTX[$NIC]} / $X" | bc 2>/dev/null || echo | awk "{print ${tTX[$NIC]} / $X}")
        TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
    else
        RX=0
        TX=0
    fi
    NICS="$NICS$NIC,$RX,$TX;"
    # Individual NIC IP addresses - simplificado para Endian
    ipv4_addrs=$(ip addr show "$NIC" 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | xargs | sed 's/ /,/g')
    ipv6_addrs=$(ip addr show "$NIC" 2>/dev/null | grep 'inet6.*global' | awk '{print $2}' | cut -d'/' -f1 | xargs | sed 's/ /,/g')
    IPv4="$IPv4$NIC,$ipv4_addrs;"
    IPv6="$IPv6$NIC,$ipv6_addrs;"
done
NICS=$(echo -ne "$NICS" | base64 | tr -d '\n\r\t ')
IPv4=$(echo -ne "$IPv4" | base64 | tr -d '\n\r\t ')
IPv6=$(echo -ne "$IPv6" | base64 | tr -d '\n\r\t ')
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Network Interfaces: $NICS" >> "$ScriptPath"/debug.log; fi
# Port connections
CONN=""
if [ -n "$ConnectionPorts" ] && [ "$X" -gt 0 ]
then
    for cPort in "${ConnectionPortsArray[@]}"
    do
        CON=$(echo "${Connections[$cPort]} / $X" | bc 2>/dev/null || echo | awk "{print ${Connections[$cPort]} / $X}")
        CON=$(echo "$CON" | awk '{printf "%18.0f",$1}' | xargs)
        CONN="$CONN$cPort,$CON;"
    done
fi
CONN=$(echo -ne "$CONN" | base64 | tr -d '\n\r\t ')
# Temperature
TEMP=""
if [ "${#TempArray[@]}" -gt 0 ]
then
    for TempName in "${!TempArray[@]}"
    do
        if [ "${TempArrayCnt[$TempName]}" -gt 0 ]
        then
            TMP=$(echo "${TempArray[$TempName]} / ${TempArrayCnt[$TempName]}" | bc 2>/dev/null || echo | awk "{print ${TempArray[$TempName]} / ${TempArrayCnt[$TempName]}}")
            TMP=$(echo "$TMP" | awk '{printf "%18.0f",$1}' | xargs)
            TEMP="$TEMP$TempName,$TMP;"
        fi
    done
fi
TEMP=$(echo -ne "$TEMP" | base64 | tr -d '\n\r\t ')
# Check Services
SRVCS=""
if [ -n "$CheckServices" ]
then
    for i in "${CheckServicesArray[@]}"
    do
        status=$(servicestatus "$i")
        SRVCS="$SRVCS$i,$status;"
    done
fi
SRVCS=$(echo -ne "$SRVCS" | base64 | tr -d '\n\r\t ')
# Software RAID
RAID=""
if [ "$CheckSoftRAID" -gt 0 ]
then
    dfPB1=$(df -PB1 2>/dev/null)
    for i in $(echo -ne "$dfPB1" | awk '$1 ~ /\// {print}' | awk '{print $1}')
    do
        mdadm_output=$(mdadm -D "$i" 2>/dev/null)
        if [ -n "$mdadm_output" ]
        then
            mnt=$(echo -ne "$dfPB1" | grep "$i " | awk '{print $(NF)}')
            RAID="$RAID$mnt,$i,$mdadm_output;"
        fi
    done
fi
RAID=$(echo -ne "$RAID" | base64 | tr -d '\n\r\t ')
# Disks usage - Simplificado
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Starting disk usage calculation" >> "$ScriptPath"/debug.log; fi
DISKs=""
df_output=$(df -TPB1 | sed 1d | grep -v -E 'tmpfs')
while IFS= read -r line
do
    if [ -n "$line" ]
    then
        mount_point=$(echo "$line" | awk '{print $(NF)}')
        filesystem_type=$(echo "$line" | awk '{print $2}')
        total_size=$(echo "$line" | awk '{print $3}')
        used_size=$(echo "$line" | awk '{print $4}')
        available_size=$(echo "$line" | awk '{print $5}')
        
        DISKs="$DISKs$mount_point,$filesystem_type,$total_size,$used_size,$available_size;"
        
        if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Disk: $mount_point Type: $filesystem_type Size: $total_size" >> "$ScriptPath"/debug.log; fi
    fi
done <<< "$df_output"
DISKs=$(echo -ne "$DISKs" | base64 | tr -d '\n\r\t ')
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Disk usage calculation completed" >> "$ScriptPath"/debug.log; fi
# Drive Health (desabilitado)
DH=""
# Custom Variables
CV=""
if [ -n "$CustomVars" ] && [ -s "$ScriptPath"/"$CustomVars" ]
then
    CV=$(cat "$ScriptPath"/"$CustomVars" | base64 | tr -d '\n\r\t ')
fi
# Outgoing PING
OPING=""
if [ -n "$OutgoingPings" ] && [ -f "$ScriptPath"/ping.txt ]
then
    OPING=$(grep -v '^$' "$ScriptPath"/ping.txt | tr -d '\n' | base64 | tr -d '\n\r\t ')
    rm -f "$ScriptPath"/ping.txt
fi
# Running Processes
RPS1=""
RPS2=""
if [ "$RunningProcesses" -gt 0 ]
then
    if [ -f "$ScriptPath"/running_proc.txt ]
    then
        RPS1=$(cat "$ScriptPath"/running_proc.txt)
    fi
    RPS2=$(ps -ef | base64 -w 0 2>/dev/null || ps -ef | base64)
    echo "$RPS2" > "$ScriptPath"/running_proc.txt
fi
# Secured Connection
if [ "$SecuredConnection" -gt 0 ]
then
    SecuredConnection=""
else
    SecuredConnection="--no-check-certificate"
fi
# Current time/date
Time=$(date '+%Y-%m-%d %T %Z' | base64 | tr -d '\n\r\t ')
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) Starting JSON preparation" >> "$ScriptPath"/debug.log; fi
# Prepare data - JSON corrigido
json='{"version":"'"$Version"'","SID":"'"$SID"'","agent":"0","user":"'"$User"'","os":"'"$OS"'","kernel":"'"$Kernel"'","hostname":"'"$Hostname"'","time":"'"$Time"'","reqreboot":"'"$RequiresReboot"'","uptime":"'"$Uptime"'","cpumodel":"'"$CPUModel"'","cpusockets":"'"$CPUSockets"'","cpucores":"'"$CPUCores"'","cputhreads":"'"$CPUThreads"'","cpuspeed":"'"$CPUSpeed"'","cpu":"'"$CPU"'","wa":"'"$CPUwa"'","st":"'"$CPUst"'","us":"'"$CPUus"'","sy":"'"$CPUsy"'","load1":"'"$loadavg1"'","load5":"'"$loadavg5"'","load15":"'"$loadavg15"'","ramsize":"'"$RAMSize"'","ram":"'"$RAM"'","ramswapsize":"'"$RAMSwapSize"'","ramswap":"'"$RAMSwap"'","rambuff":"'"$RAMBuff"'","ramcache":"'"$RAMCache"'","disks":"'"$DISKs"'","inodes":"'"$INODEs"'","iops":"'"$IOPS"'","raid":"'"$RAID"'","zp":"","dh":"'"$DH"'","nics":"'"$NICS"'","ipv4":"'"$IPv4"'","ipv6":"'"$IPv6"'","conn":"'"$CONN"'","temp":"'"$TEMP"'","serv":"'"$SRVCS"'","cust":"'"$CV"'","oping":"'"$OPING"'","rps1":"'"$RPS1"'","rps2":"'"$RPS2"'"}'
# Compress payload
jsoncomp=$(echo -ne "$json" | gzip -cf | base64 -w 0 2>/dev/null | sed 's/ //g' | sed 's/\//%2F/g' | sed 's/+/%2B/g' || echo -ne "$json" | gzip | base64 | tr -d '\n' | sed 's/ //g' | sed 's/\//%2F/g' | sed 's/+/%2B/g')
# Save data to file
echo "j=$jsoncomp" > "$ScriptPath"/hetrixtools_agent.log
if [ "$DEBUG" -eq 1 ]; then echo -e "$ScriptStartTime-$(date +%T]) JSON preparation completed. Length: ${#json}" >> "$ScriptPath"/debug.log; fi
# BusyBox compatible wget
if [ "$DEBUG" -eq 1 ]
then
    echo -e "$ScriptStartTime-$(date +%T]) Posting data with BusyBox wget" >> "$ScriptPath"/debug.log
    # Tentar diferentes métodos de POST para BusyBox
    if wget --help 2>&1 | grep -q "post-data"; then
        # Método 1: wget com --post-data (se suportado)
        wget --post-data="$(cat "$ScriptPath"/hetrixtools_agent.log)" -q -O- -T 15 https://sm.hetrixtools.net/v2/ >> "$ScriptPath"/debug.log 2>&1
    elif command -v curl > /dev/null 2>&1; then
        # Método 2: curl como fallback (se disponível)
        curl -s -X POST -d @"$ScriptPath"/hetrixtools_agent.log https://sm.hetrixtools.net/v2/ >> "$ScriptPath"/debug.log 2>&1
    fi
    echo -e "$ScriptStartTime-$(date +%T]) Data posted via BusyBox compatible method" >> "$ScriptPath"/debug.log
else
    # Modo silencioso - tentar o método mais simples
    if wget --help 2>&1 | grep -q "post-data"; then
        wget --post-data="$(cat "$ScriptPath"/hetrixtools_agent.log)" -q -O- -T 15 https://sm.hetrixtools.net/v2/ > /dev/null 2>&1
    elif command -v curl > /dev/null 2>&1; then
        curl -s -X POST -d @"$ScriptPath"/hetrixtools_agent.log https://sm.hetrixtools.net/v2/ > /dev/null 2>&1
    fi
fi
