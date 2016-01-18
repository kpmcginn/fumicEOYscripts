#!/bin/bash
#------------------------------------------------------------------
# Name: genFumiApCheckReport.sh
# Desc: Script to generate the AP check report. This
#       script has 1 optional argument. This allows for the passing
#       of the year for which to gen the report. By default, the
#       current year is used.
#
#       This report is derived from the apcheck AS400 database table.
#	This table is defined as the AP check file for auditors. The
# 	report process is such that the data is extracted from this table 
#	filtering on the specified year of the report. The date is 
#	extracted with minor formatting applied and written to the cvs file.
#
#===================================================================
#  Version   Name      Date              Description
#------------------------------------------------------------------
#   0.0      KPM     04/15/2014          Original Release
#------------------------------------------------------------------

#
declare -i month=
declare -i cent=
declare -i year=
declare -i temp=
declare -i headCnt=0
#declare -i var5=
baseFileName='/tmp/apCheckReport'
baseYTDTitle='FUMI A/P Vendor Checks YTD'
reportTitle=
csvFileName=

# working filek
xFile="/tmp/outWF3.xxx"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh

# days in each month - set feb to init 
monthList=(0 31 0 31 30 31 30 31 31 30 31 30 31)

# clean up old files
function cleanFiles
{
        cleanOnExit

        if [ -f "$csvFileName" ]
        then
                rm -f "$csvFileName"
        fi
}

function cleanOnExit
{
        if [ -f "$xFile" ]
        then
                rm -f "$xFile"
        fi
}

# set the range limits of the report
function setLimits
{
	if [[ "$1" = '' ]] && [[ "$2" = '' ]]
	then
		cent=$(date +"%C")
		year=$(date +"%y")
		month=$(date +"%m")
	elif [[ "$2" = '' ]]
	then
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
		month=12
	else
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
		month=$2
	fi
	#echo "Cent: $cent year: $year month: $month"
	thisYear="$cent$year"

	# Set days in Feb based on year
	monthList[2]=$(( $(cal $thisYear |egrep "^[ 0-9][0-9]| [ 0-9][0-9]$" |wc -w)- 337 ))
}

# Create the file based on the passed parameters
function createFileName
{
	if [[ "$2" = '' ]]
	then
		csvFileName="${baseFileName}_YTD_${cent}${year}.csv"
	else
		csvFileName="${baseFileName}_"

		if [ "$month" -lt 10 ]
		then
			csvFileName="${csvFileName}0"
		fi
		csvFileName="${csvFileName}${month}_${monthList[$month]}_${cent}${year}.csv"
	fi
}

function createReportTitle 
{

	if [[ "$1" = '' ]] && [[ "$2" = '' ]]
	then
		reportTitle="${baseYTDTitle}_YTD_${cent}${year}"
	elif [[ "$2" = '' ]]
	then
		reportTitle="${baseYTDTitle}_YTD_${cent}${year}"
	else
		reportTitle="${baseYTDTitle}_"

		if [ "$month" -lt 10 ]
		then
			reportTitle="${reportTitle}0"
		fi
		reportTitle="${reportTitle}${month}_${monthList[$month]}_${cent}${year}"
	fi
}


function generateResults
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
	db -db as400 -query \${  select substr(F00002,38,4)||'-'||substr(F00002,42,2) as "fisc_prd",substr(F00002,44,4)||'-'||substr(F00002,48,2)||'-'||substr(F00002,50,2) as date,substr(F00002,2,8) as vendor,substr(trim(K00001),4) as chkNo,substr(hex(F00002),25,11) as amount,substr(F00002,38,2) as FiscCy,substr(F00002,40,4) as "FscPrd",substr(F00002,44,2) as "CkCy",substr(F00002,46,6) as CkDate,substr(F00002,53,45) as payee from "AP.ACHK" where substr(F00002,44,4)='$thisYear' and cast(substr(F00002,48,2) as numeric(11,0)) <= $month order by 2
 }$ $ipDef $libDef $usrDef $usrPwd
EOF
}

function addReportHeader
{
	echo " " > "$csvFileName"
	echo ",,,$reportTitle" >> "$csvFileName"
	echo "---,---,---,---,---,---,---,---,---" >> "$csvFileName"
}

# read the output and properly format
function postProcess
{
	while read var1 var2 var3 var4 var5 var6 var7 var8 var9 name1 name2 name3 name4
	do
		# Ignore blank lines
		if [[ "$var1" = "" ]]
		then
			continue
		fi

		# The first line is put into the csv file ase the header
		if [ "$headCnt" -eq 0 ]
		then
			nextRow="Fisc Prd,Date,Vendor,Check #,Amount,Fisc Cy, Fisc Prd, Ck Cy, Ck Date, PAYEE"
		else
			name="$name1 $name2 $name3 $name4"
			mon="$(echo $var5/100.00|bc -l)"
			nextRow="$var1,$var2,$var3,$var4,$mon,$var6,$var7,$var8,$var9,\"$name\""
		fi
		((headCnt++))

		if [[ "$nextRow" != "" ]]
		then
			echo "$nextRow"
		fi
	done < "$xFile">>"$csvFileName"
}

setLimits "$1" "$2"
createFileName "$1" "$2"
cleanFiles
createReportTitle "$1" "$2"
generateResults
addReportHeader
postProcess
echo "Results can be found in: $csvFileName"

# clean up on error or exit
trap cleanOnExit EXIT SIGINT
trap cleanFiles  ERR SIGTERM

#
#------------------------- end of script ----------------------------
