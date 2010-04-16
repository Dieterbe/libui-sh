#!/bin/bash
# TODO: implement 'retry until user does it correctly' everywhere
# TODO: at some places we should check if $1 etc is only 1 word because we often depend on that
# TODO: standardize. eg everything $1= question/title, $2=default. also default should probably be 'no' for no default everywhere
# TODO: figure out something to make dia windows always big enough, yet fit nicely in the terminal


# you should call this function when you want to use this library (can be called multiple times, to change ui type or other settings)
# $1 ui type (dia or cli). defaults to cli
# $2 directory for tmp files. default /tmp (leave empty for default)
# $3 logfile (or string of logfiles, separated by whitespace) (leave empty to disable logging)
# $4 debug categories (leave empty to disable debugging) (an array of categories you will use in debug calls. useful when grepping logfiles)
# this library uses the UI debug category internally, you don't need to specify it. we add it automatically
libui-sh-init ()
{
	LIBUI_UI=${1:-cli}
	[ "$LIBUI_UI" == 'dialog' ] && ! which dialog &>/dev/null && die_error "Required dependency dialog not found"
	LIBUI_TMP_DIR=/tmp
	if [ -n "$2" ]; then
		LIBUI_TMP_DIR=$2
	fi
	LIBUI_LOG=0
	if [ -n "$3" ]; then
		LIBUI_LOG=1
		LIBUI_LOG_FILE="$3"
	fi
	LIBUI_DEBUG=0
	shift 3
	if [ -n "$1" ]; then
		LIBUI_DEBUG=1
		LIBUI_DEBUG_CATEGORIES=("$@")
		check_is_in 'UI' "${LIBUI_DEBUG_CATEGORIES[@]}" || LIBUI_DEBUG_CATEGORIES+=('UI')
	fi
	LIBUI_DIA_SUCCESSIVE_ITEMS=$LIBUI_TMP_DIR/libui-sh-dia-successive-items
	LIBUI_FOLLOW_PID=$LIBUI_TMP_DIR/libui-sh-follow-pid
	LIBUI_DIA_MENU_TEXT="Use the UP and DOWN arrows to navigate menus.  Use TAB to switch between buttons and ENTER to select."
}


## Helper functions ##
# $1 needle
# $2 set (array) haystack
check_is_in ()
{
	[ -z "$1" ] && die_error "check_is_in needs a non-empty needle as \$1 and a haystack as \$2!(got: check_is_in '$1' '$2'" # haystack can be empty though

	local needle="$1" element
	shift
	for element
	do
		[[ $element = $needle ]] && return 0
	done
	return 1
}


### Functions that your code can use. Cli/dialog mode is fully transparant.  This library takes care of it ###
# you could write your own functions implementing other things (kdedialogs, zenity dialogs, ..),
# - just implement the functions below
# - source your library
# - libui-sh-init with the correct UI type


# display error message and die
# Do not call other functions like debug, notify, .. here because that might cause loops!
die_error ()
{
	echo "ERROR: $@" >&2
	exit 2
}


# display warning message
# $1 title
# $2 item to show
# $3 type of item.  msg or text if it's a file. (optional. defaults to msg)
show_warning ()
{
	[ -z "$1" ] && die_error "show_warning needs a title"
	[ -z "$2" ] && die_error "show_warning needs an item to show"
	[ -n "$3" -a "$3" != msg -a "$3" != text ] && die_error "show_warning \$3 must be text or msg"
	type=msg
	[ -n "$3" ] && type=$3
	debug 'UI' "show_warning '$1': $2 ($type)"
	[ `type -t _${LIBUI_UI}_show_warning` == function ] || die_error "_${LIBUI_UI}_show_warning is not a function"
	_${LIBUI_UI}_show_warning "$1" "$2" $type
}


