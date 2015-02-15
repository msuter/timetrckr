#!/bin/sh

# Settings #
FILE=time.csv
LUNCHTIME="11:30:00-13:30:00"
THRESHHOLD=`echo 10*60 | bc` # 10 minutes
TIMESEPARATOR=";" 

# Variables #
TODAY=`date "+%Y-%m-%d"`
TIME=`date "+%H:%M:%S"`
NOW=`date +%s` # timestamp

[ ! -f $FILE ] && echo "File $FILE not found!\n Creating it now!" && touch $FILE

# TODO: check format of file (eg first line is of the correct format)

ALREADYLOGGEDINTODAY=`grep $TODAY $FILE`
LASTSLEEPTIME=`tail -n 1 $FILE | awk -F "$TIMESEPARATOR" '{if (NF%2 == 0) {print $NF}}'` 
if [ -z "$LASTSLEEPTIME" ]
then 
	NEWDAYORWILLSLEEPNOW=1
else
	LASTSLEEPTIMESTAMP=`date -j -f "%H:%M:%S" "${LASTSLEEPTIME}" "+%s"`
fi

if [ -z "$ALREADYLOGGEDINTODAY" ]
then
	# It's a new day, you look great today
	printf "%s %s" "$TODAY" "$TIME" > $FILE
elif [[ ! -z $NEWDAYORWILLSLEEPNOW || $(($NOW - $LASTSLEEPTIMESTAMP)) -gt $THRESHHOLD ]]
then
	printf "%s%s" "$TIMESEPARATOR" "$TIME" >> $FILE
fi

unset LASTSLEEPTIME
unset NEWDAYORWILLSLEEPNOW
