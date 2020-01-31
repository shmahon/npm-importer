#!/bin/bash
# vim: set ts=3 sw=3 autoindent smartindent:

# import our utilities
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
   . "$DIR/term_color.sh"


# These notes consider how to download a "release" of TOA
# for purposes of uploading it to codenest.


# ======================== [ function definitions ] ===========================

#---------------------------------

#---------------------------------
function usage() {

   green "Usage: $0 <npm package to import>"
   green "============================================================"
   grey  "  This script is intended to *import* an NPM package from   "
   grey  "  https://registry.npmjs.org without installing it or       "
   grey  "  requiring any elevated permissions, scan it for viruses,  "
   grey  "  and then upload it to our local npm-mpf registry (which   "
   grey  "  is *not* proxied and therefore a sanitary repository.     "
   grey  "                                                            "
   grey  "  Note:  this script will manipulate your .npmrc config-    "
   grey  "  ration during the importation process and then put it     "
   grey  "  back to the *expected* values.                            "
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
   TEMP=`getopt -o hd --long debug -n $name -- "$@"`
   # catch any errors from getopt
   if [ $? -ne 0 ]; then
      usage
   fi

   eval set -- "$TEMP"

   while [ $# -gt 0 ]; do

      case "$1" in

         # process an option without a required argument
         -d | --debug ) output=/dev/stdout ; shift ;;

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
      red "no npm package specified for import!"
		usage
   else
      NPMPACKAGE=$1
      green  "Importing $NPMPACKAGE package..."
   fi
   yellow "-------------------------------------------------------------------"
}


#---------------------------------

#  NOTE:  also need to get 
#         "peerDependencies"
#---------------------------------
function download_package() {

	# $1 is expected to be the 'quarantine' directory (one up from package)
	# $2 is expected to be the package name (directory name of package)

	cd $1

	grey "$(indent $align)Downloading package :: $2"
	#npmDownload -p "${NPMPACKAGE}" --dependencies -o ~/npm-quarantine
	npmDownload -p "$2" -o ~/npm-quarantine &> ${output}

	# grab a copy of the current registry setting : this should be the "secure"
	# one
	reg=$(npm config get registry)

	# check if NPM module uses a github repository that break 'npm view'
	npm view --json $2 repository &> ${output}

	# now get a list of all the dependencies that works for all repository
	# types (that I've tried so far).
	if [ $? -ne 0 ]; then
		grey "$(indent $((align+7)))$2 probably has a github repository url.  Trying alternate approach."
		npm config delete registry &> ${output}
		dependencies=$(npm view --json $2 dependencies | grep -vE "[{}]" | cut -d":" -f1 | tr -d '"')
		modules[${2}]="alternate"
	else
		dependencies=$(npm view --json $2 dependencies | grep -vE "[{}]" | cut -d":" -f1 | tr -d '"')
		modules[${2}]="verified"
	fi

	# reset to 'npm-mpf' registry
	npm config set registry $reg


	# only add the new dependency if its not already in our list of modules
	for dep in $dependencies
	do
		if [[ ! -z "${modules[${dep}]:-}" ]]; then
			cyan "$(indent $((align+3)))$dep is already in our list of modules"
		else
			#cyan "$(indent $((align+3)))adding $dep to list of modules"
			magenta "$(indent $((align+3)))$dep"
			modules[${dep}]="not verified"
		fi

		# mark as 'installed' if already in registry
		npm view --json $dep repository &> ${output}
		if [ $? -eq 0 ]; then
			modules[${dep}]="published"
		fi
	done

	((align+=3))
	# recursively download all dependencies
	for dep in $dependencies
	do
		cyan "$(indent $((align+5)))modules[${dep}] = ${modules[${dep}]}"
		if [[ "${modules[${dep}]}" == "not verified" ]]; then
			download_package $1 $dep
		fi
	done
	((align-=3))
}


#---------------------------------

#---------------------------------
function publish_module() {

	pushd $PWD &> ${output}
	cd $1
	tball_cnt=$(find $2 -name "$2*.tgz" | wc -l)
	if [[ $tball_cnt -lt 1 ]]; then
		red "no download packages found for $2.  skipping."
		return
	elif [ $tball_cnt -gt 1 ]; then
		red "more than one download package found for $2.  skipping."
		return
	else
		tball=$(find $2 -name "$2*.tgz")
		yellow "publishing ${tball}"

		npm publish ${tball} --registry=$3 --access public

		success	
	fi

	popd &> ${output}
}


