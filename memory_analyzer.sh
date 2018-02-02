#!/bin/bash

if [ "$1" == "--help" ]; then

	echo "Example: ./memory_analyzer.sh"
	echo "A sequence of tests will be performed for configured limits."
	echo "Please configure variables in config section before running tests"
	exit 1;

fi


################## config section starts ###################

jvm_pid=8152;
monitor_sleep_time_ms=0.1;
limits=(5);
url="http://localhost:8080/search/test?pageSize=100";
curl_command='curl -X POST $url -H "content-type:application/json" -d "@data.json"';
################## config section ends #####################


# output file names

counter_file="counter.txt"
heap_memory_file="heap_memory.txt"
cpu_memory_file="cpu_memory.txt";
time_output_file="time_consumed.txt";
command_output_file="log.txt"


#others

concurrent_requests=0;

if [[ -z "$1" ]]; then
	echo "No value for concurrent requests provided."
	echo "Will run a sequence of tests"
fi


if [[ -z "$JAVA_HOME" ]]; then
	#export JAVA_HOME=/opt/jdk1.6.0_37
	JAVA_HOME="/c/"Program Files"/Java/jdk1.7.0_79/";
fi

function cleanup {
	> $counter_file;
	> $heap_memory_file;
	> $command_output_file;
	> $cpu_memory_file;
	> $time_output_file;
}

function appendTestPrefix {
	echo "$1" >> $heap_memory_file;
	echo "$1" >> $command_output_file;
	echo "$1" >> $cpu_memory_file; 
	echo "$1" >> $time_output_file;
}

# Total Heap utilization(In KB) = OU(OLD SPACE UTILIZATION) + EU(EDEN SPACE UTILIZATION) + S0U(SURVIVOR SPACE 0 UTILIZATION) + S1U(SURVIVOR SPACE 1 UTILIZATION)
function monitor_heap_memory_usage {
	while true
	do
		local counter=$(wc -w ${counter_file} | cut -f1 -d' ')
		if [[ "$counter" == "$concurrent_requests" ]]; then
			local end_time=$(($(date +%s)*1000));
			echo "end_time:" ${end_time};
			echo "Total time taken in ms:" $((${end_time}-${start_time})) >> $time_output_file;
			exit 1;
		fi
		local time=$(($(date +%s)*1000));
		local mem=$("$JAVA_HOME"/bin/jstat -gc ${jvm_pid} | tail -1| awk '{split($0,a," "); sum=a[3]+a[4]+a[6]+a[8]; print sum}');
		echo "$time $mem"  >> $heap_memory_file 2>&1 &
		sleep ${monitor_sleep_time_ms}
	done
	 
}


function monitor_cpu_usage {
	while true
	do
		local counter=$(wc -w ${counter_file} | cut -f1 -d' ')
		if [[ "$counter" == "$concurrent_requests" ]]; then
			exit 1;
		fi
		local time=$(($(date +%s)*1000));
		local mem=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage "%"}');
		#top -bn 2 -d 0.01 | grep '^Cpu.s.' | tail -n 1 | awk '{print $2+$4+$6}' >> $cpu_memory_file 2>&1 &
		echo "$time $mem"  >> $cpu_memory_file 2>&1 &
		sleep ${monitor_sleep_time_ms}
	done
}

function async {
    
    local commandToExec="$1"
    local resolve="$2"
    local reject="$3"

    if [[ -z "$commandToExec" || -z "$reject"  ||  -z "$resolve" ]]; then
		printf "%s\n" "Insufficient number of arguments";
		return 1;
    fi

    local temp_array=( "$commandToExec" "$reject" "$resolve" )
        
    for temp in "${temp_array[@]}";do
		read -d " " comm <<<"${temp}"
		type "${comm}" &>/dev/null
		local status=$?
    	(( status != 0 )) && {
    	    printf "\"%s\" is neither a function nor a recognized command\n" "${temp}";
	    unset temp
	    return 1;
    	}
    done
    
	unset temp_array ;  unset temp
    
    {
	#result=$($commandToExec)
	result=$(curl -X POST ${url} -H "content-type:application/json" -d "@data.json")
	status=$?
	(( status == 0 )) && {
	    $resolve "${result}"
	} || {
	    $reject "${status}"
	}
	unset result
    } &

    JOB_IDS+=( "${JOBS} ${command}" )
    
    read -d " " -a __kunk__ <<< "${JOB_IDS[$(( ${#JOB_IDS[@]} - 1))]}"    
    echo ${__kunk__}
    : $(( JOBS++ ))
    
}



function success {
	echo " success" >> $counter_file;
	local result="$1"
	echo "$result" >> $command_output_file 2>&1 &
}

function error {
	echo "error occured"
	echo " error" >> $counter_file;
}

function send_async_requests {

for (( i=0; i<${concurrent_requests} ; i+=1 )) ; do
		async "$curl_command" success error;
done

}


################# driver method to run tests ############################
function main {
cleanup
for i in "${limits[@]}"
do
echo ""> $counter_file;
local iteration_separator="iteration for $i requests";
appendTestPrefix "$iteration_separator";
	#send requests and analyze memory
	echo "Performing GC..."
	su zantaz -c "$JAVA_HOME/bin/jcmd ${jvm_pid} GC.run"
	
	concurrent_requests=${i};
	
	start_time=$(($(date +%s)*1000));
	echo "start_time:" "${start_time}";
	
	monitor_heap_memory_usage &
	monitor_cpu_usage &
	echo "Running" ${concurrent_requests} " concurrent operations!";
	send_async_requests &
	wait
done

}

main
