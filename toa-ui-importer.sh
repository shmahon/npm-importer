#!/bin/bash
# vim: set ts=3 sw=3 autoindent smartindent:

# This script should just process a 'package.json' file install
# all the development and production dependencies.


# import our utilities
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
   . "$DIR/term_color.sh"


# ======================== [ function definitions ] ===========================

#---------------------------------

#---------------------------------
function usage() {

   green "Usage: $0 <package.json file>"
   green "============================================================"
   grey  "  This script is intended to use the 'npm-importer'         "
   grey  "  script to import all the development and production       "
   grey  "  dependencies required by a package.json file.             "
	grey  "                                                            "
	red   "  YOU ARE RESPONSIBLE TO VERIFY THE FOLLOWING:              "
   grey  "                                                            "
   grey  "      - you understand what this script is doing!           "
   grey  "      - you ensure that the virus scan is clean!            "
   grey  "      - you ensure that your NPM configuration is valid     "
   grey  "        after the completion of this script: your registry  "
   grey  "        must point to 'npm-mpf'!                            "
   grey  "                                                            "
   grey  "  -d | --debug                                              "
   grey  "       allow stdout to go to the terminal instead of        "
   grey  "       /dev/null                                            "
   grey  "                                                            "
   grey  "  --nocred                                                  "
   grey  "       assume that the user has already registered          "
   grey  "       credentials for the NPM registry and do not ask      "
   grey  "       to do it again.                                      "
   grey  "       assume that the user has already registered          "
   grey  "                                                            "
   grey  "  -h : print the usage message and exit.                    "
   grey  "                                                            "
   green "============================================================"
   exit 1
}



#---------------------------------


#---------------------------------
function parse_args() {

   # get the simplified name of this script for getopt to use when reporting errors
   name="${0##*/}"

   # use getopt to do most of the work
   TEMP=`getopt -o hd --long debug,nocred -n $name -- "$@"`
   # catch any errors from getopt
   if [ $? -ne 0 ]; then
      usage
   fi

   eval set -- "$TEMP"

   while [ $# -gt 0 ]; do

      case "$1" in

         # process an option without a required argument
         -d | --debug ) output=/dev/stdout ; debugFlag=1; shift ;;

			# assume the user has already provided NPM registry credentials
			--nocred ) nocredFlag='true' ; shift ;;

         # print the usage message
         -h) shift ; usage; break ;;

         # get rid of '--'; the optional params will be in '$@'
         --) shift ; break ;;

         # handle an error case (have I seen this, yet?)
			*) red "invalid option: -${OPTARG} " >&2 ;;
      esac
   done

   # if not cleanup, then get a module argument to add to the venv
   if [ $# -lt 1 ]; then
		red "no npm module or package.json file specified for import!"
		usage
	else
		# is this a package.json file
		if [ -f $1 ] && [ $(basename $1) == "package.json" ]; then

			# process this as a 'package.json' file.
			jsonfile=$(basename $1)
			NPMDIR=$(dirname $(readlink -f $1) )

		elif [ -d $1 ] && [ -f $1/package.json ]; then

			# or is it a directory with a package.json file
			NPMDIR=$1
			jsonfile="package.json"
		else
			# refuse to process this input
			red "$1 is package.json file or a directory containing a package.json file"
			usage
		fi

		# use the package.json file to get the module name and version
		NPMPACKAGE=$(cat $NPMDIR/$jsonfile | jq -r '.name')
		NPMVERSION=$(cat $NPMDIR/$jsonfile | jq -r '.version')

		green  "Importing $NPMPACKAGE@$NPMVERSION package at $NPMDIR."
   fi
   yellow "-------------------------------------------------------------------"
}




#---------------------------------