#---------------------------------

#---------------------------------
function report() {

	# just create a module report
	magenta "Module and Dependency Report:"
	white   "--------------------------------------------"
	for key in ${!modules[@]}
	do
		blue "$key $(indent 20)-> ${modules[${key}]}"
	done
	white   "--------------------------------------------"
}

# ======================== [ script begins here ] ===========================

NPMPACKAGE=""
output=/dev/null
align=0

declare -A modules  # an array with modules[<package name>] = <status>
declare -A devdeps  # an array with devdeps[<package name>] = <status>

# need to make sure 'grep' isn't aliased
unalias grep &> ${output}

parse_args $@

LOGFILE="${NPMPACKAGE}_clam.log"

#--------------------------------------
# ensure proper NPM configuration
#--------------------------------------
npm config set proxy "http://nexus.vsi-corp.com:8888"
npm config set https-proxy "http://nexus.vsi-corp.com:8888"
npm config set registry "http://nexus.vsi-corp.com:8888/repository/npm-mpf/"
npm config set strict-ssl false
 
#--------------------------------------
# ensure local installation
#    - no escalated privileges
#--------------------------------------
cd ${HOME}
mkdir -p ~/.global-modules
npm config set prefix "~/.global-modules"
export PATH=~/.global-modules/bin:$PATH

# make sure that our npm-package-downloader tool is installed
which npmDownload > ${output} 2>&1
if [ $? -ne 0 ]; then
	green "installing npm-package-downloader from $(npm config get registry)."
	npm install -g npm-package-downloader >& ${output}
	grey  "\tdone."
fi


#
# quarantine directory
#
if [ -d ~/npm-quarantine ]; then
	cyan "This script will erase and recreate ~/npm-quarantine to use as a"
	cyan "  sanitary sandbox."

	while true; do
		cmode $fg_magenta
		read -p "Do you confirm that it is OK? [Y/N] :: " yn

		# verify response
		case $yn in
			[Y]* ) break;;
			[N]* ) red "   exiting." ; exit 1 ;;
            * ) grey "  Please answer Yes or No";;
		esac
	done
	cmode $reset

	rm -rf ~/npm-quarantine
fi

# recreate the clean sandbox
mkdir -p ~/npm-quarantine
 
# temporarily open up our registry to hit npm
npm config delete proxy
npm config delete https-proxy
 
# download the package with dependencies.
download_package ~/npm-quarantine ${NPMPACKAGE} 
success

report

# set our registry correctly again
npm config set proxy http://nexus.vsi-corp.com:8888/
npm config set https-proxy http://nexus.vsi-corp.com:8888/
 
# scan the downloaded software
cd ~/npm-quarantine
green -n "Scanning for viruses ::"
clamscan -ri ~/npm-quarantine &> "${LOGFILE}"

# get the value of "Infected lines" 
MALWARE=$(tail "${LOGFILE}" | grep Infected |cut -d" " -f3) 

# if the value is not equal to zero, abort!!
if [ "$MALWARE" -ne "0" ];then 
	failure
	red "Malware has been detected while scanning ${NPMPACKAGE}!"
	red "$(indent 3)Aborting the import."
	yellow "$(indent 5)$NPMPACKAGE will be kept in ~/npm-quarantine."
	yellow "$(indent 5)Notify an SA immediately to report malware detection."
	exit 1
else
	success
fi 


# add credentials to MPF hosted npm registry
green "Publishing $NPMPACKAGE and its dependencies to 'npm-mpf' nexus repo"

# this requires your Crowd credentials
magenta "Please verify your credentials ::"
npm adduser --registry=http://nexus.vsi-corp.com:8888/repository/npm-mpf/  
 
for key in ${!modules[@]}
do
	# skip modules that have already been published
   if [[ "${modules[${key}]}" == "published" ]]; then
		continue
   fi

	# this handles NPM packages with a github repository
	reg=$(npm config get registry)
	if [[ "${modules[${key}]}" == "alternate" ]]; then
		npm config delete registry &> ${output} 
	fi

#
#
# This script isn't working because I'm not downloading the
# development dependencies and installing them first.  As such,
# when I go to publish the packages, they can't be built and pushed.
#
#
	publish_module ~/npm-quarantine ${key} $reg
	modules[${key}]="published"

	# reset the registry to normal 'npm-mpf'
	npm config set registry $reg
done
