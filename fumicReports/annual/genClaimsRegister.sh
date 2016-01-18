#!/bin/bash
#------------------------------------------------------------------
# Name: genClaimsRegister.sh
# Desc: Script to generate the claims register report. This
#       script has 1 optional argument. This allows for the passing
#       of the year for which to gen the report. By default, the
#       current year is used.
#
#       This report is derived from severn AS400 tables: clclaims, 
#	clvdjoin, clsubrec, clclchd, clclvdhs, clclnam, clclhist.
#	The function and purpose of each of these tables is as follows:
#	  - clclaims - master claims table used to derive claims to
#                      be included in report, used to derive cost and
#                      expenses used to driving alloc/unalloc values
#	  - clvdjoin - claims expenses used in the drivation of alloc/
#                      unalloc values.
#         - clsubrec - source of claim salvage/subrogation values
#         - clclchd  - source of claim payment values
#         - clclvdhs - source of voided claim payments
#         - clclnam  - source of name data associated with claim
# 	  - clclhist - source of claim reserve value
#
#	All of these tables are associated to the clclaims table by
# 	means of the claim number.
#
#	The claims to be included in the report are those that were
#	open in the year of the report, or claims that were closed
#       or deleted in the year of the report.
#
#	The payment value included in the report is the sum of claim payments 
#	minus voided payments. The salvage/subrogation value is the absolute 
#	value of the sum of amounts for the claim year from the subrogation table. 
#	The reserve is taken directly from the claim history table. The 
#	derivation of the allocated and unallocated values is a complex algorithm 
#	that considers the status of the claim (open, closed, deleted), whether 
#	the claim was new the year of the report or older, and a complex analysis 
#	of the costs and expensed derived from the clclaims and clvdjoin tables.
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
declare -i isSubro=0
declare -i isStar=0
declare -i isMB=0
declare -i partCnt=0
nameHeader=

baseFileName='/tmp/claimsRegister'
baseYTDTitle='IS4925 Claims Register as of '
reportTitle=
csvFileName=

# working file
xFile="/tmp/outWF1.xxx"

# Set the location path
locPath="$(dirname `which $0`)"

# get the IP, userName, and password
source $locPath/credDef.sh

# Required for gen'ing 2013 report in 2014
#source $locPath/affectedClaims.sh

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
	# If nothing passed use current century and date
        if [[ "$1" = '' ]] && [[ "$2" = '' ]]
	then
		cent=$(date +"%C")
		year=$(date +"%y")
		let month=12

	# If year is passed assume "yyyy" and parse
	elif [[ "$2" = '' ]]
	then
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
		let month=12
	else
		temp=$1
		cent=$temp/100
		let year=$temp-$(expr $cent \* 100)
		let month=$2
	fi
	currentYear="$(echo $year |bc -l)"
	followingYear="$(echo $year + 1|bc -l)"
	currentCentury="$(echo $cent |bc -l)"
	lastCentury="$(echo $cent-1 |bc -l)"
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
	# Use this option if year of the report is in the past and more than
	# 25 days into the current year. This condion was developed imperically.
	if [ $(date +%Y) -gt $thisYear ] && [ $(date +%j) -gt 25 ]
	then
		generateResultsOp1
		postProcessOp1

	# If the report is for the current year, use hist. trace table for results
	else
		generateResultsOp2
		postProcessOp2
	fi
}