#notify user
notify ()
{
	debug 'UI' "notify: $@"
	[ `type -t _${LIBUI_UI}_notify` == function ] || die_error "_${LIBUI_UI}_notify is not a function"
	_${LIBUI_UI}_notify "$@"
}


# like notify, but user does not need to confirm explicitly when in dia mode
# $1 str
# $2 0/<listname> this inform call is part of a successive list of things (eg repeat previous things, keep adding items to a list) (only needed for dia, cli does this by design).
#   You can keep several "lists of successive things" by grouping them with <listname>
#   this is somewhat similar to follow_progress.  Note that this list isn't cleared unless you set $3 to 1.  default 0. (optional).
# $3 0/1 this is the last one of the group of several things (eg clear buffer).  default 0. (optional)
inform () #TODO: when using successive things, the screen can become full and you only see the old stuff, not the new
{
	successive=${2:-0}
	succ_last=${3:-0}
	debug 'UI' "inform: $1"
	[ `type -t _${LIBUI_UI}_inform` == function ] || die_error "_${LIBUI_UI}_inform is not a function"
	_${LIBUI_UI}_inform "$1" $successive $succ_last
}

# logging of stuff
log ()
{
	[ "$LIBUI_LOG" = 1 ] || return;
	for file in $LIBUI_LOG_FILE; do
		[ -z "$file" ] && continue;
		dir=$(dirname $file)
		mkdir -p $dir || die_error "Cannot create log directory $dir"
		str="[LOG] `date +"%Y-%m-%d %H:%M:%S"` $@"
		echo -e "$str" >> $file || die_error "Cannot log $str to $file"
	done
}


# $1 = one or more debug categories (must be in a list of specified categories. see init function) (separated by spaces)
#      Useful when grepping in the logfile
# $2 = string to log
debug ()
{
	[ "$LIBUI_DEBUG" = "1" ] || return;
	[ -n "$1" ] || die error "you must specify at least one (non-empty) debug category"
	[ -n "$2" ] || die_error "debug \$2 cannot be empty"
	for cat in $1
	do
		check_is_in $cat "${LIBUI_DEBUG_CATEGORIES[@]}" || die_error "debug \$1 contains a value ($cat) which is not a valid debug category"
	done
	for file in $LIBUI_LOG_FILE; do
		[ -z "$file" ] && continue;
		dir=$(dirname $file)
		mkdir -p $dir || die_error "Cannot create log directory $dir"
		str="[DEBUG $1 ] $2"
		echo -e "$str" >> $file || die_error "Cannot debug $str to $file"
	done
}



# ask for a timezone.
# this is pretty similar to how tzselect looks, but we support dia+cli + we don't actually change the clock + we don't show a date/time and ask whether it's okay. that comes later.
ask_timezone ()
{
	REGIONS=""
	for i in $(grep '^[A-Z]' /usr/share/zoneinfo/zone.tab | cut -f 3 | sed -e 's#/.*##g'| sort -u); do
		REGIONS="$REGIONS $i -"
	done
	while true; do
		ask_option no "Please select a region" '' required $REGIONS || return 1
		region=$ANSWER_OPTION
		ZONES=""
		for i in $(grep '^[A-Z]' /usr/share/zoneinfo/zone.tab | grep $region/ | cut -f 3 | sed -e "s#$region/##g"| sort -u); do
			ZONES="$ZONES $i -"
		done
		ask_option no "Please select a timezone" '' required $ZONES || return 1
		zone=$ANSWER_OPTION
		ANSWER_TIMEZONE="$region/$zone" && return
	done
}


# ask the user to make a selection from a certain group of things
# $1 question
# shift;shift; $@ list of options. first tag, then item then ON/OFF. if item == ^ or - it will not be shown in cli mode.
# for nostalgic reasons, you can set item to ^ for ON items and - for OFF items. afaik this doesn't have any meaning other then extra visual separation though
ask_checklist ()
{
	[ -z "$1" ] && die_error "ask_checklist needs a question!"
	[ -z "$4" ] && debug 'UI' "ask_checklist args: $@" && die_error "ask_checklist makes only sense if you specify at least 1 thing (tag,item and ON/OFF switch)"
	[ `type -t _${LIBUI_UI}_ask_checklist` == function ] || die_error "_${LIBUI_UI}_ask_checklist is not a function"
	_${LIBUI_UI}_ask_checklist "$@"
}


