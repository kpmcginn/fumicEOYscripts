#!/bin/bash 
#--------------------------------------------------------------------------------------------------------------
# Name: credDef.sh
# Desc: Bash shell that is sourced from the createNameRecord script. This script defines the credentials to 
#       use to access the desired as400 instance. Along with each set of credential is a variable named 'envir'
# 	The createNameRecord script uses this script to display to the user which environment is being accessed
#       to avoid confusion.
#
#==============================================================================================================
#  Version   Name      Date                                Description
#--------------------------------------------------------------------------------------------------------------
#   0.0      KPM     11/25/2014          Original Release
#--------------------------------------------------------------------------------------------------------------
#
# UNCOMMENT/COMMENT as needed the correct set of 4 lines of the credential
#
#ipDef='10.122.251.20'
#libDef='QS36F'
#usrDef='QSECOFR'
#usrPwd='abc1234'
#envir='DR Environment'
ipDef='192.168.2.10'
libDef='QS36F'
usrDef='QSECOFR'
usrPwd='set44now'
envir='Production Environment'
#---------------------------------- end of 'credDef.sh' script -------------------------