function generateResultsOp1
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
	db -db as400 -query \${ select aa.clno, substr(aa.clno,3,2)||'-'||substr(aa.clno,5) as "Claim #", aa.clopcl, cast(aa.cllscy||aa.cllsyy as numeric(11,0)), cast(aa.clrdcy||clrdyy as numeric(11,0)), cast(aa.cladex as numeric(11,2)), cast(aa.cllgex as numeric(11,2)), cast(aa.claajf as numeric(11,2)), cast(aa.cllgfe as numeric(11,2)), (select cast(sum(chckam) as numeric(11,2)) from clvdjoin where chclno=aa.clno and chfscy=$currentCentury and chfspd like '$currentYear%' and chpyty!='L'and chvoid = 'N'),(select cast(sum(chckam) as numeric(11,2)) from clvdjoin where chclno=aa.clno and chfscy=$currentCentury and chfspd like '$currentYear%' and chpyty='L'and chvoid = 'N'),case when aa.cllsmm < 10 then '0'||substr(aa.cllsmm,1,1) else substr(aa.cllsmm,1,2) end ||'/'||case when aa.cllsdd < 10 then '0'||substr(aa.cllsdd,1,1) else substr(aa.cllsdd,1,2) end||'/'||aa.cllscy||case when cast(aa.cllsyy as integer) < 10 then '0'||substr(aa.cllsyy,1,1) else substr(aa.cllsyy,1,2) end as "Loss Date",case when aa.clrdmm < 10 then '0'||substr(aa.clrdmm,1,1) else substr(aa.clrdmm,1,2) end ||'/'||case when aa.clrddd < 10 then '0'||substr(aa.clrddd,1,1) else substr(aa.clrddd,1,2) end||'/'||aa.clrdcy||case when cast(aa.clrdyy as integer) < 10 then '0'||substr(aa.clrdyy,1,1) else substr(aa.clrdyy,1,2) end, case when aa.clrvmm < 10 then '0'||substr(aa.clrvmm,1,1) else substr(aa.clrvmm,1,2) end ||'/'||case when aa.clrvdd < 10 then '0'||substr(aa.clrvdd,1,1) else substr(aa.clrvdd,1,2) end||'/'||aa.clrvcy||case when cast(aa.clrvyy as integer) < 10 then '0'||substr(aa.clrvyy,1,1) else substr(aa.clrvyy,1,2) end, ( select cast(sum(chckam) as numeric(11,2)) from clclchd where chpyty='A' and chclno=aa.clno and chckcy=$currentCentury and chckdt like '$currentYear%' and chvoid='N'), (select cast(sum(sbamt*10) as numeric(11,2)) from clsubrec where sbficy=$currentCentury and sbfisc like '$currentYear%' and sbclno=aa.clno), cast(bb.chybr*10 as numeric(11,2)), (select cast(sum(vdckam*100) as numeric(11,2)) from clclvdhs where vdclno=aa.clno and vdpyty='C' and vdvdcy=$currentCentury and vdvddt like '$currentYear%' ), (select cast( sum(cc.chckam*100) as numeric(11,2)) from clclchd cc where cc.chclno=aa.clno  and cc.chpyty='C' and cc.chckcy=$currentCentury and cc.chckdt like '$currentYear%'  ) ,aa.clacst||'-'||case when aa.clacno <100 then '0000'||substr(aa.clacno,1,2) when aa.clacno<1000 then '000'||substr(aa.clacno,1,3) when aa.clacno < 10000 then '00'||substr(aa.clacno,1,4) when aa.clacno < 100000 then '0'||substr(aa.clacno, 1, 5) else substr(aa.clacno,1,6) end ||'-'||case when cast(aa.clplin as integer) < 10 then '0'||substr(aa.clplin,2,1)  else substr(aa.clplin,1,2) end ||'-0'||case when cast(aa.clplsq as integer) < 10 then '0'||substr(aa.clplsq,1,1)  else substr(aa.clplsq,1,2) end ||'-'|| aa.clckdg||'-'||case when cast(aa.clplyr as integer) < 10 then '0'||substr(aa.clplyr,1,1) else substr(aa.clplyr,1,2) end ,aa.clcano as Cause, aa.clajno as Adjuster, aa.clrsv as "Rsrv Code",( select cc.nmname||'@'||cc.nmbscd  from clclnam cc where cc.nmclno = aa.clno and cc.nmaob in ('A','B','O','D') and ( select count(*) from clclnam where nmclno =cc.nmclno ) = 2 and not exists( select 1 from clclnam  where nmbscd='Y' and nmclno=cc.nmclno)  union select ee.nmname||'@'||ee.nmbscd from clclnam ee where ee.nmclno = aa.clno and ee.nmbscd='N' and ( select count(*) from clclnam  where nmclno = ee.nmclno ) = 2 and exists( select 1 from clclnam where nmbscd='Y' and nmclno=ee.nmclno) and exists( select 1 from clclnam where nmbscd='N' and nmclno=ee.nmclno) union  select gg.nmname||'@'||gg.nmbscd from clclnam gg where gg.nmclno=aa.clno and gg.nmadno = 0 and ( select count(*) from clclnam  where nmclno = gg.nmclno ) = 2 and exists( select 1 from clclnam where nmbscd='Y' and nmclno=gg.nmclno) and not exists( select 1 from clclnam where nmbscd='N' and nmclno=gg.nmclno) union select hh.nmname||'@'||hh.nmbscd   from clclnam hh where hh.nmclno=aa.clno and ( select count(*) from clclnam  where nmclno = hh.nmclno ) = 1 )    from clclaims aa join clclhist bb on aa.clno = bb.chclno where ((((clopcl='O' and clrdcy=$currentCentury and clrdyy<=$currentYear and clrdmm<=$month) or (clopcl='O' and clrdcy=$lastCentury))or (aa.clrdcy =$currentCentury and clrdyy=$currentYear and clrdmm <=$month)) or (((clopcl in ('C','D') and aa.clrdcy=$currentCentury and clrdyy in ($currentYear,$followingYear)) or (clopcl='O' and aa.clrdcy=$currentCentury and clrdyy =$followingYear))and ((cllscy=$lastCentury) or (cllscy=$currentCentury and cllsyy<=$currentYear)))) and aa.clno not like '$nextYear%' order by 1  }$ $ipDef $libDef $usrDef $usrPwd
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
#  var1  - claim numbers with leading two digits trimmed and result formatter
#  var2  - status of claim Open, Closed, Deleted [ used for debugging]
#  var3  - year the claim was received
#  var4  - year claim was last updated
#  var5  - clclaims.cladex value is the act. adj. expense
#  var6  - clclaims.cllgex value is the act. legal/professional expense
#  var7  - clclaims.cllgfe value is the actual legal/professional fees
#  var8  - clclaims.claajf value is the act. adjusted fee
#  var9  - sum of clvdjoin.chckam amounts from legal expenses for the claim
#  var10 - sum of clvdjoin.chckam amounts from adjusted expenses for the claim
#  var11 - loss date
#  var12 - last accounting date for the claim
#  var13 - Date claim was received
#  var14 - sum of clclchd.chckam which is check header info for payment type 'A' (adjustment?)
#  var15 - sum of clsubrec.abamt for the claim the derive salvage/subrogation value
#  var16 - clhist.chybr as current reserve
#  var17a - running total of payments
#  var17b - sum of clclchd.chckam which is check header where payment is not void
#  var18 - format account, line no, sequence, check digit, and year together to create account/policy no for report.
#  var19 - clclaims.clcano as claims cause number
#  var20 - clclaims.clajno as claims adjuster
#  var21 - clclaims.clrsv as reserve code 
#  name[1-6] - pieces of the claim name derived clclnam
#
function postProcessOp1
{
        # Loop and read each row of the result set from the temp file
        while read var0 var1 var2 _var3 _var4 _var5 _var6 _var7 _var8 _var9 _var10 var11 var12 var13 _var14 _var15 _var16 _var17a _var17b var18 var19 var20 var21 name1 name2 name3 name4 name5 name6
        do
                # Ignore blank lines
                if [[ "$var1" = "" ]]
                then
                        continue
		fi

                # First row returned is header info.
                if [ "$headCnt" -eq 0 ]
                then
                        nextRow="Claim #,Claimant,Account/Policy No,Loss Date,Date Received, Accnting Date,CC #, ADJ #,RS CD,Rsrv Chg, Curr Rsrv,Clm Pmts,Salvg/Subro,Alloc,U alloc"
                else

	#----------------------------------------------------------------------------------------
	# BLOCK START - Build formatted name string
	#----------------------------------------------------------------------------------------
	#		_nameHeader=''
	#		nameBuilder _nameHeader  "$name1" "$name2" "$name3" "$name4" "$name5" "$name6" 
	#		nameHeader=$(echo $_nameHeader|sed "s/~/'/g")
			nameBuilder "DUMMY" "$name1" "$name2" "$name3" "$name4" "$name5" "$name6" 
	#----------------------------------------------------------------------------------------
	# BLOCK END - Build formatted name string complete
	#----------------------------------------------------------------------------------------

			# var3 and var4 are integer value dates but as400 returns dates with
			# leading zeros which Bash can interpret as octal.
			var3="$(echo $_var3* 1|bc -l)"
			var4="$(echo $_var4* 1|bc -l)"
			oldVar4=$var4

	#----------------------------------------------------------------------------------------
	# BLOCK START - For 2013 report run in 2014 look up last acct date in 2013 and
	#               make adjustments to controls for claim
	#----------------------------------------------------------------------------------------
			#if [[ "$thisYear" == "13" ]]
			#then
			#	if [[ "${claimString/$var0}" != "$claimString" ]]
			#	then
			#		# read through file that contaims claims and acct dates
			#		# if found parse and reset accounting date. If file acct
			#		# date is beyond last 2013 date, set status as open
			#		while read line
			#		do
			#			if [[ "${line:0:9}" == "$var0" ]]
			#			then
			#				endDate="${line:10:10}"
			#				var2="O"
			#				var4=$thisYear
#
##							break
#						fi
#					done<dateCorrections.sh
#				else
#					endDate=$var12	
#				fi
#			else
				endDate=$var12	
#			fi

	#----------------------------------------------------------------------------------------
	# BLOCK END - For 2013 report run in 2014 look up last acct date ... complete
	#----------------------------------------------------------------------------------------

			# Get the year for the received date and acct date
			year1=$(echo `date -d "$var13" +%Y`)
			year2=$(echo `date -d "$endDate" +%Y`)

			# Get the julian date of the received date and the acct date
			daysYear1=$(echo `date -d "$var13" +%j`)
			daysYear2=$(echo `date -d "$endDate" +%j`)

			# Get days for the two dates
			periodEnd1="$(echo $year1+$daysYear1/365 | bc -l )"
			periodEnd2="$(echo $year2+$daysYear2/365 | bc -l )"

			# Compute the delta between the recieved date and the acct date
			yearDelta="$(echo $periodEnd2-$periodEnd1 | bc -l )"

			# In case of a date oddity force neg, delta to 0
			if [ "$(echo $yearDelta '<' 0.0|bc -l)" -eq 1 ]
			then
				yeardelta=0
			fi

			# clclaims.cladex is the act. adj. expense
                	if [[ "$_var5" != "00000000000" ]]
                	then
                		var5="$(echo $_var5/ 100 | bc -l)"
                	else
				var5=0
                	fi

			# clclaims.cllgex is the act. legal/professional expense
                	if [[ "$_var6" != "00000000000" ]]
                	then
                		var6="$(echo $_var6/ 100 | bc -l)"
                	else
				var6=0
                	fi

			# clclaims.claajf is the act. adjusted fee
                	if [[ "$_var7" != "00000000000" ]]
                	then
                		var7="$(echo $_var7/ 100 | bc -l)"
                	else
				var7=0
                	fi

			# clclaims.cllgfe is the actual legal/professional fees
                	if [[ "$_var8" != "00000000000" ]]
                	then
                		var8="$(echo $_var8/ 100 | bc -l)"
                	else
				var8=0
                	fi

			# clvdjoin.chckam amounts from legal expenses for the claim
                        if [[ "$_var9" != "00000000000" && "$_var9" != ">Í%%" ]]
                        then
                		var9="$(echo $_var9/ 100 | bc -l)"
                	else
				var9=0
                	fi

			# clvdjoin.chckam amounts from adjusted expenses for the claim
                        if [[ "$_var10" != "00000000000" && "$_var10" != ">Í%%" ]]
                        then
                		var10="$(echo $_var10/ 100 | bc -l)"
                	else
				var10=0
                	fi

			#  clclchd.chckam which is check header info for payment type 'A' (adjustment?)
                        if [[ "$_var14" != "00000000000" && "$_var14" != ">Í%%" ]]
                        then
                		var14="$(echo $_var14/ 100 | bc -l)"
                	else
				var14=0
			fi

			#  clsubrec.abamt for the claim the derive salvage/subrogation value
			#  The abs() with AS400 query was inconsistant, To ensure consistant
			#  resukts, ensure result the net result = abs(sum(clsubrec.abamt)
                        if [[ "$_var15" != "00000000000" && "$_var15" != ">Í%%" ]]
                        then
				# Negative results are returned with a trailing (rt most) alpha
				# character [A-Z]. Trim off and divide by 100
                        	if [[ "$(echo $_var15|sed 's/[^0-9,^}]*//g')" != "$_var15" ]]
                        	then
                                	_var15=$(echo $_var15|sed 's/[^0-9,^}]*//g')
					var15="$(echo $_var15/ 100| bc -l)"

				# Commonly, a '}' is the trailing character (rt most). indicating
				# negative. For abs(), remove char and divide by 100.
                                elif [[ "${_var15%\}}" != "$_var15"  ]]
                                then
                                        _var15="${_var15%\}}"
                                        var15="$(echo $_var15/ 100| bc -l)"
				else
                			var15="$(echo $_var15/ 1000| bc -l)"
				fi
                	else
				var15=0
			fi

			# payments for open claims
                        if [[ "$_var17a" != "00000000000" && "$_var17a" != ">Í%%" ]]
                        then
                		paymentV="$(echo $_var17a/ 100 | bc -l)"

                	else
				paymentV=0
			fi

	#----------------------------------------------------------------------------------------
	# BLOCK START - Convert the payments and voided payments to real numbers
	#               and compute net payment for claim
	#----------------------------------------------------------------------------------------

			# payements for closed or deleted claims
                        if [[ "$_var17b" != "00000000000" && "$_var17b" != ">Í%%" ]]
                        then
                		paymentP="$(echo $_var17b/ 100 | bc -l)"
                	else
				paymentP=0
			fi 	

			payment="$(echo $paymentP- $paymentV | bc -l)"
			payment="$(echo $payment/100 | bc -l)"

			# If bad data and payment is negative skip this logic
			#if  [ "$(echo $payment '>=' 0.0|bc -l)" -eq 1 ] 
			#then
	#----------------------------------------------------------------------------------------
	# BLOCK END - Convert the payments and voided payments ....
	#----------------------------------------------------------------------------------------

                        	payAsInt="$(echo $payment|sed 's/[.].*//')"
                        	payDecimal="$(echo $payment- $payAsInt | bc -l)"

                        	# Convert trailing decimal to int
                        	payDecimal="$(echo $payDecimal*100 | bc -l|sed 's/[.].*//')"
			#else
			#	payAsInt=0
			#	payAsDecimal=0
			#fi

			#  clhist.chybrs as current reserve
                        if [[ "$_var16" != "00000000000" ]]
                        then
                                if [[ "${_var16%\}}" != "$_var16"  ]]
                                then
                                        _rsrvChg="${_var16%\}}"
                                        rsrvChg="$(echo $_rsrvChg/ -100 | bc -l)"
                                else
                                        reserve="$(echo $_var16/ 1000 | bc -l)"
					rsrvChg=''

				#-------------------------------------------
				# Derived rules for the adj of reserver. No
				#-------------------------------------------

					# if the reserve is old and small but no zero set to 1
					if  [ "$(echo $yearDelta '>' 3.0|bc -l)" -eq 1 ] 
					then
     						if [ "$var4" -eq "$thisYear"  ] &&
						   [ "$(echo $reserve '>' 0.0 |bc -l)" -eq 1 ]
						then
							reserve=1
						fi
					fi

                                	# If the payment value is exactly xx.50 add $1 to 
					# resv value. Unclear of the reasoning but this was 
					# from prior report
                                	if [ "$(echo $payDecimal '!=' 50|bc -l)" -ne 1 ] 
                                	then
                                       		reserve="$(echo $reserve+1|bc -l)"
					fi
                                fi
                        else
                                reserve="$(echo 0 | bc -l)"
				rsrvChg=''
                        fi

			# Init the alloc and un-alloc variables
			unalloc=0
			alloc=0

	#----------------------------------------------------------------------------------------
	# BLOCK START - Compute allocated and un-allocated values
	#----------------------------------------------------------------------------------------

			# If deleted or closed after report year, then were open in report year.
			# Deleted and closed processed as such if date of last action is in
			# report year
			if [[ "$var2" == "D" || "$var2" == "C" ]] 
			then
				# If deleted, determine alloc and unalloc
				if [[ "$var2" == "D" ]]
				then
					# if the claims was created in the year of the report and
					# the act. adj. expense (cladex) is not zero, set unalloc to 
					# cladex value
					if [ "$var3" -eq "$thisYear" ] && 
				   	   [ "$(echo $var5 '!=' 0.0|bc -l)" -eq 1 ]

					then
						unalloc=$var5

					# Otherwise if the act. leg/prof. exp (cllgex) is non zero 
					# set the unalloc to the cllgex value
					elif [ "$(echo $var6 '!=' 0.0|bc -l)" -eq 1 ]
					then
						unalloc=$var6

					# default for the unalloc value is zero
					else
						unalloc=0
					fi

					# if the claim init date is within a year of the last update
					# or the last change was in the following year and the
					# act. adj fee (claajf) is non zero, set alloc value to claajf
					#if [[ "$(echo $var4-$var3 | bc -l)" -le 1  ]]
					if [ "$var3" -eq "$thisYear" ] && 
				   	   [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ]
					then
						alloc=$var7

					elif [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ] &&
					     [ "$(echo $var14 '!=' 0.0|bc -l)" -eq 1 ]
					then
						alloc=$var14

					# Othewise if the act. leg/pro. fee (cllgfe) is non zero
					# set the alloc value to cllgfe
					elif [ "$(echo $var8 '!=' 0.0|bc -l)" -eq 1 ]
					then
						alloc=$var8

					# The default for the alloU is zero
					else
						alloc=0
					fi

				elif [[ "$var2" == "C" ]] 
				then
					# if the claims was created in the year of the report and
					# the act. adj. expense (cladex) is not zero, set unalloc to 
					# cladex value
					if [ "$var3" -eq "$thisYear" ] 
					then
						if [ "$(echo $var5 '!=' 0.0|bc -l)" -eq 1 ]
						then
							unalloc=$var5

						elif [ "$(echo $var6 '!=' 0.0|bc -l)" -eq 1 ]
						then
							unalloc=$var6
						fi

						if [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ]
						then
							alloc=$var7

						elif [ "$(echo $var8 '!=' 0.0|bc -l)" -eq 1 ]
						then
							alloc=$var8
						fi


					elif [ "$(echo $yearDelta '<=' 3.0|bc -l)" -eq 1 ]
					then
						if [ "$(echo $var9 '!=' 0.0 | bc -l )" -eq 1 ] 
						then
							alloc="$(echo $var9-$var5 | bc -l )"
							unalloc="$(echo $var5 | bc -l )"

						elif [ "$(echo $var10 '>' 0.0|bc -l)" -eq 1 ] 
						then
							alloc="$(echo $var10-$var6 | bc -l)"
							unalloc="$(echo $var6 | bc -l )"

						elif [ "$(echo $var5 '!=' 0.0|bc -l)" -eq 1 ] &&
						     [ "$(echo $var14 '!=' 0.0|bc -l)" -eq 1 ]
						then
							unalloc=$var14

						elif [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ] &&
						     [ "$(echo $var14 '!=' 0.0|bc -l)" -eq 1 ]
						then

							alloc=$var14
						fi

					else
						if [ "$(echo $var9 '!=' 0.0 | bc -l )" -eq 1 ] 
						then
							unalloc="$(echo $var9-$var5 | bc -l )"
							alloc="$(echo $var5 | bc -l )"

						elif [ "$(echo $var10 '>' 0.0|bc -l)" -eq 1 ] 
						then
							alloc="$(echo $var10-$var6 | bc -l)"
							unalloc="$(echo $var6 | bc -l )"
						fi
					fi
				fi

			# if currently open 
			else
				if [ "$(echo $var9 '!=' 0.0 | bc -l )" -eq 1 ] 
				then
					if [ "$(echo $var9-$var5 '<=' 0.0|bc -l)" -eq 1 ]
					then
						unalloc="$(echo $var9 | bc -l )"
						alloc=0
					else
						unalloc="$(echo $var9 -$var7 | bc -l )"
						alloc="$(echo $var7 | bc -l )"
					fi

				elif [ "$(echo $var10 '!=' 0.0|bc -l)" -eq 1 ] 
				then
					if [ "$(echo $var10-$var6 '<=' 0.0|bc -l)" -eq 1 ]
					then
						alloc=0
						unalloc="$(echo $var10 | bc -l )"
					else
                               			alloc="$(echo $var10 | bc -l)"
                                       		unalloc=0
					fi

				elif [ "$var4" -eq "$thisYear"  ] && 
				     [ "$var3" -eq "$thisYear"  ]
				then
					if [ "$oldVar4" -eq "$thisYear" ]
					then
                                        	if [ "$(echo $var5 '!=' 0.0|bc -l)" -eq 1 ]
                                        	then
                                                	unalloc=$var5

                                        	elif [ "$(echo $var6 '!=' 0.0|bc -l)" -eq 1 ]
                                        	then
                                                	unalloc=$var6
                                        	fi

                                        	if [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ]
                                        	then
                                                	alloc=$var7

                                        	elif [ "$(echo $var8 '!=' 0.0|bc -l )" -eq 1 ]
                                        	then
                                                	alloc=$var8
                                        	fi

				      	elif [ "$oldVar4" -eq "$nextYear" ] 
					then
                                        	if [ "$(echo $var5 '!=' 0.0|bc -l)" -eq 1 ] &&
						   [ "$(echo $var14 '!=' 0.0|bc -l)" -eq 1 ] 
						then
                                                	unalloc=$var14
                                        	fi

                                        	if [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ] &&
						   [ "$(echo $var14 '!=' 0.0|bc -l)" -eq 1 ] 
                                        	then
                                                	alloc=$var14
                                        	fi
					fi

				elif [ "$var3" -eq "$lastYear"  ]
			     	then
                                	if [ "$(echo $var7 '!=' 0.0|bc -l)" -eq 1 ] &&
					   [ "$(echo $var14 '!=' 0.0|bc -l)" -eq 1 ] 
                                       	then
                                               	alloc=$var14
					fi	
				fi
			fi

	#----------------------------------------------------------------------------------------
	# BLOCK END - Compute allocated and un-allocated values - end
	#----------------------------------------------------------------------------------------

			nextRow="$var1,\"$nameHeader\",$var18,$var11, $var13, $endDate,$var19, $var20, $var21, $rsrvChg,$reserve,$payment,$var15,$alloc,$unalloc"

			# under some conditions, rows are picked up with last
			# activity past the end month selected for report.
			# Find and clear output
 			#if [[ "${endDate%%$currentYear}" != "$endDate" ]]
			#then
			#	if [ "$(echo $endDate|cut -d / -f1)" -gt $month ]
			#	then
			#		nextRow=""
			#	fi
			#fi
		fi

		# If not a blank line add to the report
		if [[ "$nextRow" != "" ]]
		then
			echo "$nextRow"
		fi
		((headCnt++))

	done < "$xFile">>"$csvFileName"
	#done < "$xFile"
}

