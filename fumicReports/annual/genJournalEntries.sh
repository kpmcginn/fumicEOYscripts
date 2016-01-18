#!/bin/bash
#--------------------------------------------------------------------------------------------------------------
# Name: genJournalEntries.sh
# Desc: Script to generate the Manual Journal Entries report. This 
#       script has 1 optional argument. This allows for the passing
#       of the year for which to gen the report. By default, the 
#       current year is used.
#
#	This report is derived from the GL.JRNL table in the as400
#       database. Being that this is an old table, there is no meta-
#       data definition available for this table. Because of that 
#       several columns of data are returned in 2 results set
#	columns; K00001 and F00002. For the textual columns of the
#       report, these columns are parsed as substrings. To derive the
#       credit and debit values, F00002 is converted to HEX first.
#       The resultant credit/debit values are derived as substrings
#       of these hex representations.
#
#	The second column of the report 'Ref#' contains leading zeros
#	Being that this is an identifier and to maintain the leading
#	zeros, each of these column values is encased as ="xx". This
#	format prevents Excel from trimming the leading zeros.
#
#===================================================================
#  Version   Name      Date              Description
#------------------------------------------------------------------
#   0.0      KPM     02/25/2014          Original Release
#------------------------------------------------------------------

# declartions
declare -i cent=
declare -i year=
declare -i temp=
declare -i headCnt=0
declare -i factor=0
#
baseFileName='/tmp/manualJournalEntries'
baseYTDTitle='FUMI Manual Journal Entries in '
reportTitle=
csvFileName=

# working file
xFile="/tmp/outWF6.xxx"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh

#-----------------------------------------------------------------
# FUNCTIONS
#-----------------------------------------------------------------
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
	# If not date passed; assume this year
	if [[ "$1" = '' ]] 
	then
		cent=$(date +"%C")
		year=$(date +"%y")

	# Parse the passed date
	else
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
	fi
	thisYear="$cent$year"
}

# Create the file based on the passed parameters
function createFileName
{
	csvFileName="${baseFileName}_${cent}${year}.csv"
}

function createReportTitle 
{

	reportTitle="${baseYTDTitle} ${cent}${year}"
}

# parse out the contents of the "GL.JRNL" table. Because of spaces
# in comment field, pipe delimit results to avoid issues with spaces
function generateResults
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
	db -db as400 -query \${ select trim(K00001)||'|'||substr(trim(F00002), length(trim(F00002))-5,4)||'-'||substr(trim(F00002), length(trim(F00002))-1,2)||'|'|| trim(substr(trim(F00002),length(trim(F00002))-40,30))||'|'||substr(trim(F00002),1,15)||'|'|| trim(substr(hex(F00002),32,11))||'|'||trim(substr(hex(F00002),44,11))  from "GL.JRNL" where K00001 like 'JV %' and F00002 like '%$thisYear%' and K00001 not like '%-%' and K00001 not like '%\_%' order by substr(trim(F00002), length(trim(F00002))-1,2) asc }$ $ipDef $libDef $usrDef $usrPwd
EOF
}

function addReportHeader
{
	echo " " > "$csvFileName"
	echo ",,,$reportTitle" >> "$csvFileName"
	echo " " >> "$csvFileName"
}

# read the outoyt and properly format
function postProcess
{
	# Split on pipe to account spaces in comments
	IFS='|'

	# Read dump from select
	while read var2 var3 var4 var5 var6 var7
	do
		# Ignore blank lines
		if [[ "$var2" = "" ]]
		then
			continue
		fi

		# The first line is put into csv file as the header
		if [ "$headCnt" -eq 0 ]
		then
			nextRow="Jrnl Ref,Ref #,G/L Account,Debit,Credit,Comments,Fisc. Prd"
		else
			# Trim to the left to derive ref. num.
			refKey=${var2#JV *}

			# A 'D' indicates neg.; an 'F' positive
			if [[ ${var6%%D} != "$var6" || ${var6%%F} != "$var6" ]]
			then
				if [[ ${var6%%D} != "$var6" ]]
				then
					factor=-100
					var6=${var6%%D}
				else
					factor=100
					var6=${var6%%F}
				fi 
				# Compute debit
 				debit="$(echo $var6/ $factor | bc -l)"
			else
 				debit="$(echo 0| bc -l)"
			fi 


			# A 'D' indicates neg.; an 'F' positive
			#if [[ "$var7" == "0000000000D" || "$var7"  == "0000000000F" ]]
			if [[ ${var7%%D } != "$var7" || ${var7%%F } != "$var7" ]]
			then
				if [[ ${var7%%D } != "$var7" ]]
				then
					factor=-100
					var7=${var7%%D }
				else
					factor=100
					var7=${var7%%F }
				fi

				# Compute credit
 				credit="$(echo $var7/ $factor | bc -l)"
			else
 				credit="$(echo 0| bc -l)"
			fi

			# Skip if ref. is not numeric
			if [[ "$refKey" == ${refKey%*[A-Z]} ]]
			then
				# Format to preserve leading zeros
				refKey="=\"$refKey\""
				nextRow="${var2% *},$refKey,$var5,$debit,$credit,$var4,$var3"
			fi
		fi
		((headCnt++))

		# if row is defined add to CSV file
		if [[ "$nextRow" != "" ]]
		then
			echo "$nextRow"
		fi
	done < "$xFile">>"$csvFileName"
}

#-----------------------------------------------------------------
# MAIN
#-----------------------------------------------------------------
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
