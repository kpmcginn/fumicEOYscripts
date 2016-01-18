#!/bin/bash
#----------------------------------------------------------------------------------------
# Name: genOutStandingReserve.sh
# Desc: The report will include information on Open Claims or claims closed in the year
#       of the report. The year of the report is the current year or the year passed to
#       this script as a parameter in the format of YYYY. 
#
#       The script is based on the claims table - CLCLAIMS. The column 'clopcl' in this
#       table indicates if the claim is open, closed, or deleted ('O','C','D'). The deleted
#       claims are filtered out. If the status is open, the claim is included in this 
#       report. If the status is closed and the column 'clclcy' (claim closed century) and
#       column 'clclyy' (claim closed year) match the century and year of this report
#       the claim is added to the report.
#
#===================================================================
#  Version   Name      Date              Description
#------------------------------------------------------------------
#   0.0      KPM     04/15/2014          Original Release
#------------------------------------------------------------------

declare -i day=31
declare -i month=12
declare -i cent=
declare -i year=
declare -i temp=
declare -i headCnt=0
declare -i factor=0
declare -i rowID=0
declare -A results
declare -A sumResults
declare -i nextCnt=0
declare -i index=0
declare -i subIndex=0
declare -i counter=0
baseFileName='/tmp/outstandingReserve_'
baseYTDTitle='Legal/Adjustor Outstanding Reserve as of'
reportTitle=
csvFileName=
lastClaim=

# working filek
xFile="/tmp/outWF7.xxx"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh

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
	if [[ "$1" = '' ]] 
	then
		cent=$(date +"%C")
		year=$(date +"%y")
	else
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
	fi
}

# Create the file based on the passed parameters
function createFileName
{
	csvFileName="${baseFileName}${month}_${day}_${cent}${year}.csv"
}

function createReportTitle 
{
	reportTitle="${baseYTDTitle} ${month}/${day}/${cent}${year}"
}

# grab claim data. Filter on open claims
function generateResults
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
	db -db as400 -query \${ select aa.clno as "Claim Number", (select coalesce(cast(round(sum(bb.rscham),0) as numeric(11,2)),0) from CLRESDT bb where aa.clno = bb.rsclno and bb.RSRVTP in ('A','L') and rsdtch like'${year}%' group by bb.RSCLNO) as totRes, cast(cllscy as numeric(11,0)) as lossCY,cast(cllsyy as numeric(11,0)) as lossYY,cast(clplin as numeric(11,0)) as line,cast(cllgfe as numeric(11,0)) as actuals,cast(aa.cllgex as numeric(11,0)) as altActuals,(select coalesce(cast(round(sum(chckam),0) as numeric(11,0)),0) from clclchd where chvoid='N' and chpyty in ('A','L') and chckdt like '${year}%' and chclno=aa.clno) as missing,aa.clopcl, cast(clclyy as numeric(11,0))  from CLCLAIMS aa where cast(aa.CLRDYY as numeric(8,0))='$year' and ((cast(aa.clclyy as numeric(8,0)) = '$year' and cast(aa.clclcy as numeric(8,0))> 0 and aa.clopcl = 'C') or aa.clopcl = 'O')   order by 1 }$ $ipDef $libDef $usrDef $usrPwd
EOF
}

# add the header to the report
function addReportHeader
{
	echo " " > "$csvFileName"
	echo ",,,$reportTitle" >> "$csvFileName"
	echo ",,,------------------------------------------------------------" >> "$csvFileName"
}

# read the output and properly format
function postProcess
{
	# Init sums to zero
	totRes=0
	totOut=0
	totPaid=0
	var6=0

	# load the results into an array for processing
	while read var1 _var6 var9 var10 var11 _var13 _var14 _var15 claimStatus claimCloseDate
	do
		# Ignore blank lines
		if [[ "$var1" = "" ]]
		then
			continue
		fi

		# First line read; ignore and add report header
		if [ "$headCnt" -eq 0 ]
		then
			echo "Claim Number,Reserve,Paid,Outstanding, Loss Year, Line"
			echo "---,---,---,---,---,---"
		else
			# Even with the coalesce, the $_var6 will come back with null as
			# '>Í%%'. If this var is all zeros or null just handle as zero
			if [[ "$_var6" != ">Í%%" ]] && [[ "$_var6" != "0000000000000" ]]
			then
				# If the last character is an alpha character remove it.
				# Removing last character means the number needs to be
				# multiplied by 10; set load factor to 10
				if [[ "$(echo $_var6|sed 's/[^0-9,^}]*//g')" != "$_var6" ]]
				then
					var6=$(echo $_var6|sed 's/[^0-9,^}]*//g')
					factor=10

				# a last char of '}' indicates negative number. Remove
				# last char and set load factor to -10
				elif [[ "${_var6%\}}" != "$_var6"  ]]
				then
					var6=${_var6%\}}
					factor=-10

				# For positive number with no "noise" set value directlly
				# and factor to 100 to account to 2 place trailing decimal
				else
					var6=$_var6
					factor=100
				fi

				# Perform math in 2 stages; removes leading zeros which
				# BSH would other otherwise interpret as octal
				var6="$(echo $var6* 1|bc -l)"
				var6="$(echo $var6/$factor|bc -l)"

			# By default the reserve value summation is zero
			else
				var6="$(echo 0.0|bc -l)"
			fi

			# convert loss century to integer
			if [[ ${_var13%\}} != "$_var13"  ]]
			then
				var13=${_var13%\}}
				var13="$(echo $var13* -10|bc -l)"
			else
				var13="$(echo $_var13* 1|bc -l)"
			fi

			# convert loss year to integer
			if [[ ${_var14%\}} != "$_var14"  ]]
			then
				var14=${_var14%\}}
				var14="$(echo $var14* -10|bc -l)"
			else
				var14="$(echo $_var14* 1|bc -l)"
			fi

			# Convert the payments to numeric
			if [[ ${_var15%\}} != "$_var15"  ]]
			then
				var15=${_var15%\}}
				var15="$(echo $var15* -1|bc -l)"
			else
				var15="$(echo $_var15* 1|bc -l)"
			fi
				
			# Convert the loss year to 2 char string
			if [ "$var10" -lt 10 ]
			then
				lossYY="0$(echo $var10|bc -l)"
			else
				lossYY="$(echo $var10|bc -l)"
			fi

			# convert loss year and line to integer
			lossCY="$(echo $var9|bc -l)"
			line="$(echo $var11|bc -l)"
				
			# and otustanding amounts.
			reserve=$var6

			# If the last paid was this year use value 
			# otherwise 0
			paid=$var15

			outstanding="$(echo $reserve-$paid|bc -l)"

			# Keep a running total of each column
			totRes="$(echo $totRes+$reserve |bc -l)"
			totOut="$(echo $totOut+$outstanding |bc -l)"
			totPaid="$(echo $totPaid+$paid |bc -l)"

			# Dump this row to the CSV file
			if [[ "$reserve" != "0" ]] || [[ "$paid" != "0" ]]
			then
				echo "$var1, $reserve, $paid, $outstanding, $lossCY$lossYY, $line"
			fi
		fi
		((headCnt++))
	done < "$xFile" >>"$csvFileName"
	#done < "$xFile" 

	# Sum the columns
	echo ",---,---,---">>"$csvFileName"
	echo ",$totRes,$totPaid,$totOut">>"$csvFileName"
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
