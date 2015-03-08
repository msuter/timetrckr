#!/bin/sh

# This script will help you calculate your lunch break.
# 
# Specifically: writes wake up time in the beginning of the day.
# Sleep time if during lunch time and break was big enough.
#
# Why not check also other times? 
# Because of meetings or discussions were laptop might sleep but you are still working

usage() {
	logger -t $APPNAME "Usage: -s|-w, optional -f <conf.file>"
	exit 1
}

isItLunchTime() {
	if [[ $(( $1 - `date -j -f "%T" "$LUNCHSTART" "+%s"` )) -ge 0 && $(( $1 - `date -j -f "%T" "$LUNCHSTOP" "+%s"` )) -le 0 ]] 
	then
		echo true
	fi
}

# Warning: OSX notifications won't work if you run the script from tmux
showSummary() {
	local LINE=`grep "$LASTWORKINGDAY" $FILE`
	# convert the line to timestamps and calculate the diff
	# Notes:
	# the space is required for [ $TIMESEPARATOR] since the date has a space
	# $0 is the full line in awk and $1 is the date, that's why we start the loop with $2
	# NR starts from 1 in awk	
	local DIFF=`echo $LINE | awk -F "[ $TIMESEPARATOR]" '{for (i=2; i<=NF;i++) {print $i}}' | xargs -n1 date -j -f "%T" "+%s" | awk 'BEGIN{diff=0;}{if(NR%2==0){diff+=$0} else {diff-=$0}} END{print diff}'`

	if [[ $DIFF -le 0 ]]
	then 
		osascript -e "display notification \"Seems you worked negative time on $LASTWORKINGDAY? Please check your $FILE\" with title \"$APPNAME\""
		exit 1;
	elif [[ -f $OUTPUTFILE && ! -z `grep $LASTWORKINGDAY $OUTPUTFILE` ]]  
	then
		osascript -e "display notification \"There exists another entry for $LASTWORKINGDAY. Please check your $OUTPUTFILE\" with title \"$APPNAME\""
		exit 1;
	fi

	local HOURS=$(( $DIFF/60/60 )) # Bash does not support float arithmetics
	local MINUTES=$(( ($DIFF/60)%60 ))
	local PRETTYTEXT=$HOURS" hours, "$MINUTES" minutes"
	osascript -e "display notification \"worked on $LASTWORKINGDAY\" with title \"$PRETTYTEXT\""
	logger -t $APPNAME "Writing summary of $LASTWORKINGDAY in $OUTPUTFILE" 

	# Here we need additional precision (2 digits)
	# Note that bc floors the result
	printf "%s %s" $LASTWORKINGDAY `echo "scale=2; $DIFF/60/60" | bc` >> $OUTPUTFILE 
}

# enter subshell so we don't pollute with variables
( 
# Variables #
APPNAME="timetrckr"
TODAY=`date "+%F"` # +%Y-%m-%d
TIME=`date "+%T"` # +%H:%M:%S
NOW=`date +%s` # timestamp
SHUTDOWNPATTERN="SHUTDOWN_TIME:"
SLEEPSTATE="sleep"
WAKESTATE="wake"

# Default settings #
DEFAULTCONFFILE=$APPNAME".conf" 
FILE=~/time.csv
OUTPUTFILE=~/summary.csv
THRESHOLD=$(( 10*60 )) # 10 minutes
TIMESEPARATOR=";" 
LUNCHSTART="11:30:00"
LUNCHSTOP="13:30:00"

# Parse configuration file, this will overwrite the defaults above #
while read propline 
do 
   # ignore comment lines
   echo "$propline" | grep "^#" > /dev/null 2>&1 && continue
   # strip inline comments and set the variables 
   [ ! -z "$propline" ] && declare `sed 's/#.*$//' <<< $propline` 
done < $DEFAULTCONFFILE

# Parse command line parameters #
# if they exist
if [ "$#" -eq 0 ]
then
	usage
fi

# f requires an argument
# note: caller can use both s and w, the latter will be used
while getopts "swf:" opt
do
	case $opt in
	s)
		logger -t $APPNAME "s selected"
		STATE=$SLEEPSTATE
		;;
	w)
		logger -t $APPNAME "w selected"
		STATE=$WAKESTATE
		;;
	f)
		logger -t $APPNAME "f selected"
		CONFFILE=$OPTARG
		;;
	\?)
		logger -t $APPNAME "Invalid arg"
		usage
		;;
	esac
done

# check if mandatory arguments were given
if [[ -z $STATE ]]
then
	usage 
fi

# Main part #
[ ! -f $FILE ] && logger -t $APPNAME "File $FILE not found, creating it now" && touch $FILE
# TODO: check format of file (eg first line is of the correct format)

ALREADYLOGGEDINTODAY=`grep $TODAY $FILE`
LASTSLEEPTIME=`tail -n 1 $FILE | awk -F "$TIMESEPARATOR" '{if (NF%2 == 0) {print $NF}}'` 
if [ ! -z "$LASTSLEEPTIME" ]
then
	LASTSLEEPTIMESTAMP=`date -j -f "%T" "${LASTSLEEPTIME}" "+%s"`
fi
LASTWORKINGDAY=`tail -n 1 $FILE | awk -F " " '{print $1}'`

if [ -z "$ALREADYLOGGEDINTODAY" ]
then
	logger -t $APPNAME "Writing last shutdown time to $FILE"
	LASTSHUTDOWNTIMESTAMP=`tail -r /private/var/log/system.log | grep -m 1 $SHUTDOWNPATTERN | awk -F "$SHUTDOWNPATTERN" '{print $2}' | awk '{print $1}'`
	LASTSHUTDOWNTIME=`date -j -f "%s" $LASTSHUTDOWNTIMESTAMP "+%T"` 
	sed -i '' '$ s/$/'$TIMESEPARATOR$LASTSHUTDOWNTIME'/' $FILE
	# an alternative way to do this would be through last shutdown | head -n 1 but too slow and the format is not suitable for date to parse
	
	logger -t $APPNAME "Starting a new day"
	printf "%s %s" "$TODAY" "$TIME" >> $FILE

	if [[ ! -z $LASTWORKINGDAY ]]
	then
		sleep 2 # give some time for the notifications
		# Create results for previous working day	
		showSummary
	else
		osascript -e "display notification \"$APPNAME has started recording...\" with title \"Ahoy!\""
	fi
elif [[ (-z $LASTSLEEPTIME && "`isItLunchTime $NOW`" = true) ]]  
then
	# We are sleeping now while lunch time
	logger -t $APPNAME "Writing sleep time to $FILE"
	sed -i '' '$ s/$/'$TIMESEPARATOR$TIME'/' $FILE # printf "%s%s" "$TIMESEPARATOR" "$TIME" >> $FILE
elif [[ ! -z $LASTSLEEPTIME ]]
then 
	# We are waking up again
	if [[ $(( $NOW - $LASTSLEEPTIMESTAMP )) -lt THRESHOLD ]]
	then
		# Was not big enough to be considered a lunch break
		logger -t $APPNAME "Removing last sleep time from $FILE"
		sed -i '' '$ s/'$TIMESEPARATOR$LASTSLEEPTIME'//' $FILE
	else 
		logger -t $APPNAME "Writing new wake time to $FILE"
		sed -i '' '$ s/$/'$TIMESEPARATOR$TIME'/' $FILE
	
		sleep 2;	
		osascript -e "display notification \"Resuming recording...\" with title \"$APPNAME\""
	fi
fi
)
