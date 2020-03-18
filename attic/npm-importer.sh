#!/bin/bash
# vim: set ts=3 sw=3 autoindent smartindent:

# DEPENDENCIES:  you will need you yum install 'jq'
#                you will need 'yarn' installed

#
#
#  Approach as of 03/03/2020
#    1. install the package into a quarantine directory
#    2. I think this should install dependendencies in the 
#       'npm_modules' directory of the installed package.
#        Example:
#           url=$(npm view --json babylon@6.18.0 repository.url | tr -d '"'
#           commit=$(npm view --json babylon@6.18.0 gitHead | tr -d '"'
#           yarn add git+https://github.com/babel/babylon.git#da66d3f65b0d305c0bb042873d57f26f0c0b0538
#    3.  For every development dependency
#           cd ~/.global_modules/lib/babylon
#           # get a list of devDependencies  
#           dependencies=$(npm view --json $2 dependencies | \
#                     grep -vE "[{}]" | cut -d":" -f1 | tr -d '"')
#           for each dependency
#                npm install -g <dependency>
#
#    4.  For every 

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
   grey  "  You can specify a package simply like 'babel-core' or you "
   grey  "  can add a version such as 'babel-core@6.26.0'.            "
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
   TEMP=`getopt -o hd --long debug,dev -n $name -- "$@"`
   # catch any errors from getopt
   if [ $? -ne 0 ]; then
      usage
   fi

   eval set -- "$TEMP"

   while [ $# -gt 0 ]; do

      case "$1" in

         # process an option without a required argument
         -d | --debug ) output=/dev/stdout ; shift ;;

			--dev ) devFlag='true' ; shift ;;

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
      NPMPACKAGE=${1%%@[\^0-9]*}
		NPMVERSION=${1##*@}
		if [[ $NPMVERSION == $NPMPACKAGE ]]; then
			NPMVERSION=""
			green  "Importing $NPMPACKAGE package..."
		else
			green  "Importing $NPMPACKAGE version $NPMVERSION package..."
		fi
   fi
   yellow "-------------------------------------------------------------------"
}


#-----------------------------------
#
#
#-----------------------------------
function check_dep() {

	# $1 : the package name (with version if you require it)
   # $2 : type of dependency.  must be 'global' or 'local' 
	#      defaults to 'local'
	
	local pkgver=$1
	local package=${pkgver%%@[\^0-9]*}
	local version=${pkgver##*@}
	local scope=${2:-'local'}
	local res=1

	# version can be empty
	if [[ $version == $package ]]; then
		version=""
	fi

	((align+=3))
	grey "$(indent $align)check_dep :: running in $PWD :: checking $pkgver"
	grey ".dependencies.\"$package\".version :: $(npm ls $pkgver --depth=0 --json | jq '.dependencies."$package".version')" 
	grey "\"$package\".version               :: $(npm ls $pkgver --depth=0 --json | jq '."$package".version')" 
	case "$scope" in

		local )
			if [[ $(npm ls $pkgver --depth=0 --json | \
				   jq '.dependencies."$package".version') == $version ]]; then
				res=0; 
			fi ;;
		global )
			#grey "$(indent $align)check_dep( 'global' ) :: $1";
			if [[ $(npm ls $pkgver -g --depth=0 --json | \
				   jq '.dependencies."$package".version') == $version ]]; then
				res=0; 
			fi ;;
		* )
			# just default to 'local' scope
			magenta "$(indent $align)check_dep( $scope ) : invalid 'scope' provided; defaulting to 'local'.";
			if [[ $(npm ls $pkgver --depth=0 --json | \
				   jq '.dependencies."$package".version') == $version ]]; then
				res=0; 
			fi ;;
	esac
	((align-=3))

	# just return the result
	return $res
}

