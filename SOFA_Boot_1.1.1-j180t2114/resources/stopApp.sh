#!/bin/bash

kill_tengine()
{
  /usr/bin/killall -9 tengine
  /bin/sleep 1
}

kill_nginxPro(){
  nginxPro=`/usr/bin/pgrep -f nginx`
  if [ ! -z "$nginxPro" ];then
   /bin/kill -9 $nginxPro
  fi
}

kill_java() {
    # ignore xflush and timetunnel.User can self define the process ignored
    local bootpids=`ps aux | grep admin |grep java| grep -v python | grep -v cloudmonitor | grep -v xflush | grep -v timetunnel | grep -v grep |awk '{print $2;}'`
    local boot_pid_array=($bootpids)
    echo -e "\\nkilling SOFABoot processes:${boot_pid_array[@]}"
    for bootpid in "${boot_pid_array[@]}"
    do
        if [ -z "$bootpid" ]; then
            continue;
        fi
        echo "kill $bootpid"
	    kill $bootpid
	    sleep 5
	    killed_pid=`ps aux|grep java|grep $bootpid |awk '{print $2;}'`

	    if [[ "$killed_pid" == "$bootpid" ]]; then
	    echo "Kill $bootpid don't work and kill -9 $bootpid used violently!"
        kill -9 $bootpid
	    fi
    done
}


main(){
  kill_tengine
  kill_nginxPro
  kill_java

  echo "kill end"
  exit 0
}
main