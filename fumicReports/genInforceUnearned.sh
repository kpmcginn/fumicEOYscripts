#!/bin/bash
#------------------------------------------------------------------
# Name: genInforceUnearned.sh
# Desc: Script to generate the inforce unearned report. This
#       script has 1 optional argument. This allows for the passing
#       of the year for which to gen the report. By default, the
#       current year is used.
#
#       This report is derived from the NDID01F AS400 database table.
#       This table is defined as the ND Ins Department - unearned premium 
#	table. The query is comprised of three database queries; each 
#	with a specific intent. 
#
#	The first query is for the year of the report for those 
#	table entries where the pro-rate premium(xdprm) or unsecured 
#	premium (xdunrn) are defined and the advance premium(xdavpm) 
#	and the unpaid advance(xdunav) are not defined and the given 
#	policy has only a single occurence in the database.
#
#	The second query is for the year of the report for those 
#	policies that have more then one occurance for the given year
#	where either pro-rate premium(xdprpm) is defined or advance
#	premium(xdavpm) is defined or unpaid advance(xdunav) is defined.
#
#	The third query is for the year after the year of the report
#	for policies where pro-rate premium(xdprpm) is zero and either
#	advance premium (xdavpm) is not zero or unpaid advance (xdunav)
#	is non-zero.
#
#	The extracted data requires minor post extraction processing. 
#	The effective and expiration dates are modified adding the
#	century to the year to create an accurate date. The values 
#	extracted from the database are evaluated for negative characters
#	and adjusted accordingly. The resultant data is written to the
#	CVS file.
#
#===================================================================
#  Version   Name      Date              Description
#------------------------------------------------------------------
#   0.0      KPM     04/15/2014          Original Release
#------------------------------------------------------------------

#
declare -i day=31
declare -i month=12
declare -i cent=
declare -i year=
declare -i temp=
declare -i headCnt=0
declare -i lastType=0
declare lastKey=
declare lastStart=
declare lastEnd=
declare lastDays=0
#declare -i var5=
baseFileName='/tmp/inforceUnearned'
#baseYTDTitle='IS4925 Claims Register as of '
reportTitle=
csvFileName=

# working file
xFile="/tmp/outWF5.xxx"
tFile="/tmp/cleanWF5.out"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh


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

	if [[ -f "$tFile" ]]
	then
		rm -f "$tFile"
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
	controlDate="01/01/${year}"
	thisYear=$year
	followingYear="$(echo $year + 1|bc -l)"
}

# Create the file based on the passed parameters
function createFileName
{
	csvFileName="${baseFileName}_${month}_${day}_${cent}${year}.csv"
}

#function createReportTitle 
#{
#	reportTitle="${baseYTDTitle} ${month}/${day}/${cent}${year}"
#}


