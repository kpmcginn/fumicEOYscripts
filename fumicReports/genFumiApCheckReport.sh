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
baseFileName='/tmp/I_item_8-FUMI_AP_Checks'
baseYTDTitle='FUMI A/P Vendor Checks YTD'
reportTitle=
csvFileName=

# working filek
xFile="/tmp/outWF3.xxx"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh

# days in each month
monthList=(0 31 29 31 30 31 30 31 31 30 31 30 31)

# clean up old files
function cleanFiles
{
        cleanOnExit

        if [[ -f "$csvFileName" ]]
        then
                rm -f "$csvFileName"
        fi
}

function cleanOnExit
{
        if [[ -f "$xFile" ]]
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
}

# Create the file based on the passed parameters
function createFileName
{
	if [[ "$1" = '' ]] && [[ "$2" = '' ]]
	then
		csvFileName="${baseFileName}_YTD_${cent}${year}.csv"
	elif [[ "$2" = '' ]]
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
	db -db as400 -query \${ select apficy||case when apfisc < 10 then '00-01' when apfisc < 100 then '00-'||substr(apfisc,1,2) when apfisc < 1000 then '0'||substr(apfisc,1,1)||'-'||substr(apfisc,2,2) when apfisc < 10000 then substr(apfisc,1,2)||'-'||substr(apfisc,3,2)  end as "Fisc Prd", apckcy||case when  apckdt < 1000 then '00-0'||substr(apckdt,1,1)||'-'||substr(apckdt,2,2) when apckdt < 10000 then '00-'||substr(apckdt,1,2)||'-'||substr(apckdt,3,2) when apckdt < 100000 then '0'||substr(apckdt,1,1)||'-'||substr(apckdt,2,2)||'-'||substr(apckdt,4,2) else substr(apckdt,1,2)||'-'||substr(apckdt,3,2)||'-'||substr(apckdt,5,2) end as Date, apckno as "Check #",apvevo as Vendor, cast(apckam as numeric(11,2)) as Amount, apficy as "Fisc Prod", apckcy as "Ck Cy", apckdt as "Ck Date", appaye as Payee from APCHECK where apficy = '$cent' and '$year' = case when apfisc < 10 then 0 when apfisc < 100 then 0 when apfisc < 1000 then substr(apfisc,1,1) when apfisc < 10000 then substr(apfisc,1,2)  end and '$month' >= case when apfisc < 10 then 1 when apfisc < 100 then substr(apfisc,1,2) when apfisc < 1000 then substr(apfisc,2,2) when apfisc < 10000 then substr(apfisc,3,2)  end order by case when apfisc < 10 then 1 when apfisc < 100 then substr(apfisc,1,2) when apfisc < 1000 then substr(apfisc,2,2) when apfisc < 10000 then substr(apfisc,3,2)  end }$ $ipDef $libDef $usrDef $usrPwd
EOF
}

function addReportHeader
{
	echo " " > "$csvFileName"
	echo ",,,$reportTitle" >> "$csvFileName"
	echo "---,---,---,---,---,---,---,---,---" >> "$csvFileName"
}

# read the outoyt and properly format
function postProcess
{
	while read var1 var2 var3 var4 var5 var6 var7 var8 var9 var10 var11 var12 var13 var14 var15
	do
		# Ignore blank lines
		if [[ "$var1" = "" ]]
		then
			continue
		fi

		# The first line is put into the csv file ase the header
		if [ "$headCnt" -eq 0 ]
		then
			nextRow="$var1 $var2,$var3,$var4 $var5,$var6,$var7,$var8 $var9, $var10 $var11, $var12 $var13, $var14 $var15"
		else
			mon="$(echo $var5/100.00|bc -l)"
			nextRow="$var1,$var2,$var3,$var4,$mon,$var6,$var7,$var8,$var9 $var10 $var11 $var12 $var13 $var14 $var15"
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
