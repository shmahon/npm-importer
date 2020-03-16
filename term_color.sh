#!/bin/bash

#
# Notes
#
#  its more common to see the terminal escape typed as '\033' instead of '\e'
#
#  you can use this by 
#
# Foreground Colors
#
fg_default="\e[39m"
fg_black="\e[30m"
fg_red="\e[31m"
fg_green="\e[32m"
fg_yellow="\e[33m"
fg_blue="\e[34m"
fg_magenta="\e[35m"
fg_cyan="\e[36m"
fg_lightgray="\e[37m"
fg_darkgray="\e[90m"
fg_lightred="\e[91m"
fg_lightgreen="\e[92m"
fg_lightyellow="\e[93m"
fg_lightblue="\e[94m"
fg_lightmagenta="\e[95m"
fg_lightcyan="\e[96m"
fg_white="\e[97m"


#
# Background Colors
#
bg_default="\e[49m"
bg_black="\e[40m"
bg_red="\e[41m"
bg_green="\e[42m"
bg_yellow="\e[43m"
bg_blue="\e[44m"
bg_magenta="\e[45m"
bg_cyan="\e[46m"
bg_lightgray="\e[47m"
bg_darkgray="\e[100m"
bg_lightred="\e[101m"
bg_lightgreen="\e[102m"
bg_lightyellow="\e[103m"
bg_lightblue="\e[104m"
bg_lightmagenta="\e[105m"
bg_lightcyan="\e[106m"
bg_white="\e[107m"



#
# Attributes
#
bright="\e[1m"
dim="\e[2m"
underlined="\e[4m"
blink="\e[5m"
reverse="\e[7m"
hidden="\e[8m"  # useful for password prompts
nobright="\e[21m"
nodim="\e[22m"
nounderlined="\e[24m"
noblink="\e[25m"
noreverse="\e[27m"
nohidden="\e[28m"
tab="\e["
resetall="\e[0m"
reset="$fg_default$bg_default$resetall"

function scrape_opts() {

	# name of script
	_name="${0##*/}"

	# use getopt to do most of the work
	TEMP=`getopt -q -o nh -n $_name -- "$@"`

	# debug
	#echo "TEMP :: >${TEMP}<"

	# catch errors
	if [ $? -ne 0 ]; then
		opts=""
	else

		# important! : this makes getopt's response be this scripts parameters
		eval set -- "$TEMP"

		while [ $# -gt 0 ]; do
			case "$1" in
				-n ) opts="${opts:=""} $1" ; shift ;;
				-- ) shift ; break ;;
				* ) magenta "invalid option: -${OPTARG} " >&2 ;;
				\?) red "invalid option: -${OPTARG} " >&2 ;;
			esac
		done
	fi

	# prepare globals
	OPTS="${opts:=""}"
	PARAMS="$@"

	# debug
	#echo "PARAMS :: >${PARAMS}<"
}

function indent() {
	/bin/echo -en "\e[$*G"
}

function cmode() {
	/bin/echo -en "$*"
}

function white() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_white"$PARAMS"$reset
}

function blue() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_blue"$PARAMS"$reset
}

function green() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_green"$PARAMS"$reset
}

function red() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_red"$PARAMS"$reset
}

function yellow() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_yellow"$PARAMS"$reset
}

function cyan() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_cyan"$PARAMS"$reset
}

function magenta() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_magenta"$PARAMS"$reset
}

function red() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	/bin/echo -e ${OPTS} $bright$fg_red"$PARAMS"$reset
}

function grey() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	#echo -e "options:\n$OPTS"
	#echo -e "paramaters:\n$PARAMS"

	/bin/echo -e ${OPTS} $bright$fg_darkgray"$PARAMS"$reset
}

function success() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	#echo "OPTS   => ${OPTS}"
	#echo "PARAMS => ${PARAMS}"
	#echo "opts   => ${opts}"

	eval set -- "$PARAMS"

	#echo "\$@ => $@"
	#echo "\$# => $#"

	# assume first parameter is the indent
	if [ $# -gt 0 ]; then
		indent $1
		shift
	else
		indent 60
	fi

	/bin/echo -en $bright$bg_black$fg_white"["$reset
	/bin/echo -en $bright$bg_black$fg_green"${1:-SUCCESS}"$reset
	/bin/echo -e ${OPTS} $bright$bg_black$fg_white"]"$reset
}

function failure() {
	unset OPTS PARAMS opts
	scrape_opts "$@"

	eval set -- "$PARAMS"

	# assume first parameter is the indent
	if [ $# -gt 0 ]; then
		indent $1
		shift
	else
		indent 60
	fi

	/bin/echo -en $bright$bg_black$fg_white"["$reset
	/bin/echo -en $bright$bg_black$fg_red"${1:-FAILURE}"$reset
	/bin/echo -e ${OPTS} $bright$bg_black$fg_white"]"$reset
}

function pass() {
	success ${1:-60} "PASS"
}

function fail() {
	failure ${1:-60} "FAIL"
}

