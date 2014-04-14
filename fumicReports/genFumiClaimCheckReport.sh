#!/bin/bash
#------------------------------------------------------------------
# Name: genFumiClaimCheckReport.sh
# Desc: Script to generate the claim check report. This
#       script has 1 optional argument. This allows for the passing
#       of the year for which to gen the report. By default, the
#       current year is used.
#
#       This report is derived from the clclchd AS400 database table.
#       This table is defined as the claims check header table. The
#       report process is such that the data is extracted from this table
#       filtering on the specified year of the report. The date is
#       extracted with minor formatting applied and written to the csv file.
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
baseFileName='/tmp/I_item_8-Claims_Checks'
baseYTDTitle='FUMI Claims Checks Issued '
reportTitle=
csvFileName=

# working filek
xFile="/tmp/outWF4.xxx"
tFile="/tmp/cleanWF4.out"

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
		reportTitle="${baseYTDTitle} in ${cent}${year}"
	elif [[ "$2" = '' ]]
	then
		reportTitle="${baseYTDTitle} in ${cent}${year}"
	fi
}


function generateResults
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
	db -db as400 -query \${ select '~'||cast(chckno as varchar(10))||'~'||substr(chclno,1,4)||'-'||substr(chclno,5,5)||'~'|| chpyty ||'~'||cast(chckam as numeric(11,2)) ||'~'||chckcy||case when  chckdt < 1000 then '00-0'||substr(chckdt,1,1)||'-'||substr(chckdt,2,2) when chckdt < 10000 then '00-'||substr(chckdt,1,2)||'-'||substr(chckdt,3,2) when chckdt< 100000 then '0'||substr(chckdt,1,1)||'-'||substr(chckdt,2,2)||'-'||substr(chckdt,4,2) else substr(chckdt,1,2)||'-'||substr(chckdt,3,2)||'-'||substr(chckdt,5,2) end||'~'||chfscy||case when chfspd < 10 then '0'||chfspd||'-'||'01' when chfspd < 100 then chfspd||'-'||'01' when chfspd <1000 then substr(chfspd,1,2)||'-0'||substr(chfspd,3,1) else substr(chfspd,1,2)||'-'||substr(chfspd,3,2) end ||'~'||chajno||'~'||chpay1||'~'|| chpay2||'~'||chadd1||'~'||chadd2||'~'||chcity||'~'||chstat||'~'||chzip||'~'||chname as Name from CLCLCHD where chckcy= '$cent' and '$year' = case when chckdt < 10000 then 0 when chckdt < 100000 then '0'||substr(chckdt,1,1) else  substr(chckdt,1,2)  end and '$month' >= cast(case when chckdt < 1000 then substr(chckdt,1,1) when chckdt < 10000 then substr(chckdt,1,2) when chckdt < 100000 then substr(chckdt,2,2) else substr(chckdt,3,2) end as integer) order by case when chckdt< 1000 then substr(chckdt,1,1) when chckdt < 10000 then substr(chckdt,1,2) when chckdt < 100000 then substr(chckdt,2,2) else substr(chckdt,3,2) end }$  $ipDef $libDef $usrDef $usrPwd
EOF
}

function addReportHeader
{
	echo " " > "$csvFileName"

	if [[ "$reportTitle" != "" ]]
	then
		echo ",,,$reportTitle" >> "$csvFileName"
		echo "---,---,---,---,---,---,---,---,---,---,---,---,---,---,---" >> "$csvFileName"
	fi
}

# read the outoyt and properly format
function postProcess
{
	# Removal leding non-printable characters
	tr -cd '\11\12\15\40-\176' <"$xFile">"$tFile"
	
	# Add the column headers
	echo "Check #,Claim #, Type, Amount, Date, Fisc Prd, Adjustr,Claimant,Address,Address,Address,City, State,Zip, Name" >> "$csvFileName"

	oldIFs=IFS
	IFS='~'
	while read dummy var1 var2 var3 var4 var5 var6 var7 var8 var9 var10 var11 var12 var13 var14 var15 var16 var17 var18
	do
		# Ignore blank lines
		if [[ "$var1" = "" ]]
		then
			continue
		fi

		# if zip is undefined it will be zero. set to blank
		if [[ "$var14" = "0" ]]
		then
			var14=""
		fi

		nextRow="$var1,$var2,$var3,$var4,$var5,$var6,$var7,$var8,$var9, $var10, $var11, $var12, $var13, $var14, $var15"

		if [[ "$nextRow" != "" ]]
		then
			echo "$nextRow"
		fi
	done < "$tFile">>"$csvFileName"
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
