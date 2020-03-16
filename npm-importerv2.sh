#!/bin/bash
# vim: set ts=3 sw=3 autoindent smartindent:

# These notes consider how to download a "release" of TOA
# for purposes of uploading it to codenest.
#
# DEPENDENCIES:  you will need you yum install 'jq'
#
#  Approach as of 03/10/2020
#
#     1.  Install the base package unless its a directory in 
#         which case, skip right to installing its dependencies.
#     2.  If its a package (not a directory), then assume that an
#         install also brings down its immediated dependencies.
#     3.  Scan everything.
#     4.  Make a list of all the dependencies and publish them.
#

# import our utilities
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
   . "$DIR/term_color.sh"


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
   grey  "  --align <integer>                                         "
   grey  "       changes the space alignment of output for use when   "
   grey  "       calling this script from another script.             "
   grey  "                                                            "
   grey  "  --dev  *** This isn't functional right now ***            "
   grey  "       also install the development dependencies.           "
   grey  "                                                            "
   grey  "  --rebuild-quarantine [true|false]                         "
   grey  "       just a flag to force the removal and rebuild of      "
   grey  "       the quarantine directory.                            "
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
   TEMP=`getopt -o hd --long debug,dev,nocred,rebuild-quarantine:,align: -n $name -- "$@"`
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

			# assume the user has already provided NPM registry credentials
			--nocred ) nocredFlag='true' ; shift ;;

			# option to automatically control the rebuilding of the quarantine directory
			--rebuild-quarantine )
			   case "$2" in
					true ) rebuildFlag='true'  ; shift 2 ;;
				  false ) rebuildFlag='false' ; shift 2 ;;
				      * ) red "--rebuild-quarantine requires a 'true' or 'false' paramater" ; usage ;;
				esac ;;
				
			# an option that controls the column alignment of output
			--align )
				case "$2" in
					"" ) red "--align requires an integer parameter" ; usage ;;
					*  ) align=$2; shift 2 ;;
				esac ;;

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
		red $(indent $align)"no npm package specified for import!"
		usage
	else
      NPMPACKAGE=${1%%@[\^0-9]*}
      NPMVERSION=${1##*@}
      if [[ $NPMVERSION == $NPMPACKAGE ]]; then
         NPMVERSION=""
			green  "\n$(indent $align)Importing $NPMPACKAGE package..."
      else
			green  "\n$(indent $align)Importing $NPMPACKAGE version $NPMVERSION package..."
      fi
   fi
	yellow -n "$(indent $align)"
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
	grey "$(indent $align)check_dep :: running in $PWD :: checking $pkgver" &> ${output}
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
		value=${value//[\^\~\ ]/}

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

	done < <(jq -r '.dependencies | to_entries | .[] | .key + "=" + .value ' $jsonfile);
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
	grey "$(indent $align)pkg path = ${PWD}" &> ${output}

	# install dependencies; package local installation
	while IFS== read -r key value;
	do 

		# check for empty deps
		if [ -z $key ]; then
			echo "key => x${key}x"
			break
		fi

		# version fixup
		value=${value//[\^\~\ ]/}

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
function read_dependencies() {

	#local pkgpath=$1
	#local package=$2
	#local version=$3

	local package=$1
	local version=$2
	local pkgpath=${modpaths[${package}${version:+,$version}]}

	# debug
	grey  "$(indent $align)pkgpath = ${pkgpath}" &> ${output}

	((align+=3))

	# set location for dependency file
	local pkgjsonfile=$PWD/package.json

	# debug information
	magenta "$(indent $align)$package${version:+@$version} :: dependencies" &> ${output}
	grey "$(indent $align) in $PWD." &> ${output}

	# add dependencies to our installation list ("report") 
	local key=""
	local value=""
	while IFS== read -r key value;
	do 

		# check for empty deps
		if [ -z $key ]; then
			echo "key => x${key}x"
			break
		fi

		# version fixup
		value=${value//[\^\~\ ]/}
		
		# so, just install them here.
		blue -n "$(indent $align)+ "; white -n "adding $key@$value"

		# only add this dependency if not already in our list
		if [[ ! -z "${modules[${key}${value:+,$value}]:-}" ]]; then
			red " x"

			# no need to check for child dependencies
			continue
		else
			green " *"
			modules[${key}${value:+,$value}]="installed"
		fi

		# recursively add this dependencies, dependencies.
		modpaths[${key}${value:+,$value}]=$root_dir/node_modules/$key

		# debug reporting
		grey -n "$(indent $((align+2)))"
		grey "added modpaths[${key}${value:+,$value}] :: ${modpaths[${key}${value:+,$value}]}" &> ${output}

		cyan -n "$(indent $((align+2)))"
		cyan "checking ${modpaths[${key}${value:+,$value}]} for deps..." &> ${output}

		pushd $PWD &> ${output}
		cd ${modpaths[${key}${value:+,$value}]}

		# get all this dependencies dependencies
		read_dependencies $key $value	

		popd &> ${output}

	done < <(jq -r '.dependencies | to_entries | .[] | .key + "=" + .value ' $pkgjsonfile); 

	((align-=3))
}


#---------------------------------
#  
#
#---------------------------------
function get_dependencies() {

   # $1 : the full package path
	# $2 : the package name
	# $3 : the package *version* (can be empty)
	
	local moduledir=$1
	local package=$2
	local version=$3

	# record where we started
	pushd $PWD &> ${output}

	cd $moduledir

	grey "get_dependencies :: $PWD" &> ${output}

	# get a recursive list of all dependencies for this package
	read_dependencies $package $version

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

	# install the module without caching it in npm-proxy
	grey "$(indent $align)Installing package locally :: $package${version:+@$version}" &> ${output}
	npm install -g "$package${version:+@$version}" &> ${output} 
	
	# record where we started
	pushd $PWD &> ${output}

	# go to 'quarantine' directory
	cd $nodedir

	# mark this module as installed
	modules[${package}${version:+,$version}]="installed"
	modpaths[${package}${version:+,$version}]=$PWD


	# install all of the devDependencies at the 'global' scope
	if [[ devFlag == 'true' ]]; then
		get_devDependencies $1/lib/node_modules $package${version:+@$version} 
		if [ $? -ne 0 ]; then
			red "install_package :: get_devDependencies :: failed for $package"
			exit 1
		fi
	fi

	# install all dependencies in package local 'node_modules'
	get_dependencies $nodedir $package $version

	# return to original location
	popd &> ${output}
}


#---------------------------------

#---------------------------------
function publish_module() {

	# $1 : the package name (directory name of package)
	# $2 : the package *version* (can be empty)

	# get the 'actual' installed version, can be different than expected
	yellow -n "$(indent $align)publishing module :: ${1} , version :: ${2}"
	white -n " [" ; green -n "$actualver"; white -n "]"

	# skip modules that have already been published
	npm publish --access public --ignore-scripts &> ${output}
	if [ $? -eq 0 ]; then
		success 80
		modules[${1}${2:+,$2}]=$(echo "${modules[${1}${2:+,$2}]},published")
	else
		failure 80
		modules[${1}${2:+,$2}]=$(echo "${modules[${1}${2:+,$2}]},not published")
	fi
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
			white -n "$(indent $((align+5)))npmrc config :: "; green "safe";
			npm config set proxy "http://nexus.vsi-corp.com:8888";
			npm config set https-proxy "http://nexus.vsi-corp.com:8888";
			npm config set registry "http://nexus.vsi-corp.com:8888/repository/npm-mpf/";
			npm config set strict-ssl false; ;;
		# 'proxy' : point to http://nexus.vsi-corp.com:8888/repository/npm-proxy/
		#           used for caching local copies for evaluation
		proxy )
			white -n "$(indent $((align+5)))npmrc config :: "; yellow "proxy";
			npm config set proxy "http://nexus.vsi-corp.com:8888";
			npm config set https-proxy "http://nexus.vsi-corp.com:8888";
			npm config set registry "http://nexus.vsi-corp.com:8888/repository/npm-proxy/";
			npm config set strict-ssl false; ;;
		# 'open'  : point to https://registry.npmjs.org/
		#           used for getting direct access to internet NPM registry for
		#           virus scanning
		open )
			white -n "$(indent $((align+5)))npmrc config :: "; red "open";
			npm config delete proxy;
			npm config delete https-proxy;
			npm config delete registry;
			npm config delete strict-ssl; ;;

		* ) red "$(indent $align)config_npmrc :: invalid paramater '$1' provided.  Aborting."; exit ;;
	esac
}


#---------------------------------

#---------------------------------
function report() {

	# $1 - the module that is being installed
	# $2 - flag for printing the paths
	local flag=${2:-'false'}
	local key;

	# just create a module report
	echo -en "\n"
	magenta "$(indent $align)Module and Dependency Report: $1"
	white -n "$(indent $align)"
	white "-------------------------------------------------------------------------------------------------"
	for key in ${!modules[@]}
	do
		offset=${offset:-$(( 40+${#modules[${key}]}+5 ))}
		offset=$(( ${#modules[${key}]} > $((offset-40-5)) ?  $((40+${#modules[${key}]}+5)) : offset ))
		blue -n "$(indent $align)$key $(indent 40)-> ${modules[${key}]} $(indent $offset)"
		case "$flag" in
			 true ) grey " :: ${modpaths[${key}]}"; ;;
			false ) grey ""; ;; # just add the carriage return
			    * ) grey ""; ;; # assume 'false'
		esac
	done
	white -n "$(indent $align)"
	white "-------------------------------------------------------------------------------------------------"
	echo -en "\n"
}


# ======================== [ script begins here ] ===========================

NPMPACKAGE=""
NPMVERSION=""
output=/dev/null
devFlag='false'
nocredFlag='false'
rebuildFlag=''
align=0
quarantine="/data/npm-quarantine"
root_dir="/data/npm-quarantine/lib/node_modules"


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
if [ -d $quarantine ]; then
	if [ $rebuildFlag == "" ] ; then
		echo -e "$(indent $align)$quarantine already exists"
		while true; do
			cmode $fg_cyan
			read -p "    Do you wish to erase it before starting? [Y/N] :: " yn

			# verify response
			case $yn in
				[Y]* ) rm -rf $quarantine; break;;
				[N]* ) break ;;
				   * ) grey "$(indent $align)      Please answer Yes or No";;
			esac
		done
		cmode $reset
	elif [ $rebuildFlag == "true" ]; then
		rm -rf $quarantine;
	else
		echo -e "$(indent $align)using existing $quarantine directory"
	fi
fi

#--------------------------------------
# ensure proper NPM configuration
#--------------------------------------
mkdir -p $quarantine                # setup sandbox to work in
npm config set prefix $quarantine
export PATH=$quarantine/bin:$PATH


#--------------------------------------
#  Begin the installation process
#--------------------------------------

config_npmrc 'open' # Caution : npm set to access the internet registry

# update the root package dir
root_dir="$root_dir/$NPMPACKAGE"

# download the package with dependencies.
echo -en "\n"
install_package ${root_dir} ${NPMPACKAGE} ${NPMVERSION} 

# advertising
((align+=3))
report ${NPMPACKAGE}@${NPMVERSION} 'true' &> ${output}
white -n "\n$(indent $align)installation of ${NPMPACKAGE}@${NPMVERSION}"; success;


# this requires your Crowd credentials
if [ $nocredFlag == "false" ]; then
	magenta "Please verify your credentials for http://nexus.vsi-corp.com:8888/repository/npm-mpf/ ::"
	npm adduser --registry=http://nexus.vsi-corp.com:8888/repository/npm-mpf/  
fi

export PATH=$quarantine/bin:$PATH

#--------------------------------------
# Virus Scanning and Publishing
#--------------------------------------
green "\n$(indent $align)Publishing $NPMPACKAGE and its dependencies to 'npm-mpf' nexus repo"
blue -n "$(indent $align)"
blue "-------------------------------------------------------------------------------------------"
config_npmrc 'safe'
for key in ${!modules[@]}
do
	# get module and version from key
	module=${key%%,*}
	version=${key##*,}
	if [[ $version == $module ]]; then
		version=""
	fi

	# work out of the locally installed module dir
	pushd $PWD &> ${output}
	moduledir="${modpaths[${module}${version:+,$version}]}"
	
	cd $moduledir

	# advertise
	yellow -n "\n$(indent $align) - " 
	white -n "${module}${version:+@$version}"

	# get the 'actual' installed version, can be different than expected
	actualver=$(cat package.json | jq -r ".version")
	if [[ $actualver != $version ]]; then 
		white -n " [" ; green -n "$actualver"; white -n "]"; 
	fi
	white "" # just finish the line

	# debug formatting
	(( align+=2 ))

	# early skip for modules that are already imported
	if [[ $(npm view --json ${module}${actualver:+@$actualver} version) != "" ]]; then #&> ${output}
		grey " $(indent $align)already published :: ${module}@${actualver}."
		modules[${key}]=$(echo "${modules[${module}${version:+,$version}]},published")
		(( align-=2 ))
		continue
	fi
	
	# debug formatting
	((align+=2))
   
	# scan the downloaded software
	blue -n "$(indent $align)virus scanning :: ${module}@${actualver}."
	LOGFILE="$module-$(date +%T-%m%d%Y).clam"
	clamscan -ri "$moduledir" > "./$LOGFILE"

	# get the value of "Infected lines" 
	MALWARE=$(tail ${LOGFILE} | grep Infected |cut -d" " -f3) 

	# if the value is not equal to zero, abort!!
	if [[ "$MALWARE" -ne "0" ]];then 
		failure 80
		red "$(indent $align)Malware has been detected while scanning ${module}!"
		red "$(indent $((align+3)))Aborting the import."
		yellow "$(indent $((align+5)))$module will be kept in $moduledir"
		yellow "$(indent $((align+5)))Notify an SA immediately to report malware detection!"

		modules[${key}]="virus detected"
	else
		success 80
		modules[${key}]="virus scanned"
		publish_module ${module} ${version}
	fi 

	popd &> ${output}
	(( align-=2 ))
done

# summary report
report