# query the CLCLAIMS and CLCLHIST tables for report elements
function generateResultsOp2
{
	java -Xms4g -Xmx4g -jar /opt/api-java/AbsPerfOS400.jar<<EOF > "$xFile"
db -db as400 -query \${ select substr(aa.clno,3,2)||'-'||substr(aa.clno,5) as "Claim #", aa.clacst||'-'||case when aa.clacno <100 then '0000'||substr(aa.clacno,1,2) when aa.clacno<1000 then '000'||substr(aa.clacno,1,3) when aa.clacno < 10000 then '00'||substr(aa.clacno,1,4) when aa.clacno < 100000 then '0'||substr(aa.clacno, 1, 5) else substr(aa.clacno,1,6) end as Account, case when cast(aa.clplsq as integer) < 10 then '0'||substr(aa.clplsq,1,1)  else substr(aa.clplsq,1,2) end ||'-'||'0'||substr(aa.clplin,1,2)  as Policy, aa.clckdg as "Ck Digit",aa.clplyr as Year,case when aa.cllsmm < 10 then '0'||substr(aa.cllsmm,1,1) else substr(aa.cllsmm,1,2) end ||'/'||case when aa.cllsdd < 10 then '0'||substr(aa.cllsdd,1,1) else substr(aa.cllsdd,1,2) end||'/'||aa.cllscy||case when cast(aa.cllsyy as integer) < 10 then '0'||substr(aa.cllsyy,1,1) else substr(aa.cllsyy,1,2) end as "Loss Date",case when aa.clrvmm < 10 then '0'||substr(aa.clrvmm,1,1) else substr(aa.clrvmm,1,2) end ||'/'||case when aa.clrvdd < 10 then '0'||substr(aa.clrvdd,1,1) else substr(aa.clrvdd,1,2) end||'/'||aa.clrvcy||case when cast(aa.clrvyy as integer) < 10 then '0'||substr(aa.clrvyy,1,1) else substr(aa.clrvyy,1,2) end as "Rsrv Date",case when aa.clrdmm < 10 then '0'||substr(aa.clrdmm,1,1) else substr(aa.clrdmm,1,2) end ||'/'||case when aa.clrddd < 10 then '0'||substr(aa.clrddd,1,1) else substr(aa.clrddd,1,2) end||'/'||aa.clrdcy||case when cast(aa.clrdyy as integer) < 10 then '0'||substr(aa.clrdyy,1,1) else substr(aa.clrdyy,1,2) end as "Acctg Date",aa.clcano as Cause, aa.clajno as Adjuster, aa.clrsv as "Rsrv Code", cast(dd.chyer*10 as numeric(11,2)) as  "Curr Rsrv",cast(dd.chynp*10 as numeric(11,2)) as "Clm Pmts",cast(dd.chys*10 as numeric(11,2)) as "Salvg/Subro",cast(dd.chyla*10 as numeric(11,2)) as "U alloc",case when aa.claajf > 0 or aa.cllgfe > 0 then '1' else '0' end, cast(aa.cllgex as numeric(11,2)), cast(aa.cladex as numeric(11,2)),  cast(aa.cllgfe as numeric(11,2)), ( select cc.nmname||'@'||cc.nmbscd  from clclnam cc where cc.nmclno = aa.clno and cc.nmaob in ('A','B','O','D') and ( select count(*) from clclnam where nmclno =cc.nmclno ) = 2 and not exists( select 1 from clclnam  where nmbscd='Y' and nmclno=cc.nmclno)  union select ee.nmname||'@'||ee.nmbscd from clclnam ee where ee.nmclno = aa.clno and ee.nmbscd='N' and ( select count(*) from clclnam  where nmclno = ee.nmclno ) = 2 and exists( select 1 from clclnam where nmbscd='Y' and nmclno=ee.nmclno) and exists( select 1 from clclnam where nmbscd='N' and nmclno=ee.nmclno) union  select gg.nmname||'@'||gg.nmbscd from clclnam gg where gg.nmclno=aa.clno and gg.nmadno = 0 and ( select count(*) from clclnam  where nmclno = gg.nmclno ) = 2 and exists( select 1 from clclnam where nmbscd='Y' and nmclno=gg.nmclno) and not exists( select 1 from clclnam where nmbscd='N' and nmclno=gg.nmclno) union select hh.nmname||'@'||hh.nmbscd   from clclnam hh where hh.nmclno=aa.clno and ( select count(*) from clclnam  where nmclno = hh.nmclno ) = 1 ) as "Claimant" from clclaims aa join clclhist dd on aa.clno = dd.chclno where (aa.clopcl = 'O' and cast(substr(aa.clno,1,4) as int) <= $thisYear) or (aa.clclcy = $cent and aa.clclyy = $year and aa.clopcl !='O' ) or (aa.clrdcy = $cent and aa.clrdyy = $year and aa.clopcl !='O' ) order by aa.clno asc }$ $ipDef $libDef $usrDef $usrPwd
EOF
}