function generateResults
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
	db -db as400 -connect -to @db $ipDef $libDef $usrDef $usrPwd
	db -dbconnected @db -query \${ select distinct aa.XDPOL, cast(aa.XDEFDT as varchar(30)), cast(aa.XDEXDT as varchar(30)), cast(aa.XDDAYS as numeric(11,0)) effDays, cast(aa.XDPRPM*10 as numeric(11,0)), cast(aa.XDUNRN*10 as numeric(11,0)), cast(aa.XDAVPM*10 as numeric(11,0)), cast(aa.XDPDAV*10 as numeric(11,0)), cast(aa.XDUNAV*10 as numeric(11,0)), aa.XDLINE from NDID01F aa where trim(cast(aa.xdefdt as varchar(30))) like '______$thisYear' and ((select count(*) from NDID01F where XDPOL= aa.XDPOL and (XDPRPM > 0 or XDUNRN > 0 or XDAVPM > 0 or XDPDAV > 0 or XDUNAV > 0 ))=1)  }$
	db -dbconnected @db -query \${ select distinct aa.XDPOL, cast(aa.XDEFDT as varchar(30)), cast(aa.XDEXDT as varchar(30)), cast(aa.XDDAYS as numeric(11,0)) effDays, cast(aa.XDPRPM*10 as numeric(11,0)), cast(aa.XDUNRN*10 as numeric(11,0)), cast(aa.XDAVPM*10 as numeric(11,0)), cast(aa.XDPDAV*10 as numeric(11,0)), cast(aa.XDUNAV*10 as numeric(11,0)), aa.XDLINE from NDID01F aa where trim(cast(aa.xdefdt as varchar(30))) like '______$thisYear' and XDPRPM != 0 and ((select count(*) from NDID01F where xdpol=aa.xdpol and (XDPRPM > 0 or XDUNRN > 0 or XDAVPM > 0 or XDPDAV > 0 or XDUNAV > 0 )) >1 ) and cast(aa.XDEFDT as varchar(30)) like '______$thisYear' order by 1 }$
	db -dbconnected @db -query \${ select distinct aa.XDPOL, cast(aa.XDEFDT as varchar(30)), cast(aa.XDEXDT as varchar(30)), cast(aa.XDDAYS as numeric(11,0)) effDays, cast(aa.XDPRPM*10 as numeric(11,0)), cast(aa.XDUNRN*10 as numeric(11,0)), cast(aa.XDAVPM*10 as numeric(11,0)), cast(aa.XDPDAV*10 as numeric(11,0)), cast(aa.XDUNAV*10 as numeric(11,0)), aa.XDLINE from NDID01F aa where  trim(cast(aa.xdefdt as varchar(30))) like '______$followingYear' and XDPRPM = 0 and xdavpm !=0 order by 1 }$
EOF
}

# NOT USED
function addReportHeader
{
	echo " " > "$csvFileName"

	if [[ "$reportTitle" != "" ]]
	then
		echo ",,,$reportTitle" >> "$csvFileName"
		echo "---,---,---,---,---,---,---,---,---,---,---,---,---,---,---" >> "$csvFileName"
	fi
}