#---------------------------------
function config_npmrc() {
	# $1 adjective indicating 'safe' or 'proxy' or 'open'
	if [ $# -eq 0 ]; then
		red "config_npmrc :: called with no arguments"
		white "$(indent 5)must provide one of the following:"
		white "$(indent 7)'safe'  - set .npmrc to point to npm-mpf repository"
		white "$(indent 7)'proxy' - set .npmrc to point to npm-proxy repository"
		white "$(indent 7)'open'  - set .npmrc to point to https://registry.npmjs.org/"
		exit
	fi

	case "$1" in

		# 'safe'  : point to http://nexus.vsi-corp.com:8888/repository/npm-mpf/
		#           normal state for 'secure' development
		safe )
		   white -n "$(indent 5)npmrc config :: "; green "safe";
			npm config set proxy "http://nexus.vsi-corp.com:8888";
			npm config set https-proxy "http://nexus.vsi-corp.com:8888";
			npm config set registry "http://nexus.vsi-corp.com:8888/repository/npm-mpf/";
			npm config set strict-ssl false; ;;
		# 'proxy' : point to http://nexus.vsi-corp.com:8888/repository/npm-proxy/
		#           used for caching local copies for evaluation
		proxy )
		   white -n "$(indent 5)npmrc config :: "; yellow "proxy";
			npm config set proxy "http://nexus.vsi-corp.com:8888";
			npm config set https-proxy "http://nexus.vsi-corp.com:8888";
			npm config set registry "http://nexus.vsi-corp.com:8888/repository/npm-proxy/";
			npm config set strict-ssl false; ;;
		# 'open'  : point to https://registry.npmjs.org/
		#           used for getting direct access to internet NPM registry for
		#           virus scanning
		open )
		   white -n "$(indent 5)npmrc config :: "; red "open";
			npm config delete proxy;
			npm config delete https-proxy;
			npm config delete registry;
			npm config delete strict-ssl; ;;

		* ) red "config_npmrc :: invalid paramater '$1' provided.  Aborting."; exit ;;
	esac
}


# ======================== [ script begins here ] ===========================

NPMPACKAGE=""
NPMVERSION=""
output=/dev/null
debugFlag=0
align=0
quarantine="/data/npm-quarantine"
jsonfile=package.json
nocredFlag='false'

declare -A modules   # an array with modules[<package name>,<package version>] = <status>
declare -A devdeps   # an array with devdeps[<package name>,<package version>] = <path>
declare -A modpaths  # an array with modpaths[<package name>,<package version] = <path>

# need to make sure 'grep' and 'ls' aren't aliased
unalias grep &> ${output}
unalias ls &> ${output}

parse_args $@

trap 'res=$?; exit $res' INT EXIT

#--------------------------------------
#  Begin the installation process
#--------------------------------------

# add NPM registry credentials now
#config_npmrc 'safe'
align=5
if [ $nocredFlag == "false" ]; then
	magenta "$(indent $align)Please verify your credentials for http://nexus.vsi-corp.com:8888/repository/npm-mpf/ ::"
	npm adduser --registry=http://nexus.vsi-corp.com:8888/repository/npm-mpf/  
fi

#
# Caution : npm set to access the internet registry
# 
while IFS== read -r key value;
do 

	# check for empty deps
	if [ -z $key ]; then
		echo "key => x${key}x"
		break
	fi

	# version fixup
	version=${value//[\^\~]/}
	grey "value = $value" &> ${output}
	grey "value = ${key}${version:+@$version}" &> ${output}
	
	# just use the npm-importer script
	dbgswitch="fred"
	if [ $debugFlag -gt 0 ]; then dbgswitch="-d"; else dbgswitch=""; fi
	grey "debugFlag = $debugFlag :: dbgswitch = $dbgswitch" &> ${output}
	npm-importer $dbgswitch --align 5 --nocred --rebuild-quarantine true $(echo "$key${value:+@$version}")

done < <(jq -r '.dependencies | to_entries | .[] | .key + "=" + .value ' $NPMDIR/$jsonfile); 