ask_datetime ()
{
	[ `type -t _${LIBUI_UI}_ask_datetime` == function ] || die_error "_${LIBUI_UI}_ask_datetime is not a function"
	_${LIBUI_UI}_ask_datetime "$@"
}


# ask for a number.
# $1 question
# $2 lower limit (optional)
# $3 upper limit (optional. set 0 for none)
# $4 default (optional)
# sets $ANSWER_NUMBER to the number the user specified
# returns 1 if the user cancelled or did not enter a numeric, 0 otherwise
ask_number ()
{
	[ -z "$1" ] && die_error "ask_number needs a question!"
	[ -n "$2" ] && [[ "$2" = *[^0-9]* ]] && die_error "ask_number \$2 must be a number! not $2"
	[ -n "$3" ] && [[ "$3" = *[^0-9]* ]] && die_error "ask_number \$3 must be a number! not $3"
	[ -n "$4" ] && [[ "$4" = *[^0-9]* ]] && die_error "ask_number \$4 must be a number! not $4"
	[ `type -t _${LIBUI_UI}_ask_number` == function ] || die_error "_${LIBUI_UI}_ask_number is not a function"
	_${LIBUI_UI}_ask_number "$1" $2 $3 $4
}


# ask the user to choose something
# $1 default item (set to 'no' for none)
# $2 title
# $3 additional explanation (default: '')
# $4 type (required or optional). '' means required. cancel labels will be 'Cancel' and 'Skip' respectively.
# shift 4 ; $@ list of options. first tag. then name. (eg tagA itemA "tag B" 'item B' )

# $ANSWER_OPTION : selected answer (if none selected: default (if available), or empty string otherwise). if user hits cancel or skip, this is an empty string.
# $?             : 0 if the user selected anything or skipped (when optional), when user cancelled: 1
ask_option ()
{
	[ `type -t _${LIBUI_UI}_ask_option` == function ] || die_error "_${LIBUI_UI}_ask_option is not a function"
	_${LIBUI_UI}_ask_option "$@"
}


# ask the user a password. return is stored in $PASSWORD or $<TYPE>_PASSWORD
# $1 type (optional.  eg 'svn', 'ssh').
ask_password ()
{
	[ `type -t _${LIBUI_UI}_ask_password` == function ] || die_error "_${LIBUI_UI}_ask_pasword is not a function"
	_${LIBUI_UI}_ask_password "$@"
}


# ask for a string.
# $1 question
# $2 default (optional)
# $3 exitcode to use when string is empty and there was no default, or default was ignored (1 default)
# Sets $ANSWER_STRING to response.
# returns 1 if the user cancelled, 0 otherwise
ask_string ()
{
	[ -z "$1" ] && die_error "ask_string needs a question!"
	[ `type -t _${LIBUI_UI}_ask_string` == function ] || die_error "_${LIBUI_UI}_ask_string is not a function"
	_${LIBUI_UI}_ask_string "$1" "$2" "$3"
}


# ask a yes/no question.
# $1 question
# $2 default answer yes/no (optional)
# returns 0 if response is yes/y (case insensitive).  1 otherwise
ask_yesno ()
{
	[ -z "$1" ] && die_error "ask_yesno needs a question!"
	[ `type -t _${LIBUI_UI}_ask_yesno` == function ] || die_error "_${LIBUI_UI}_ask_yesno is not a function"
	_${LIBUI_UI}_ask_yesno "$@"
}





