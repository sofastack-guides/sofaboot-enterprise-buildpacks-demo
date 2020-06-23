#!/bin/bash

set_oom_score_adj() {
    local pid=$1
    if [[ -n $pid ]]; then
        echo | sudo -S bash -c "echo -500 > /proc/$pid/oom_score_adj" 2> /dev/null
        score_adj=$(cat /proc/$pid/oom_score_adj)
        echo "set oom_score_adj of $pid to -500"
        if [[ $score_adj -ne -500 ]]; then
            echo "but failed with /proc/$pid/oom_score_adj get $score_adj"
        fi
    fi
}

function parse_opts()
{
    # A POSIX variable
    OPTIND=1         # Reset in case getopts has been used previously in the shell.

    # Initialize our own variables:
    SYS_PROPS=""
    while getopts "hD:R:H:E:J:C:" opt; do
        case "$opt" in
        h|\?)
            echo "usage: deploy.sh -Dproperty"
            exit 0
            ;;
        D)  SYS_PROPS="-D$OPTARG ${SYS_PROPS}"
            ;;
        R)  APP_RUN=$OPTARG
            ;;
        J)  original_jar_dir=$OPTARG
            ;;
        H)  APP_HOME=$OPTARG
            ;;
        E)  ENV_VAR=$OPTARG
            ;;
        T)  TENANT_VAR=$OPTARG
            ;;
    	C)  CONFREG_URL=($OPTARG ${CONFREG_URL[@]})
            ;;
        esac
    done

    shift $((OPTIND-1))
    [ "$1" = "--" ] && shift
}

function move_static_resources()
{
    # priority : META/resources > resources > static > public

    # BOOT-INF/classes
    static_resources=$1
    # app-run
    target_dir=$2
    if [ -d $1/META/resources ]; then
        mv $1/META/resources $2/META/resources
        return
    elif [ -d $1/resources ]; then
        mv $1/resources $2/resources
        return
    elif [ -d $1/static ]; then
        mv $1/static $2/static
        return
    elif [ -d $1/public ]; then
        mv $1/public $2/public
        return
    else 
        echo "No Static Resources"
        return
    fi
}


if [ -z "$JAVA_HOME" ]; then
  echo "JAVA_HOME not set, exit"
  exit 1
fi

# get the real path
if [[ -L $0 ]]; then
    BIN_DIR=$(dirname $(readlink $0))
else
    BIN_DIR=$(dirname $(readlink -f $0))
fi

source $BIN_DIR/util.sh

# parse parameters
parse_opts $@

# check directories
if [ -z "$APP_RUN" ]; then
  APP_RUN=/home/admin/app-run
fi

if [ -z "$original_jar_dir" ]; then
  original_jar_dir=/home/admin/release/run
fi

if [ -z "$APP_HOME" ]; then
  APP_HOME=/home/admin
fi

echo "APP_HOME=${APP_HOME}"
echo "APP_RUN=${APP_RUN}"
echo "original_jar_dir=${original_jar_dir}"

# setup directories
LOG_ROOT=$APP_HOME/logs
mkdir -p $LOG_ROOT

rm -rf $APP_RUN
mkdir -p $APP_RUN

# spring-boot path middle default value
spring_boot_path_middle=BOOT-INF/classes

cd $original_jar_dir