#-----------------------------------
#
#
#-----------------------------------
function install_devDependencies() {

	local jsonfile=$1
	local key
	local value

	# install all dependencies; package local installation
	while IFS== read -r key value;
	do

		# check for empty dev deps
		if [ -z $key ]; then
			echo "key => x${key}x"
			break
		fi

		# version fixup
		value=${value//[\^\~]/}

		# so, just install them here.
		blue -n "$(indent $align)   - "; white -n "installing $key@$value"

		# only add this dependency if not already in our list
		if [[ ! -z "${devdeps[${key},${value}]:-}" ]]; then
			red " x"
		else
			green " *"
			devdeps[${key},${value}]=modpaths[${NPMPACKAGE},${NPMVERSION}]/$key
		fi

		# already installed?
		check_dep $key@$value 'global'
		if [ $? -ne 0 ]; then
			npm install -g $key@$value &> ${output}
		else
			grey "$(indent $align)    already installed."
		fi

	done < <(jq -r 'to_entries | .[] | .key + "=" + .value ' $jsonfile);
}


#------------------------------------------------------------------
#  NOTE:  this function requires the 'jq' commandline tool
#
#  This function should be run at the $quarantine/node_module
#  level of the directory tree.
#------------------------------------------------------------------
function get_devDependencies() {

	# $1 is expected to be the 'quarantine' directory (one up from the package)
	# $2 is expected to be the npm package to scan for 
   #    development dependencies, including the version.
	local nodedir=$1
	local pkgver=$2

	# record where we started
	pushd $PWD &> ${output}

	# go to 'node_modules'
	cd $nodedir

	(( align+=3 ))
	magenta "$(indent $align)$pkgver :: dev dependencies"

	# now get a list of all the devDependencies from module's package.json 
	npm view --json $pkgver devDependencies > ./${pkgver%%@[\^0-9]*}/devDeps.json 2> ${output};
	if [ $? -ne 0 ]; then
		red "get_devDependencies :: error getting dev dependencies for $pkgver" 
		exit 1
	fi

	# check if no dev dependencies
	if [ ! -s ./${pkgver%%@[\^0-9]*}/devDeps.json ]; then
		grey "$(indent $align)no dev dependencies"
	else
		#install_devDependencies ${pkgver%%@[\^0-9]*}/devDeps.json;
		install_dependencies ${pkgver%%@[\^0-9]*}/devDeps.json;
	fi
	(( align-=3 ))

	# return to where we started
	popd &> ${output};

}


#---------------------------------
#  
#
#---------------------------------
function install_dependencies()
{

	# $1 : the fully qualified path/file name with json dependencies
	local jsonfile=$1

	local key
	local value

	# install local to the package
	cd `dirname ${jsonfile}`
	grey "$(indent $align)pkg path = ${PWD}"

	# install dependencies; package local installation
	while IFS== read -r key value;
	do 

		# check for empty deps
		if [ -z $key ]; then
			echo "key => x${key}x"
			break
		fi

		# version fixup
		value=${value//[\^\~]/}

		# so, just install them here.
		blue -n "$(indent $align)+ "; white -n "installing $key@$value"

		# only add this dependency if not already in our list
		if [[ ! -z "${modules[${key}${value:+,$value}]:-}" ]]; then
			red " x"
		else
			green " *"
			modules[${key}${value:+,$value}]="verified"
			modpaths[${key}${value:+,$value}]=$PWD/node_modules
		fi

		# alread installed ? 
		check_dep $key@$value 'local'
		if [ $? -ne 0 ]; then 
			# this probably should be before the printing above, but ....
			npm install --global-style $key@$value &> ${output}

			# noop for now
			if [[ devFlag == 'true' ]]; then
				# install all of the devDependencies at the 'global' scope
				get_devDependencies $PWD/node_modules $key@$value
				if [ $? -ne 0 ]; then
					red "install_dependencies :: get_devDependencies :: failed for $key"; 
					exit
				fi
			fi

			# recursively add this dependencies, dependencies.
			get_dependencies $PWD/node_modules $key $value
		else
			grey "$(indent $align)    already installed."
		fi

	done < <(jq -r 'to_entries | .[] | .key + "=" + .value ' $(basename $jsonfile) )

}


#---------------------------------
#  
#
#---------------------------------
function get_dependencies() {

   # $1 : the full package path; one up from the module
	# $2 : the package name
	# $3 : the package *version* (can be empty)
	
	local nodedir=$1
	local package=$2
	local version=$3

	# record where we started
	((align+=3))
	pushd $PWD &> ${output}

	# go to 'node_modules' directory
	cd $nodedir

	magenta "$(indent $align)$package${version:+@$version} :: dependencies"

	# now get a list of all the dependencies from module's package.json 
	npm view --json $package${version:+@$version} dependencies > $package/deps.json 2> ${output}
	if [ $? -ne 0 ]; then
		red "get_dependencies :: error getting dependencies for $package${version:+@$version}" ;
		exit;
	fi

	((align+=3))
	# check if no dependencies
	if [ ! -s $package/deps.json ]; then
		white "$(indent $align)no dependencies"
	else
		# do the real work
		install_dependencies ${PWD}/$package/deps.json
	fi
	((align-=3))
	((align-=3)) # for some reason, this causes $? = 1

	# go back to where we started
	popd &> ${output}
}



#---------------------------------
#  NOTE:  also need to get 
#         "peerDependencies"
#---------------------------------
function install_package() {

	# $1 : the 'quarantine' directory (one up from package)
	# $2 : the package name (directory name of package)
	# $3 : the package *version* (can be empty)

	local nodedir=$1
	local package=$2
	local version=$3

	# record where we started
	pushd $PWD &> ${output}

	# go to 'quarantine' directory
	cd $nodedir

	# install the module without caching it in npm-proxy
	grey "$(indent $align)Installing package locally :: $package${version:+@$version}"
	npm install -g "$package${version:+@$version}" &> ${output} 

	# mark this module as installed
	modules[${package}${version:+,$version}]="verified"
	modpaths[${package}${version:+,$version}]=$PWD/lib/node_modules


	# install all of the devDependencies at the 'global' scope
	if [[ devFlag == 'true' ]]; then
		get_devDependencies $1/lib/node_modules $package${version:+@$version} 
		if [ $? -ne 0 ]; then
			red "install_package :: get_devDependencies :: failed for $package"
			exit 1
		fi
	fi

	# install all dependencies in package local 'node_modules'
	get_dependencies $nodedir/lib/node_modules $package

	# return to original location
	popd &> ${output}
}


#---------------------------------

#---------------------------------
function publish_module() {

	# $1 : the directory (one up from package)
	# $2 : the package name (directory name of package)
	# $3 : the package *version* (can be empty)

	# record where we started
	pushd $PWD &> ${output}


	# noop this block of code
	if [ 1 -eq 0 ]; then
		if [[ "${2}" == "${NPMPACKAGE}" ]]; then
			cd $1/lib/node_modules/${NPMPACKAGE}
		else
			# assume we are installing a dependency
			cd $1/lib/node_modules/${NPMPACKAGE}/node_modules/$2
		fi
	fi

	cd $1/$2

	yellow -n "publishing ${2}"
	npm publish --access public --ignore-scripts &> ${output}
	if [ $? -eq 0 ]; then
		success	
		modules[${2}${3:+,$3}]="published"
	else
		failure
		modules[${2}${3:+,$3}]="failed"
	fi

	# return to original location
	popd &> ${output}
}


#---------------------------------

#---------------------------------
function does_exist() {

	# just create a module report
	magenta "check publication of $1@$2 on $3:" 
	white   "--------------------------------------------"
	npm view "$1@$2" --registry=$3
	cyan -n "$(indent $((align+3))) $1@$2 : "
	if [ $? -eq 0 ]; then
		green "published."
	else
		red "unpublished"
	fi
	white   "--------------------------------------------"
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


#---------------------------------

#---------------------------------
function report() {

	# just create a module report
	magenta "Module and Dependency Report:"
	white "-------------------------------------------------------------------------------------------------"
	for key in ${!modules[@]}
	do
		blue "$key $(indent 40)-> ${modules[${key}]} $(indent 55) :: ${modpaths[${key}]}"
	done
	white "-------------------------------------------------------------------------------------------------"
}

# ======================== [ script begins here ] ===========================

NPMPACKAGE=""
NPMVERSION=""
output=/dev/null
devFlag='false'
align=0
quarantine="/data/npm-quarantine"

declare -A modules   # an array with modules[<package name>,<package version>] = <status>
declare -A devdeps   # an array with devdeps[<package name>,<package version>] = <path>
declare -A modpaths  # an array with modpaths[<package name>,<package version] = <path>

# need to make sure 'grep' and 'ls' aren't aliased
unalias grep &> ${output}
unalias ls &> ${output}

parse_args $@


oldpath=$PATH
trap 'res=$?; config_npmrc 'safe'; export PATH=$oldpath; exit $res' INT EXIT

#--------------------------------------
# ensure local installation
#    - no escalated privileges
#--------------------------------------
cd ${HOME}
if [ -d $quarantine ]; then
	echo "$quarantine already exists"
	while true; do
		cmode $fg_cyan
		read -p "    Do you wish to erase it before starting? [Y/N] :: " yn

		# verify response
		case $yn in
			[Y]* ) rm -rf $quarantine; break;;
			[N]* ) break ;;
            * ) grey "      Please answer Yes or No";;
		esac
	done
	cmode $reset