# follow the progress of something by showing it's log, updating real-time
# $1 title
# $2 logfile
# $3 pid to monitor. if process stopped, stop following (only used in cli mode)
follow_progress ()
{
	[ -z "$1" ] && die_error "follow_progress needs a title!"
	[ -z "$2" ] && die_error "follow_progress needs a logfile to follow!"
	FOLLOW_PID=
	[ `type -t _${LIBUI_UI}_follow_progress` == function ] || die_error "_${LIBUI_UI}_follow_progress is not a function"
	_${LIBUI_UI}_follow_progress "$@"
}






### Internal functions, supposed to be only used internally in this library ###


# DIALOG() taken from setup
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dia_dialog()
{
	dialog --backtitle "$TITLE" --aspect 15 "$@" 3>&1 1>&2 2>&3 3>&-
}


_dia_show_warning ()
{
	_dia_dialog --title "$1" --exit-label "Continue" --$3box "$2" 0 0 || die_error "dialog could not show --$3box $2. often this means a file does not exist"
}


_dia_notify ()
{
	_dia_dialog --msgbox "$@" 0 0
}


_dia_inform ()
{
	str="$1"
	if [ "$2" != 0 ]
	then
		echo "$1" >> $LIBUI_DIA_SUCCESSIVE_ITEMS-$2
		str=`cat $LIBUI_DIA_SUCCESSIVE_ITEMS-$2`
	fi
	[ "$3" = 1 ] && rm $LIBUI_DIA_SUCCESSIVE_ITEMS-$2
	_dia_dialog --infobox "$str" 0 0
}


_dia_ask_checklist ()
{
	str=$1
	shift
	list=
	while [ -n "$1" ]
	do
		[ -z "$2" ] && die_error "no item given for element $1"
		[ -z "$3" ] && die_error "no ON/OFF switch given for element $1 (item $2)"
		[ "$3" != ON -a "$3" != OFF ] && die_error "element $1 (item $2) has status $3 instead of ON/OFF!"
		list="$list $1 $2 $3"
		shift 3
	done
	ANSWER_CHECKLIST=$(_dia_dialog --checklist "$str" 0 0 0 $list)
	local ret=$?
	debug 'UI' "_dia_ask_checklist: user checked ON: $ANSWER_CHECKLIST"
	return $ret
}


_dia_ask_datetime ()
{
	# display and ask to set date/time
	local _date _time
	_date=$(_dia_dialog --calendar "Set the date.\nUse <TAB> to navigate and arrow keys to change values." 0 0 0 0 0) || return 1 # form like: 07/12/2008
	_time=$(_dia_dialog --timebox "Set the time.\nUse <TAB> to navigate and up/down to change values." 0 0) || return 1 # form like: 15:26:46
	debug 'UI' "Date as specified by user $_date time: $_time"

	# DD/MM/YYYY hh:mm:ss -> MMDDhhmmYYYY.ss (date default format, set like date $ANSWER_DATETIME)  Not enabled because there is no use for it i think.
	# ANSWER_DATETIME=$(echo "$_date" "$_time" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\2\1\4\5\3\6#g')
	# DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss ( date string format, set like date -s "$ANSWER_DATETIME")
	ANSWER_DATETIME="$(echo "$_date" "$_time" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
}


_dia_ask_number ()
{
	#TODO: i'm not entirely sure this works perfectly. what if user doesnt give anything or wants to abort?
	while true
	do
		str="$1"
		[ -n $2 ] && str2="min $2"
		[ -n $3 -a $3 != '0' ] && str2="$str2 max $3"
		[ -n "$str2" ] && str="$str ( $str2 )"
		ANSWER_NUMBER=$(_dia_dialog --inputbox "$str" 0 0 $4)
		local ret=$?
		if [[ $ANSWER_NUMBER = *[^0-9]* ]] #TODO: handle exit state
		then
			show_warning 'Invalid number input' "$ANSWER_NUMBER is not a number! try again."
		else
			if [ -n "$3" -a $3 != '0' -a $ANSWER_NUMBER -gt $3 ]
			then
				show_warning 'Invalid number input' "$ANSWER_NUMBER is bigger then the maximum,$3! try again."
			elif [ -n "$2" -a $ANSWER_NUMBER -lt $2 ]
			then
				show_warning 'Invalid number input' "$ANSWER_NUMBER is smaller then the minimum,$2! try again."
			else
				break
			fi
		fi
	done
	debug 'UI' "_dia_ask_number: user entered: $ANSWER_NUMBER"
	[ -z "$ANSWER_NUMBER" ] && return 1
	return $ret
}


