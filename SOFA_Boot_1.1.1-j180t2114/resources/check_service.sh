#!/bin/bash

function simplify_path {
    local path=$1
    local new_path=${path//\/\//\/}
    while [ "$path" != "$new_path" ]; do
        path=$new_path
        new_path=${new_path//\/\//\/}
    done
    echo $new_path
}

function convert_yml2properties {
   local s='[[:space:]]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\(.*\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\(.*\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1);
      vname[indent] = $2;
      for (i in vname) {
        if (i+0 > indent && vname[i] != "") {
          delete vname[i]
        }
      }
      if (length($3) > 0) {
          vn="";
          for (i=0; i<indent; i++) {
            if (vname[i] != "")
              vn=(vn)(vname[i])(".")
          }
          printf("%s%s=%s\n", vn, $2, $3);
      }
   }'
}

function getSOFABoot2HealthCheckUrl()
{
    applicationPropertiesFile=$1;

    # 默认健康检查端口
    HEALTHCHECK_PORT="8080";

    # 获取配置 server.port
    load_param "$applicationPropertiesFile" server.port
    serverPort=$RESULT

    # 获取配置 management.port
    load_param "$applicationPropertiesFile" management.port
    managementPort=$RESULT

    if [ -z "$serverPort" ]; then
        serverPort="8080";
    fi

    if [ -z "$managementPort" ]; then
        managementPort=$serverPort
    fi

    # 最终的端口值由 managementPort 决定
    HEALTHCHECK_PORT=$managementPort

    if [ ! -z "$HEALTH_CHECK_PORT" ]; then
        HEALTHCHECK_PORT=$HEALTH_CHECK_PORT
    fi

    # 默认健康检查根路径
    HEALTHCHECK_CONTEXT_PATH=""

    # 获取应用的 contextPath
    load_param "$applicationPropertiesFile" server.context-path
    contextPath=$RESULT

    if [ -z "$contextPath" ]; then
        contextPath="/"
    fi

    # 获取 server.servlet-path 配置
    load_param "$applicationPropertiesFile" server.servlet-path
    servletPath=$RESULT

    if [ -z servletPath ]; then
        servletPath="/"
    fi

    # 获取endpoint basePath
    load_param "$applicationPropertiesFile" management.context-path
    basePath=$RESULT

    if [ -z "$basePath" ]; then
        basePath="/"
    fi

    if [ "$managementPort" -eq "$serverPort" ]; then
        HEALTHCHECK_CONTEXT_PATH="$contextPath$servletPath$basePath"
    else
        HEALTHCHECK_CONTEXT_PATH="$basePath"
    fi

    #  return result
    SOFABoot_HEALTH_URL="http://localhost:$(simplify_path $HEALTHCHECK_PORT/$HEALTHCHECK_CONTEXT_PATH/health/readiness)"
}

function getSOFABoot3HealthCheckUrl()
{
    applicationPropertiesFile=$1;

    # 默认健康检查端口
    HEALTHCHECK_PORT="8080";

    # 获取配置 server.port
    load_param "$applicationPropertiesFile" server.port
    serverPort=$RESULT

    # 获取配置 management.server.port
    load_param "$applicationPropertiesFile" management.server.port
    managementPort=$RESULT

    if [ -z "$serverPort" ]; then
        serverPort="8080";
    fi

    if [ -z "$managementPort" ]; then
        managementPort=$serverPort
    fi

    # 最终的端口值由 managementPort 决定
    HEALTHCHECK_PORT=$managementPort

    if [ ! -z "$HEALTH_CHECK_PORT" ]; then
        HEALTHCHECK_PORT=$HEALTH_CHECK_PORT
    fi

    # 默认健康检查根路径
    HEALTHCHECK_CONTEXT_PATH=""

    # 获取 server.servlet.context-path 设置
    load_param "$applicationPropertiesFile" server.servlet.context-path
    contextPath=$RESULT

    if [ -z "$contextPath" ]; then
        contextPath="/"
    fi

    # 获取 server.servlet.path 配置
    load_param "$applicationPropertiesFile" server.servlet.path
    servletPath=$RESULT

    if [ -z servletPath ]; then
        servletPath="/"
    fi


    # 获取 management.server.servlet.context-path 设置
    load_param "$applicationPropertiesFile" management.server.servlet.context-path
    management_contextPath=$RESULT

    if [ -z "$management_contextPath" ]; then
        management_contextPath="/"
    fi

    # 获取endpoint basePath
    load_param "$applicationPropertiesFile" management.endpoints.web.base-path
    basePath=$RESULT

    if [ -z "$basePath" ]; then
        basePath="/actuator"
    fi


    if [ "$managementPort" -eq "$serverPort" ]; then
        HEALTHCHECK_CONTEXT_PATH="$contextPath$servletPath$basePath"
    else
        HEALTHCHECK_CONTEXT_PATH="$management_contextPath$basePath"
    fi

    #  return result
    SOFABoot_HEALTH_URL="http://localhost:$(simplify_path $HEALTHCHECK_PORT$HEALTHCHECK_CONTEXT_PATH/readiness)";
}

# run mode: jar -jar X.jar
ps aux|grep java | grep "\-jar"
STATUS=$?
if [ "$STATUS" != "0" ]; then
   echo "Exiting $STATUS and No Java Process Exists in Check Service Stage! Check Logs in VM Please!"
   exit $STATUS
fi

# get the real path
if [[ -L $0 ]]; then
    BIN_DIR=$(dirname $(readlink $0))
else
    BIN_DIR=$(dirname $(readlink -f $0))
fi
source $BIN_DIR/util.sh
# echo
echo "Bin Directory=$BIN_DIR"

APP_RUN=/home/admin/app-run
if [ -n "$1" ]; then
    APP_RUN=$1
fi
echo "APP_RUN=$APP_RUN"

cd $APP_RUN
JARS=(`ls *.jar`)
if [ -z "$JARS" ]; then
  echo "no jars under $APP_RUN, check service failed!"
  exit 1
fi

currPath=`pwd`;
echo "Current Work Path  $currPath";

# compatible for have healthcheck and no
healthcheckFile=`find $currPath -name "*healthcheck-sofa-boot-starter*"`;
if [ -z "$healthcheckFile" ]; then
    echo "No dependency com.alipay.sofa:healthcheck-sofa-boot-starter found,so healthcheck ok!"
    exit 0;
else
    echo "Dependency com.alipay.sofa:healthcheck-sofa-boot-starter found,so start healthcheck!"
fi

rm -rf $APP_RUN/application.properties
propertiesPath=`find $currPath -name "*application.properties*"`;

if [ -n "$propertiesPath" ]; then
	echo "Current properties file $propertiesPath";
else
	echo "Cannot find application.properties, fall back to application.yml"
	yml_path=$(find $currPath -name "*application.yml*")
	propertiesPath="$APP_RUN/application.properties"
	echo "Converting $yml_path to $propertiesPath"
	convert_yml2properties $yml_path > $propertiesPath
fi

# compatible for SOFABoot 2.X or 3.X
springBootFile=`find $currPath -name "*spring-boot-2.*"`;
if [ -z "$springBootFile" ]; then
    echo "Current SOFABoot version is 2.X";
    getSOFABoot2HealthCheckUrl $propertiesPath
    HEALTH_URL=$SOFABoot_HEALTH_URL;
else
    echo "Current SOFABoot version is 3.X";
    getSOFABoot3HealthCheckUrl $propertiesPath
    HEALTH_URL=$SOFABoot_HEALTH_URL;
fi


HEALTH_CHECK_COMMOND="curl -s --connect-timeout 3 --max-time 5 ${HEALTH_URL}"

echo "        -- HealthCheck URL : ${HEALTH_URL}"
#success:0;failure:1;timeout:2,and default value is failure=1
status=1
#default 90s
times=90
if [ -n "$2" ]; then
	echo "Setting health check timeout to $2"
	times=$2
fi
echo "Health check timeout is $times"

for num in $(seq $times); do
	sleep 1
	COSTTIME=$(($times - $num ))

	HEALTH_CHECK_CODE=`${HEALTH_CHECK_COMMOND} -o /dev/null -w %{http_code}`
#	reference : https://docs.spring.io/spring-boot/docs/current/reference/html/production-ready-monitoring.html#production-ready-health-access-restrictions
	if [ "$HEALTH_CHECK_CODE" == "200" ]; then
	    #success
		status=0;
		break;
    elif [ "$HEALTH_CHECK_CODE" == "503" ] ; then
        echo -n -e  "\r        -- HealthCheck Cost Time `expr $num` seconds."
        # failure
        status=1;
        break;
	else
	    # starting
		# echo -n -e  "\r        -- HealthCheck Remaining Time `expr $COSTTIME` seconds."
		status=2;
	fi
done

SOFA_BOOT_HEALTH_CHECK_RESULT="SUCCESS";

if [ $status -eq 1 ]; then
    echo "        -- HealthCheck Failed.-- Current Server Responded Http Code ${HEALTH_CHECK_CODE}"
    SOFA_BOOT_HEALTH_CHECK_RESULT=`${HEALTH_CHECK_COMMOND}`;
    # paas echo check:failure
    echo -e "Health Check Result \n$SOFA_BOOT_HEALTH_CHECK_RESULT"
    exit 1;
fi

if [ $status -eq 2 ]; then
    SOFA_BOOT_HEALTH_CHECK_RESULT="        -- HealthCheck Failed. Could Not Connect to ${HEALTH_URL}.HealthCheck ${times} Seconds Timeout!";
    # paas echo check failure:timeout
    echo -e "Health Check Result \n$SOFA_BOOT_HEALTH_CHECK_RESULT";
    exit 2;
fi

# success
echo -e "        -- Health Check Result = $SOFA_BOOT_HEALTH_CHECK_RESULT";

exit 0