# read the output and properly format
function postProcess
{
        #oldIFs=IFS
        #IFS='~'

	# read parsing on tilda. This ensures embedded spaces in the ins. line
	# are retained with in var2
	while read var1 var3 var4 _var5 _var6 _var7 _var8 _var9 _var10 name1 name2 name3 name4
	do
		# Ignore blank lines
		if [[ "$var1" == "" || "$var1" == "XDPOL" ]]
		then
			continue
		fi

		# Add the header
		if [ "$headCnt" -eq 0 ]
                then
			nextRow="Policy,Line of Business,Effective Date,Expiration Date,Effective Days,Pro-Rate Premium,Unsecured Premium, Advance Premium,Paid Advance,Unpaid Advance"
		else
			name="$name1 $name2 $name3 $name4"

			# Get the effective and expiration years
			effYear=${var3##*/}
			expYear=${var4##*/}

			# Add the century to the date variables
			effD="${var3%\/*}/20${effYear}"
			expD="${var4%\/*}/20${expYear}"

			# effective days -->NDID01F.xddays
			var5="$(echo $_var5* 1|bc -l)"

                        # pro-rate premium -->NDID01F.xdprpm. Unclear if it can be
                        # negative so include logic to handle if needed.

                        if [[ "$_var6" != "00000000000" && "$_var6" != ">Í%%" ]]
                        then
				if [[ "$(echo $_var6|sed 's/[^0-9,^}]*//g')" != "$_var6" ]]
                       		then
                       			var6=$(echo $_var6|sed 's/[^0-9,^}]*//g')
                       			var6="$(echo $var6* -1|bc -l)"

				elif [[ "${_var6%\}}" != "$_var6"  ]]
				then
					_var6="${_var6%\}}"
					var6="$(echo $_var6* -1|bc -l)"
				else
					var6="$(echo $_var6/ 10|bc -l)"
				fi
			else
				var6=0
			fi

                        # unsecure premium -->NDID01F.xdunrn. Unclear if it can be
                        # negative so include logic to handle if needed.
                        if [[ "$_var7" != "00000000000" && "$_var7" != ">Í%%" ]]
                        then
				if [[ "$(echo $_var7|sed 's/[^0-9,^}]*//g')" != "$_var7" ]]
                       		then
                       			var7=$(echo $_var7|sed 's/[^0-9,^}]*//g')
                       			var7="$(echo $var7* -1|bc -l)"

				elif [[ "${_var7%\}}" != "$_var7"  ]]
				then
					_var7="${_var7%\}}"
					var7="$(echo $_var7* -1|bc -l)"
				else
					var7="$(echo $_var7/ 10|bc -l)"
				fi
			else
				var7=0
			fi

                        # advance premium -->NDID01F.xdavpm. Unclear if it can be
                        # negative so include logic to handle if needed.
                        if [[ "$_var8" != "00000000000" && "$_var8" != ">Í%%" ]]
                        then
				if [[ "$(echo $_var8|sed 's/[^0-9,^}]*//g')" != "$_var8" ]]
                       		then
                       			var8=$(echo $_var8|sed 's/[^0-9,^}]*//g')
                       			var8="$(echo $var8* -1|bc -l)"

				elif [[ "${_var8%\}}" != "$_var8"  ]]
				then
					_var8="${_var8%\}}"
					var8="$(echo $_var8* -1|bc -l)"
				else
					var8="$(echo $_var8/ 10|bc -l)"
				fi
			else
				var8=0
			fi

                        # paid advance -->NDID01F.xdpdav. Unclear if it can be
                        # negative so include logic to handle if needed.
                        if [[ "$_var9" != "00000000000" && "$_var9" != ">Í%%" ]]
                        then
				if [[ "$(echo $_var9|sed 's/[^0-9,^}]*//g')" != "$_var9" ]]
                       		then
                       			var9=$(echo $_var9|sed 's/[^0-9,^}]*//g')
                       			var9="$(echo $var9* -1|bc -l)"

				elif [[ "${_var9%\}}" != "$_var9"  ]]
				then
					_var9="${_var9%\}}"
					var9="$(echo $_var9* -1|bc -l)"
				else
					var9="$(echo $_var9/ 10|bc -l)"
				fi
			else
				var9=0
			fi

			# unpaid advance -->NDID01F.xdunav. Unclear if it can be
			# negative so include logic to handle if needed.
                        if [[ "$_var10" != "00000000000" && "$_var10" != ">Í%%" ]]
                        then
				if [[ "$(echo $_var10|sed 's/[^0-9,^}]*//g')" != "$_var10" ]]
                       		then
                       			var10=$(echo $_var10|sed 's/[^0-9,^}]*//g')
                       			var10="$(echo $var10* -1|bc -l)"

				elif [[ "${_var10%\}}" != "$_var10"  ]]
				then
					_var10="${_var10%\}}"
					var10="$(echo $_var10* -1|bc -l)"
				else
					var10="$(echo $_var10/ 10|bc -l)"
				fi
			else
				var10=0
			fi

			nextRow="$var1,\"$name\", $effD,$expD, $var5, $var6,$var7,$var8,$var9,$var10"

                # If not a blank line add to the report
		fi

                if [[ "$nextRow" != "" ]]
                then
                        echo "$nextRow"
                fi
                ((headCnt++))

	done < "$xFile">>"$csvFileName"
#	done < "$xFile"
}

setLimits "$1" "$2"
createFileName "$1" "$2"
cleanFiles
#createReportTitle "$1" "$2"
generateResults
#addReportHeader
postProcess
echo "Results can be found in: $csvFileName"

# clean up on error or exit
trap cleanOnExit EXIT SIGINT
trap cleanFiles  ERR SIGTERM

#
#------------------------- end of script ----------------------------