_dia_ask_option ()
{
	DEFAULT=""
	[ "$1" != 'no' ] && DEFAULT="--default-item $1"
	[ -z "$2" ] && die_error "ask_option \$2 must be the title"
	# $3 is optional more info
	TYPE=${4:-required}
	[ "$TYPE" != required -a "$TYPE" != optional ] && debug 'UI' "_dia_ask_option args: $@" && die_error "ask option \$4 must be required or optional or ''. not $TYPE"
	[ -z "$6" ] && debug 'UI' "_dia_ask_option args: $@" && die_error "ask_option makes only sense if you specify at least one option (with tag and name)" #nothing wrong with only 1 option.  it still shows useful info to the user

	DIA_MENU_TITLE=$2
	EXTRA_INFO=$3
	shift 4
	CANCEL_LABEL=Cancel
	[ $TYPE == optional ] && CANCEL_LABEL='Skip'
	ANSWER_OPTION=$(_dia_dialog $DEFAULT --cancel-label $CANCEL_LABEL --colors --title " $DIA_MENU_TITLE " --menu "$LIBUI_DIA_MENU_TEXT $EXTRA_INFO" 0 0 0 "$@")
	local ret=$?
	debug 'UI' "dia_ask_option: ANSWER_OPTION: $ANSWER_OPTION, returncode (skip/cancel): $ret ($DIA_MENU_TITLE)"
	[ $TYPE == required ] && return $ret
	return 0 # TODO: check if dialog returned >0 because of an other reason then the user hitting 'cancel/skip'
}


_dia_ask_password ()
{
	if [ -n "$1" ]
	then
		type_l=`tr '[:upper:]' '[:lower:]' <<< $1`
		type_u=`tr '[:lower:]' '[:upper:]' <<< $1`
	else
		type_l=
		type_u=
	fi

	local ANSWER=$(_dia_dialog --passwordbox  "Enter your $type_l password" 8 65 "$2")
	local ret=$?
	[ -n "$type_u" ] && read ${type_u}_PASSWORD <<< $ANSWER
	[ -z "$type_u" ] && PASSWORD=$ANSWER
	echo $ANSWER
	debug 'UI' "_dia_ask_password: user entered <<hidden>>"
	return $ret
}


_dia_ask_string ()
{
	exitcode=${3:-1}
	ANSWER_STRING=$(_dia_dialog --inputbox "$1" 0 0 "$2")
	local ret=$?
	debug 'UI' "_dia_ask_string: user entered $ANSWER_STRING"
	[ -z "$ANSWER_STRING" ] && return $exitcode
	return $ret
}



_dia_ask_yesno ()
{
	local default
	str=$1
	# If $2 contains an explicit 'no' we set defaultno for yesno dialog
	[ "$2" == "no" ] && default="--defaultno"
	dialog $default --yesno "$str" 0 0 # returns 0 for yes, 1 for no
	local ret=$?
	[ $ret -eq 0 ] && debug 'UI' "dia_ask_yesno: User picked YES"
	[ $ret -gt 0 ] && debug 'UI' "dia_ask_yesno: User picked NO"
	return $ret
}