# read the output and properly format
function postProcessOp2
{
	# Loop and read each row of the result set from the
	# temp file
	while read var1 var2 var3a var4a var5 var6 var7 var8 var9 var10 var11 _var13 _var14 _var15 _var17 var31 _var32 _var33 _var34 var18 var19 var20 var21 var22 var23 var24 var25 var26 var27 var28
	do
		# Ignore blank lines
		if [[ "$var1" = "" ]]
		then
			continue
		fi

		# First row returned is header info.
		if [ "$headCnt" -eq 0 ]
                then
			nextRow="Claim #,Claimant,Account,Policy,Ck Digit,Year,Loss Date,Rsrv Date,Acctg Date,Cause,Adjuster,Rsrv Code,Rsrv Chg, Curr Rsrv,Clm Pmts,Salvg/Subro,Alloc,U alloc"
		else
			# NOTE: conversion to decimal values req.
			# clean up. A value of "00000000000" is
			# interpreted by BASH as an octal; dont
			# process just set to zero. Values are
			# multiplied by 10 on select from DB to
			# ensure trailing dec. is not lost. 
			# a '}' indicates a neg. number. Account
			# for these conditions and conv. to decimal

			# current reserve
			if [[ "$_var13" != "00000000000" ]]
			then
                        	if [[ "${_var13%\}}" != "$_var13"  ]]
                        	then
                        		_var13=${_var13%\}}
					var13="$(echo $_var13/ -100 | bc -l)"
				else
					var13="$(echo $_var13/ 1000 | bc -l)"
				fi
			else
				var13="$(echo 0 | bc -l)"
			fi

			# $_var14 is the "claim payments" value
			if [[ "$_var14" != "00000000000" ]]
			then
                        	if [[ "${_var14%\}}" != "$_var14"  ]]
                        	then
                        		_var14=${_var14%\}}
					var14="$(echo $_var14/ -100 | bc -l)"
				else
					var14="$(echo $_var14/ 1000 | bc -l)"
				fi
			else
				var14="$(echo 0 | bc -l)"
			fi

			# $_var15 is the "salvage/subrogation" value - note this is always positive.
			if [[ "$_var15" != "00000000000" && "$_var15" != ">Í%%" ]]
			then
                        	if [[ "${_var15%\}}" != "$_var15"  ]]
                        	then
                        		_var15=${_var15%\}}
					var15="$(echo $_var15/ 100 | bc -l)"
				else
					var15="$(echo $_var15/ 1000 | bc -l)"
				fi
			else
				var15="$(echo 0 | bc -l)"
			fi

			# $_var17 is the "unallocated" value
			if [[ "$_var17" != "00000000000" ]]
			then
                        	if [[ "${_var17%\}}" != "$_var17"  ]]
                        	then
                        		_var17=${_var17%\}}
					var17="$(echo $_var17/ -100 | bc -l)"
				else
					var17="$(echo $_var17/ 1000 | bc -l)"
				fi
			else
				var17="$(echo 0 | bc -l)"
			fi

			# var31 is set to 1 if clclaims.claajf - actual adj fee is non-zero or
			# clclaims.cllgfe - act. legal/professional fees are non-zero.  Used in
                        # determining if paid loss adj. is allocated or unallocated

			# clclaims.cllgex - actual legal/prof. expenses. Used in
			# determining if paid loss adj. is allocated or unallocated
			if [[ "$_var32" != "00000000000" ]]
			then
				var32="$(echo $_var32/100 | bc -l)"
			else
				var32="$(echo 0 | bc -l)"
			fi

			# clclaims.cladex - actual adjusted expense. Used in
                        # determining if paid loss adj. is allocated or unallocated
			if [[ "$_var33" != "00000000000" ]]
			then
				var33="$(echo $_var33/100 | bc -l)"
			else
				var33="$(echo 0 | bc -l)"
			fi

			# clclaims.cllgfe - actual legal/prof. fees. Used in
                        # determining if paid loss adj. is allocated or unallocated
			if [[ "$_var34" != "00000000000" ]]
			then
				var34="$(echo $_var34/100 | bc -l)"
			else
				var34="$(echo 0 | bc -l)"
			fi

			# Build the name from the extracted pieces of the name
			nameBuilder "DUMMY" "$var18" "$var19" "$var20" "$var21" "$var22" "$var23" "$var24"
			payAsInt="$(echo $var14|sed 's/[.].*//')"
			payDecimal=$(echo $var14-$payAsInt|bc -l)

			# Convert trailing decimal to int
			payDecimal="$(echo $payDecimal*100|bc -l|sed 's/[.].*//')"

			# If the reserve for the claim is negative, set the reserve
			# change is set to the reserver the reserve is set to 0
			if [ "$(echo $var13 '<' 0.0|bc -l)" -eq 1 ]
			then
				rsrvChg=$var13
				var13="$(echo 0 | bc -l)"
			else
				rsrvChg=''

				# If the payment value is exactly xx.50 add $1 to resv value
				# unclear of the reasoning but this was from prior report
				if [ "$(echo $payDecimal '!=' 50|bc -l)" -ne 1 ] && [ "$var13" > 0 ]
				then
					var13="$(echo $var13+1|bc -l)"
				fi
			fi

			# determine how to set $var17 as allocated to claim or not allocated
			if [ "$(echo $var17 '>' 0.0|bc -l)" -eq 1 ]
			then
				# The actual adjusted expense (claims.cladex) plus the actual
				# and professional expense (claims.cllgex) comprise the total
				# expense of the claim
				totExp="$(echo $var32+$var33|bc -l)"

				# if the paid loss adj. (clclhist.chyla) is equal to the actual
				# legal/prof. fees (clclaims.cllgfe) the entire paid loss adjust
				# is allocated and the unallocated is set to zero
				if [ "$(echo $var17 '==' $var34|bc -l)" -eq 1 ]
				then
					alloc=$var17
					unalloc="$(echo 0 |bc -l)"

				# if the total expense (see above) if non-zero and less then  the
				#  paid loss adj. (clclhist.chyla) then the total Expense is
				# overhead and unallocated. The difference between the paid
				# loss adjustment and the expense is allocated to the claim
				elif [ "$(echo $totExp '>' 0.0|bc -l)"    -eq 1 ] && 
				   [ "$(echo $totExp '<' $var17|bc -l)" -eq 1 ]
				then
					unalloc=$totExp
					alloc="$(echo $var17-$totExp |bc -l)"

				# if there is an actual adj. fee for the claim (clclaims.claajf) and
				# the total expense is not equal to the paid loss adjustment, the
				# entire paid loss adj. is allocated to the claim
				elif [ "$var31" -eq 1 ] && [ "$(echo $totExp '!=' $var17|bc -l)" -eq 1 ]
				then
					unalloc="$(echo 0 |bc -l)"
					alloc=$var17

				# If there is an actual adj. fee for the claim (clclaims.claajf) and
				# the total expense is equal to the paid loss adjustment, the
				# entire paid loss adj. is unallocated overhead expense.
				elif [ "$var31" -eq 1 ] 
				then
					alloc="$(echo 0 |bc -l)"
					unalloc=$var17

				# Meeting none of the above conditions, the paid loss adj.
				# is considered overhead and unallocatd.
				else
					unalloc=$var17
					alloc="$(echo 0 |bc -l)"
				fi
			else
				unalloc="$(echo 0 |bc -l)"
				alloc="$(echo 0 |bc -l)"
			fi

			# Define next row in CSV format.
			nextRow="$var1,\"$nameHeader\", $var2,$var3a,$var4a,$var5,$var6,$var7,$var8,$var9, $var10, $var11, $rsrvChg, $var13, $var14, $var15, $alloc, $unalloc"

		fi

		# If not a blank line add to the report
		if [[ "$nextRow" != "" ]]
		then
			echo "$nextRow"
		fi

		((headCnt++))

	done < "$xFile">>"$csvFileName"
	#done < "$xFile"
}

