#!/bin/bash
#
#
#
declare -i day=31
declare -i month=12
declare -i cent=
declare -i year=
declare -i lastYear=0
declare -i nextYear=0
declare -i temp=
declare -i headCnt=0
declare -i factor=0
declare -i isSubro=0
declare -i isStar=0
declare -i isMB=0
declare -i thisYear=0
declare -i var3
declare -i var4
baseFileName='/tmp/ListOf2013Claims'
baseYTDTitle='N/A '
reportTitle=
csvFileName=

# working file
xFile="/tmp/out.xxx"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh

# clean up old files
function cleanFiles
{
	if [[ -f "$xFile" ]]
	then
		rm -f "$xFile"
	fi

	if [[ -f "$csvFileName" ]]
	then
		rm -f "$csvFileName"
	fi
}

# set the range limits of the report
function setLimits
{
	# If nothing passed use current century and date
	if [[ "$1" = '' ]] 
	then
		cent=$(date +"%C")
		year=$(date +"%y")

	# If year is passed assume "yyyy" and parse
	else
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
	fi
	lastYear="$(echo $year - 1|bc -l)"
	lastYear="$(echo $cent*100+$lastYear|bc -l)"
	thisYear="$(echo $cent*100+$year|bc -l)"
	nextYear="$(echo $cent*100+$year+1|bc -l)"
}

# Create the file based on the passed parameters
function createFileName
{
	csvFileName="${baseFileName}_${month}_${day}_${cent}${year}.csv"
}

function createReportTitle 
{
	reportTitle="${baseYTDTitle} ${month}/${day}/${cent}${year}"
}
# query the CLCLAIMS and CLCLHIST tables for report elements
function generateResults
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
db -db as400 -query \${ select aa.clno, clrdmm||'/'||clrddd||'/'||clrdcy||clrdyy   from clclaims aa where ((((clopcl='O' and clrdcy=20 and clrdyy<=13) or (clopcl='O' and clrdcy=19))or (aa.clrdcy =20 and clrdyy=13)) or (((clopcl in ('C','D') and aa.clrdcy=20 and clrdyy in (13,14)) or (clopcl='O' and aa.clrdcy=20 and clrdyy =14))and ((cllscy=19) or (cllscy=20 and cllsyy<=13)))) and aa.clno not like '2014%' and clrdyy='14' order by 1  }$ $ipDef $libDef $usrDef $usrPwd
EOF
}

function addReportHeader
{
        echo " " > "$csvFileName"

        if [[ "$reportTitle" != "" ]]
        then
                echo ",,,$reportTitle" >> "$csvFileName"
                echo ",,,------------------------------------------------" >> "$csvFileName"
        fi
}

# read the output and properly format
#
# Explanation of variables
#  var0  - claim number; used for sorting
#
function postProcess
{
        # Loop and read each row of the result set from the temp file
        while read var0 var1
        do
                # Ignore blank lines
                if [[ "$var1" = "" ]]
                then
                        continue
		fi

                # First row returned is header info.
                if [ "$headCnt" -eq 0 ]
                then
                        nextRow="Claim #,Last Update"
                else

			# Define next row in CSV format.
			nextRow="$var0,$var1"
		fi

		# If not a blank line add to the report
		if [[ "$nextRow" != "" ]]
		then
			echo "$nextRow"
		fi
		((headCnt++))

	done < "$xFile">>"$csvFileName"
}

#-----------------------------------------------------------
# MAIN
#-----------------------------------------------------------
setLimits "$1" "$2"
createFileName "$1" "$2"
cleanFiles
createReportTitle "$1" "$2"
generateResults
addReportHeader
postProcess
echo "Results can be found in: $csvFileName"

#
#----- genClaimsRegister.sh script ------