_dia_follow_progress ()
{
	title=$1
	logfile=$2

	_dia_dialog --title "$1" --no-kill --tailboxbg "$2" 0 0 >$LIBUI_FOLLOW_PID
	FOLLOW_PID=`cat $LIBUI_FOLLOW_PID`
	rm $LIBUI_FOLLOW_PID

	# I wish something like this would work.  anyone who can explain me why it doesn't get's to be contributor of the month.
	# FOLLOW_PID=`_dia_dialog --title "$1" --no-kill --tailboxbg "$2" 0 0 2>&1 >/dev/null | head -n 1`

	# Also this doesn't work:
	# _dia_dialog --title "$1" --no-kill --tailboxbg "$2" 0 0 &>/dev/null &
	# FOLLOW_PID=$!

	# Also the new stdout-stderr-swapping isn't a clean solution for that. When command substitition is used bash will
	# wait until the command terminates, dialog's forking to background will fail.
	# FOLLOW_PID=$(_dia_dialog --title "$1" --no-kill --tailboxbg "$2" 0 0)
}




_cli_show_warning ()
{
	echo "WARNING: $1"
	[ "$3" = msg  ] && echo -e "$2"
	[ "$3" = text ] && (cat $2 || die_error "Could not cat $2")
}


_cli_notify ()
{
	echo -e "$@"
}


_cli_inform ()
{
	echo -e "$1"
}


_cli_ask_checklist ()
{
	str=$1
	shift
	output=
	while [ -n "$1" ]
	do
		[ -z "$2" ] && die_error "no item given for element $1"
		[ -z "$3" ] && die_error "no ON/OFF switch given for element $1 (item $2)"
		[ "$3" != ON -a "$3" != OFF ] && die_error "element $1 (item $2) has status $3 instead of ON/OFF!"
		item=$1
		[ "$2" != '-' -a "$2" != '^' ] && item="$1 ($2)"
		[ "$3" = ON  ] && ask_yesno "Enable $1 ?" yes && output="$output $1"
		[ "$3" = OFF ] && ask_yesno "Enable $1 ?" no  && output="$output $1" #TODO: for some reason, default is always N when asked to select packages
		shift 3
	done
	ANSWER_CHECKLIST=$output
	return 0
}


_cli_ask_datetime ()
{
	ask_string "Enter date [YYYY-MM-DD hh:mm:ss]"
	ANSWER_DATETIME=$ANSWER_STRING
	debug 'UI' "Date as picked by user: $ANSWER_STRING"
}


_cli_ask_number ()
{
	#TODO: i'm not entirely sure this works perfectly. what if user doesnt give anything or wants to abort?
	while true
	do
		str="$1"
		[ -n $2 ] && str2="min $2"
		[ -n $3 -a $3 != '0' ] && str2="$str2 max $3"
		[ -n $4 ] && str2=" default $4"
		[ -n "$str2" ] && str="$str ( $str2 )"
		echo "$str"
		read ANSWER_NUMBER
		if [[ $ANSWER_NUMBER = *[^0-9]* ]]
		then
			show_warning 'Invalid number input' "$ANSWER_NUMBER is not a number! try again."
		else
			if [ -n "$3" -a $3 != '0' -a $ANSWER_NUMBER -gt $3 ]
			then
				show_warning 'Invalid number input' "$ANSWER_NUMBER is bigger then the maximum,$3! try again."
			elif [ -n "$2" -a $ANSWER_NUMBER -lt $2 ]
			then
				show_warning 'Invalid number input' "$ANSWER_NUMBER is smaller then the minimum,$2! try again."
			else
				break
			fi
		fi
	done
	debug 'UI' "cli_ask_number: user entered: $ANSWER_NUMBER"
	[ -z "$ANSWER_NUMBER" ] && return 1
	return 0
}