fi

#--------------------------------------
# ensure proper NPM configuration
#--------------------------------------
config_npmrc 'safe' 
mkdir -p $quarantine                # setup sandbox to work in
npm config set prefix $quarantine
export PATH=$quarantine/bin:$PATH


#--------------------------------------
# ensure NPM tool dependencies met
#--------------------------------------
# !! ensure that 'config_npmrc safe' has been run, first
npm install -g detect-installed
if [ $? -neq 0 ]; then
	red "this script requires the 'detect-installed' NPM module."
	white "$(indent 5)Run 'npm-importer.sh detect-installed' to import it"
	white "$(indent 5)  and then rerun this script.                      "
fi

#--------------------------------------
#  Begin the installation process
#--------------------------------------

#
# Caution : npm set to access the internet registry
# 
config_npmrc 'open'

# download the package with dependencies.
install_package ${quarantine} ${NPMPACKAGE} ${NPMVERSION} 

# advertising
white -n "installation of ${NPMPACKAGE}@${NPMVERSION}"; success;
report

#--------------------------------------
# Virus Scanning
#--------------------------------------
 
# scan the downloaded software
LOGFILE="./${NPMPACKAGE/\//_}_clam.log"

cd ${quarantine} 
green -n "Scanning for viruses ::"
clamscan -ri ${quarantine} &> "./${LOGFILE}"

# get the value of "Infected lines" 
MALWARE=$(tail "./${LOGFILE}" | grep Infected |cut -d" " -f3) 

# if the value is not equal to zero, abort!!
if [[ "$MALWARE" -ne "0" ]];then 
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

config_npmrc 'safe'

# this requires your Crowd credentials
magenta "Please verify your credentials ::"
npm adduser --registry=http://nexus.vsi-corp.com:8888/repository/npm-mpf/  

export PATH=$quarantine/bin:$PATH

for key in ${!modules[@]}
do
	# get module and version from key
	module=${key%%,*}
	version=${key##*,}
	if [[ $version == $module ]]; then
		version=""
	fi
	grey "publishing module :: $module , version :: $version."

	# skip modules that have already been published
	npm view ${module}@${version} &> /dev/null
	if [ $? -eq 0 ]; then
		grey "${module}@${version} :: already published"
		modules[${key}]="published"
	fi

	publish_module ${modpaths[${module}${version:+,$version}]} ${module} ${version}
	modules[${key}]="published"
done

# summary report
report
#yellow "debug abort" ; exit;