jar_files=(`ls *.jar`)
if [ -n "$jar_files" ]; then
  # found jar, use first jar
  JAR_FILE=${jar_files[0]}
  jar_name=`basename $JAR_FILE`
  cd $APP_HOME

  JAR_FILE=${original_jar_dir}/${JAR_FILE}
  echo "JAR_FILE=$JAR_FILE"
  
  # get workspace name
  if [ -z "$ENV_VAR" ]; then
    load_param /etc/metafile workspace_name
    ENV_VAR=$RESULT
  fi

  if [ -z "$TENANT_VAR" ]; then
    load_param /etc/metafile tenant_name
    TENANT_VAR=$RESULT
  fi

  echo "spring.profiles.active=$ENV_VAR,${TENANT_VAR}_${ENV_VAR}"

  # copy the jar to app_run in sofa-lite2
  cp $JAR_FILE $APP_RUN

  # unzip jar, get JAVA_OPTS from java_opts files
  WORK_DIR=${APP_RUN}/${jar_name%.jar}
  # mkdir
  mkdir -p $WORK_DIR
  # unzip source file to workdir
  unzip -q $JAR_FILE -d $WORK_DIR
  # verify success or not
  exit_unzip_status=$?
  if [ "$exit_unzip_status" -eq "0" ]
  then
    # Do work when command exists on success
    echo "Using unzip command success!"
  else
    # change dir
    cd $WORK_DIR;
    jar -xf ${APP_RUN}/$jar_name;
    # change admin dir
    cd $APP_HOME
    echo "Using unzip command failed and using java command for unzipping!"
  fi

  # echo
  echo "Unziped Jar Directory=${WORK_DIR}"

  # static resources
  move_static_resources $WORK_DIR/${spring_boot_path_middle} ${APP_RUN}

  # get java opts
  get_java_opts $WORK_DIR/${spring_boot_path_middle}

  SYS_PROPS="$JAVA_OPTS $SYS_PROPS -Dspring.profiles.active=${ENV_VAR},${TENANT_VAR}_${ENV_VAR}"
  # get config from /etc/metafile
  get_confreg
  confregurl=$RESULT
  if [ -n "$confregurl" ]; then
    SYS_PROPS="$SYS_PROPS -Dcom.alipay.confreg.url=$confregurl"
  fi

  # get zone(cell) info
  load_param /etc/metafile cell_name
  CELL_NAME=$RESULT;
  # get datacenter info
  load_param /etc/metafile datacenter_name
  DATACENTER_NAME=$RESULT;
  if [ -n "$CELL_NAME" -a "$CELL_NAME" != "None" ]; then
    echo "cell_name=$CELL_NAME";
    SYS_PROPS="$SYS_PROPS -Dcom.alipay.ldc.zone=$CELL_NAME";
  else
    echo "No valid value cell_name found in /etc/metafile";
  fi
  if [ -n "$DATACENTER_NAME" -a "$DATACENTER_NAME" != "None" ]; then
    echo "datacenter_name=$DATACENTER_NAME";
    SYS_PROPS="$SYS_PROPS -Dcom.alipay.ldc.datacenter=$DATACENTER_NAME";
  else
    echo "No valid value datacenter_name found in /etc/metafile";
  fi

  propertiesPath=`find ${APP_RUN} -name "*application.properties*"`;
  echo "Current properties file $propertiesPath";
  load_param $propertiesPath add_dbmode_jvm_param
  ADD_DBMODE=$RESULT
  if [ -n "$ADD_DBMODE" -a "$ADD_DBMODE" == "true" ]; then
    echo "will add dbmode jvm param"
	load_param /etc/metafile workspace_name
    SYS_PROPS="$SYS_PROPS -Ddbmode=$RESULT";
  fi
  
  # echo java opts
  echo "SYS_PROPS : $SYS_PROPS"
  # run before hook
  run_hook before_appstart_hook ${WORK_DIR}/${spring_boot_path_middle}
  # run
  ( set_oom_score_adj $BASHPID; java $SYS_PROPS -jar ${APP_RUN}/$jar_name >> ${LOG_ROOT}/stdout.log 2>> ${LOG_ROOT}/stderr.log & )
  # run after hook
  run_hook after_appstart_hook ${WORK_DIR}/${spring_boot_path_middle}

  echo "deploy jar success, stdout:${LOG_ROOT}/stdout.log, stderr:${LOG_ROOT}/stderr.log"

  # start nginx, if conf exist
  if [ -f "$WORK_DIR/${spring_boot_path_middle}/tenginx-conf/tengine.conf" ]; then
    kill_nginxPro
    bash $BIN_DIR/nginx.sh $WORK_DIR/${spring_boot_path_middle}/tenginx-conf/tengine.conf
  fi
else
  echo "no jars under $original_jar_dir, deploy failed"
  exit 2
fi