function nameBuilder
{
	localName=

	# Build the name from the extracted pieces of the name
	nxName="$2 $3 $4 $5 $6 $7 $8"

	# Remove the SUBRO flag from the name and set flag to add 
	# later when name if re-formatted
	if [[ "$nxName" != "${nxName%%*SUBRO*}" ]]
	then
       		nxName="$(echo $nxName|sed 's/(SUBRO)//g')"
        	nxName="$(echo $nxName|sed 's/SUBRO//g')"
       		isSubro=1 
	else
       		isSubro=0
	fi

	# If the name string contains a star, strip out and
	# flag to add at the end of the final name string construct
	if [[ "$nxName" != "${nxName%%*\**}" ]]
	then
		nxName="$(echo $nxName|sed 's/*//g')"
		isStar=1
	else
		isStar=0
	fi

	# If a business name dont reorder
	if [[ "$nxName" != "${nxName%@Y*}" ]] 
	then 
		localName=${nxName%@Y*}

	# Reorder for report change from Last, First, middle
	# as stored to First Middle last as reqd for report
	else 
		# Remove the flag denoting name as not being
		# a business
		subName=${nxName%@N*}
		lName=' '
		fName=' '
		mName=' '

		# split on spaces
		arr=$(echo $subName|tr " " "\n")
		partCnt=0
		fName=
		mName=
		lName=

		# Set the parts of name
		for part in $arr
		do
			# Last name
			if [ "$partCnt" -eq 0 ] 
			then
				lName="$part"

			# First name
			elif [ "$partCnt" -eq 1 ]
			then
				fName="$part"

			# Middle name
			else
				mName="$part"
			fi
			((partCnt++))
		done

		# Form name based on whether there is middle initial
		if [ "${#mName}" -eq 0 ]
		then
			localName="$fName $lName"
		else
			localName="$fName $mName $lName"
		fi
	fi

	if [[ "$localName" != "${localName#MB}" ]]
	then
		localName="${localName#MB}     MB"

	# If the SUBRO string was in the base name add to end
	elif [ "$isSubro" -eq "1" ]
	then
		localName="$localName     (SUBRO)"

	elif [ "$isStar" -eq "1" ]
	then
		localName="$localName     *"
	fi
	nameHeader=$localName
}

#-----------------------------------------------------------
# MAIN
#-----------------------------------------------------------
setLimits "$1" "$2"
createFileName "$1" "$2"
cleanFiles
createReportTitle "$1" "$2"
addReportHeader
generateResults
echo "Results can be found in: $csvFileName"

# clean up on error or exit
trap cleanOnExit EXIT SIGINT
trap cleanFiles  ERR SIGTERM

#
#----- genClaimsRegister.sh script ------