_cli_ask_option ()
{
	#TODO: strip out color codes
	#TODO: if user entered incorrect choice, ask him again
	DEFAULT=
	[ "$1" != 'no' ] && DEFAULT=$1 #TODO: if user forgot to specify a default (eg all args are 1 pos to the left, we can end up in an endless loop :s)
	[ -z "$2" ] && die_error "ask_option \$2 must be the title"
	# $3 is optional more info
	TYPE=${4:-required}
	[ "$TYPE" != required -a "$TYPE" != optional ] && debug 'UI' "_dia_ask_option args: $@" && die_error "ask option \$4 must be required or optional or ''. not $TYPE"
	[ -z "$6" ] && debug 'UI' "_dia_ask_option args: $@" && die_error "ask_option makes only sense if you specify at least one option (with tag and name)" #nothing wrong with only 1 option.  it still shows useful info to the user

	MENU_TITLE=$2
	EXTRA_INFO=$3
	shift 4

	echo "$MENU_TITLE"
	[ -n "$EXTRA_INFO" ] && echo "$EXTRA_INFO"
	while [ -n "$1" ]
	do
		echo "$1 ] $2"
		shift 2
	done
	CANCEL_LABEL=CANCEL
	[ $TYPE == optional ] && CANCEL_LABEL=SKIP
	echo "$CANCEL_LABEL ] $CANCEL_LABEL"
	[ -n "$DEFAULT" ] && echo -n " > [ $DEFAULT ] "
	[ -z "$DEFAULT" ] && echo -n " > "
	read ANSWER_OPTION
	local ret=0
	[ -z "$ANSWER_OPTION" -a -n "$DEFAULT" ] && ANSWER_OPTION="$DEFAULT"
	[ "$ANSWER_OPTION" == CANCEL ] && ret=1 && ANSWER_OPTION=
	[ "$ANSWER_OPTION" == SKIP   ] && ret=0 && ANSWER_OPTION=
	[ -z "$ANSWER_OPTION" -a "$TYPE" == required ] && ret=1

	debug 'UI' "cli_ask_option: ANSWER_OPTION: $ANSWER_OPTION, returncode (skip/cancel): $ret ($MENU_TITLE)"
	return $ret
}


_cli_ask_password ()
{
	if [ -n "$1" ]
	then
		type_l=`tr '[:upper:]' '[:lower:]' <<< $1`
		type_u=`tr '[:lower:]' '[:upper:]' <<< $1`
	else
		type_l=
		type_u=
	fi

	echo -n "Enter your $type_l password: "
	stty -echo
	[ -n "$type_u" ] && read ${type_u}_PASSWORD
	[ -z "$type_u" ] && read PASSWORD
	stty echo
	echo
}


# $3 -z string behavior: always take default if applicable, but if no default then $3 is the returncode (1 is default)
_cli_ask_string ()
{
	exitcode=${3:-1}
	echo "$1: "
	[ -n "$2" ] && echo "(Press enter for default.  Default: $2)"
	echo -n ">"
	read ANSWER_STRING
	debug 'UI' "cli_ask_string: User entered: $ANSWER_STRING"
	if [ -z "$ANSWER_STRING" ]
	then
		if [ -n "$2" ]
		then
			ANSWER_STRING=$2
		else
			return $exitcode
		fi
	fi
	return 0
}


_cli_ask_yesno ()
{
	[ -z "$2"    ] && echo -n "$1 (y/n): "
	[ "$2" = yes ] && echo -n "$1 (Y/n): "
	[ "$2" = no  ] && echo -n "$1 (y/N): "

	read answer
	answer=`tr '[:upper:]' '[:lower:]' <<< $answer`
	if [ "$answer" = y -o "$answer" = yes ] || [ -z "$answer" -a "$2" = yes ]
	then
		debug 'UI' "cli_ask_yesno: User picked YES"
		return 0
	else
		debug 'UI' "cli_ask_yesno: User picked NO"
		return 1
	fi
}


_cli_follow_progress ()
{
	title=$1
	logfile=$2
	echo "Title: $1"
	[ -n "$3" ] && tail -f $2 --pid=$3
	[ -z "$3" ] && tail -f $2
}
