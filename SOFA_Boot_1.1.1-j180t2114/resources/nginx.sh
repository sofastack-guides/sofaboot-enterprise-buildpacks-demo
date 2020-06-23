#!/bin/bash

if [ $# -lt 1 ]; then
    echo 'Usage: \$1:nginx conf file path'
    exit 1;
fi

CONF_PATH=$1

NGINX_HOME=/opt/software/nginx
echo "NGINX_HOME=$NGINX_HOME"

cd `dirname $0`/..
BASE=`pwd`
NGINX_PID=$BASE/nginx.pid

# if there's alipay tengine, use it first
if [ -d "$NGINX_HOME/bin" ]
then
    if [ ! -f "$NGINX_HOME/bin/t-alipay-tengine" ]
    then
        NGINX_COMMAND=$NGINX_HOME/bin/tengine
    else 
        NGINX_COMMAND=$NGINX_HOME/bin/t-alipay-tengine
    fi
# otherwise, use common tengine instead
else
    NGINX_COMMAND=$NGINX_HOME/sbin/nginx
fi

NGINX_COMMAND="$NGINX_COMMAND -c $CONF_PATH"

# kill previous nginx processes
$NGINX_COMMAND -s quit

# replace nginx_home, and cronolog home,
# because they depend on the environment
sed -i "s|@NGINX_HOME@|$NGINX_HOME|g" $CONF_PATH
if [ -z "$CRONOLOG_HOME" ];then
    CRONOLOG_HOME="/opt/software/cronolog"
    #CRONOLOG_HOME is not set, using default value
fi
echo "CRONOLOG_HOME=$CRONOLOG_HOME"
sed -i "s|@CRONOLOG_HOME@|$CRONOLOG_HOME|g" $CONF_PATH

#
# critical for configurations that use many file descriptors,
# such as mass vhosting, or a multithreaded server.
ULIMIT_MAX_FILES="ulimit -S -n `ulimit -H -n`"
# --------------------                              --------------------
# ||||||||||||||||||||   END CONFIGURATION SECTION  ||||||||||||||||||||

# Set the maximum number of file descriptors allowed per child process.
if [ "x$ULIMIT_MAX_FILES" != "x" ] ; then
    $ULIMIT_MAX_FILES
fi

echo "nginx command:$NGINX_COMMAND"
$NGINX_COMMAND
