#!/bin/bash
if [ -z $DEFINED_UTILS ]; then
    DEFINED_UTILS=1
else
    return
fi

function load_param()
{
    local properties_file=$1
    local param=$2
    RESULT=`cat $properties_file | sed 's|[[:blank:]]||g' | grep "^$param=" | cut -d= -f2`
}

# clean windows \r in file $1, $1 should be an absolute path
function clean_windows_cr() {
    sed --in-place='' 's/\r//g' $1
}

function check_exit_code()
{
    if [ -z "$1" -o -z "$2" ]; then
        return
    fi

    if [ ! "$2" -eq "0" ]; then
        echo "Error while executing script $1 ! Error code : $2"
        exit $2
    fi
}

function kill_tengine()
{
  /usr/bin/killall -9 tengine
  /bin/sleep 1
}

function kill_nginxPro(){
  nginxPro=`/usr/bin/pgrep -f nginx`
  if [ ! -z "$nginxPro" ];then
   /bin/kill -9 $nginxPro
  fi
}

function run_hook() {
    [ $# -lt 2 ] && return
    local hook_name=$1
    local dir_name=$2
    # find hooks
    if [ -z "$HOOKS_SCRIPT" ]; then
        HOOKS_SCRIPT="/dev/null"
        if [ -f ${dir_name}/hook.sh ]; then
            HOOKS_SCRIPT=${dir_name}/hook.sh
        fi
    fi
    if [ -f "$HOOKS_SCRIPT" ]; then
        clean_windows_cr $HOOKS_SCRIPT
        source $HOOKS_SCRIPT
        grep -q $hook_name $HOOKS_SCRIPT && eval $hook_name
    fi
    return 0
}


function get_java_opts() {
    local java_opts_dir=$1
    local default_file=$java_opts_dir/java_opts
    local java_opts_files=( `ls $java_opts_dir | grep java_opts_` )
    if [ -z "$java_opts_files" ]; then
        if [ -f $default_file ]; then
            clean_windows_cr $default_file
            JAVA_OPTS=`cat $default_file`
            echo "default file $default_file is used for java_opts"
            return
        else
            JAVA_OPTS=""
            echo "no java_opts files found in $java_opts_dir"
            return
        fi
    fi

    MEM=`free -m | grep "Mem" | awk -F" " '{print $2}'`
    deviation=500
    # check if memory size fits
    found_match=""
    for file_name in ${java_opts_files[@]}
    do
        let "UPPER = $MEM + $deviation"
        let "LOWER = $MEM - $deviation"

        # extract number n from file name java_opts_ng
        local target_mem=${file_name#java_opts_}
        target_mem=${target_mem%g}

        # if has 16g java opts, set deviation to 1000m
        if [ $target_mem -eq "16" ]; then
            let "UPPER = $MEM + 1000"
            let "LOWER = $MEM - 1000"
        fi

        # translate to mega bytes, use 1000 because ecs memory is lower then expected
        let "target_mem *= 1000"

        java_opts_file=$java_opts_dir/$file_name
        # memory matches
        if [ $target_mem -gt $LOWER -a $target_mem -lt $UPPER ];
        then
            echo "file $file_name is used. actual memory: $MEM"
            clean_windows_cr $java_opts_file
            JAVA_OPTS=`cat $java_opts_file`

            found_match="true"
            break;
        fi
    done

    if [ -z $found_match ]; then
        # no match found, use default
        if [ -f $default_file ]; then
            clean_windows_cr $default_file
            JAVA_OPTS=`cat $default_file`
            echo "default file $default_file is used for java_opts"
            return
        else
            JAVA_OPTS=""
            echo "no matched java_opts files found in $java_opts_dir"
            return
        fi
    fi
}

function get_confreg()
{
  if [ ! -f /etc/metafile ]; then
    echo "/etc/metafile does not exist"
    return
  fi

  load_param /etc/metafile cell_id
  cell_id=$RESULT

  echo "cell_id=$cell_id"
  if [ -n "${CONFREG_URL}" ]; then
    echo "CONFREG_URL=${CONFREG_URL[@]}"
    for pair in ${CONFREG_URL[@]}
    do
      key=$( echo $pair | cut -d'=' -f1 )
      value=$( echo $pair | cut -d'=' -f2 )
      confreg_cell_or_datacenter=${key##*.}

      # compare case-insensitive
      lower_cellid=`echo "$cell_id" | tr -s '[:upper:]' '[:lower:]'`
      lower_confreg_cell_or_datacenter=`echo "$confreg_cell_or_datacenter" | tr -s '[:upper:]' '[:lower:]'`
      echo "lower_cellid=$lower_cellid"
      echo "confreg_cell_or_datacenter=$lower_confreg_cell_or_datacenter"
      if [ "$lower_cellid" == "$lower_confreg_cell_or_datacenter" ]; then
        echo "using confreg $value for cell_id: $cell_id"
        RESULT=$value
        return
      fi
    done
  fi

  load_param /etc/metafile datacenter_name
  datacenter_name=$RESULT

  echo "datacenter=$datacenter_name"
  if [ -n "${CONFREG_URL}" ]; then
      echo "CONFREG_URL=${CONFREG_URL[@]}"
      for pair in ${CONFREG_URL[@]}
      do
        key=$( echo $pair | cut -d'=' -f1 )
        value=$( echo $pair | cut -d'=' -f2 )
        confreg_cell_or_datacenter=${key##*.}

        # compare case-insensitive
        lower_datacenter=`echo "$datacenter_name" | tr -s '[:upper:]' '[:lower:]'`
        lower_confreg_cell_or_datacenter=`echo "$confreg_cell_or_datacenter" | tr -s '[:upper:]' '[:lower:]'`
        echo "lower_datacenter=$lower_datacenter"
        echo "confreg_cell_or_datacenter=$lower_confreg_cell_or_datacenter"
        if [ "$lower_datacenter" == "$lower_confreg_cell_or_datacenter" ]; then
          echo "using confreg $value for datacenter: $datacenter_name"
          RESULT=$value
          return
        fi
      done
    fi

  # can't find appropriate confreg url
  RESULT=""
}