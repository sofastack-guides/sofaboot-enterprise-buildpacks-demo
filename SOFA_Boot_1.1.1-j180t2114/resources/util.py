#!/usr/bin/env python
#
# Alipay.com Inc.

__author__ = 'xuanhong'

import sys
from xdeploy.util import logutil
from xdeploy.util import function_util

META_FILE = "/etc/metafile"
metafile_argvs = function_util.get_dict_from_file(META_FILE)

def filterBuildpackParam(paramArray):
    global META_FILE
    logutil.LOG_INFO(__file__, sys._getframe().f_code.co_name,str(sys._getframe().f_lineno), "args of filterBuildpackParam are: %s"%(paramArray))
    result = dict()
    
    logutil.LOG_INFO(__file__, sys._getframe().f_code.co_name,str(sys._getframe().f_lineno), "args in metafile are: %s"%(metafile_argvs))
    
    paramArrayCombineStr = ""
    for arg in paramArray:
        paramArrayCombineStr += (arg + " ")
    
    paramArrayCombineStr = paramArrayCombineStr[0:len(paramArrayCombineStr)-1]
    # paramArrayCombineStr = replaceTemplate(paramArrayCombineStr,"${ac.env.","}")

    formattedParam = paramArrayCombineStr.split(" ")
    oldParam = function_util.build_dict(formattedParam)
    # oldParam = setConfRegURL(oldParam)
    for k in oldParam: 
        if k.startswith("bp."):
            truncateKey = k[3:]
            if (truncateKey in result) == False:
                result[truncateKey] = oldParam[k]
        else:
            result[k] = oldParam[k]

    return result