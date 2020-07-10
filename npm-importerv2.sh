#!/bin/bash 
# vim: set ts=3 sw=3 et autoindent smartindent:

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
   grey  "  -t | --testing                                            "
   grey  "       don't try to virus scan or upload the modules.  This "
   grey  "       flag is used for testing the script to isolate       "
   grey  "       errors.                                              "
   grey  "                                                            "
   grey  "  -c | --cwd                                                "
   grey  "       allow all 'popd', 'pushd' and other dir commands     "
   grey  "       to print to stdout instead of default /dev/null      "
   grey  "                                                            "
   grey  "  --align <integer>                                         "
   grey  "       changes the space alignment of output for use when   "
   grey  "       calling this script from another script.             "
   grey  "                                                            "
   grey  "  --dev                                                     "
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
   TEMP=`getopt -o hdtc --long debug,testing,cwd,dev,nocred,rebuild-quarantine:,align: -n $name -- "$@"`
   # catch any errors from getopt
   if [ $? -ne 0 ]; then
      usage
   fi

   eval set -- "$TEMP"

   while [ $# -gt 0 ]; do

      case "$1" in

         # process an option without a required argument
         -d | --debug ) output=/dev/stdout ; shift ;;

         # process an option without a required argument
         -t | --testing ) testFlag='true' ; shift ;;

         # process an option without a required argument
         -c | --cwd ) cwdoutput=/dev/stdout ; shift ;;

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
      #NPMPACKAGE=$(echo $1 | sed -rn 's/(.*)@[\^>~]?([0-9]\.?){1,3}/\1/p') # ${1%%@[\^>~]*[0-9]*}
      #NPMPACKAGE=$(echo $1 | sed -rn 's/(.*)@[\^>~]?[0-9]+.*$/\1/p') # ${1%%@[\^>~]*[0-9]*}
      NPMPACKAGE=$(echo $1 | sed -rn 's/(^\@?[^\@]*).*$/\1/p') # ${1%%@[\^>~]*[0-9]*}
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
function check_version() {

   # some version strings have spaces; strip of the quotes that allow
   # a space delimited version string to be passed in as a single parameter
   local package=${1//\"/}  
   local scope=${2:-'local'}
   local res="NotFound"

   # output formatting
   ((align+=3))

   # query from selected scope
   case "$scope" in

      #
      # NOTE!! Its important to be **in** the installed package directory
      #        assumes that you are 'local' in path to the package.
      #        Otherwise, the '--depth=0' will prevent you from finding an
      #        answer.
      local )
         res=$(npm ls -s $package --depth=0 --json | \
            jq ".dependencies.\"${package%%@*}\".version") 2> ${output};
         #npm ls -ls mkdirp --json | jq '.dependencies | .[] | select( .dependencies.$package[0][0].rawSpec=="^0.5.0" ) | .'
         if [ -z $res ] || [[ $res == "null" ]]; then
            # retry at global scope
            res=$(check_version "$package" 'global');
         fi;;

      global )
         pushd $PWD &> /dev/null;
         cd $rootdir;
         res=$(npm ls -s $package --json | \
            jq -r "[.. | .dependencies? | objects | to_entries[] | select( .key == \"${package%%@*}\")] | .[0].value.version") 2> ${output}; 
         popd &> /dev/null ;;

      * )
         # just default to 'local' scope
         magenta "$(indent $align)check_version( $scope ) : invalid 'scope'" \
                 " provided; defaulting to 'global'."; > $stderr 
         res=$(check_version "$package" 'global') ;;
   esac;

   if [ -z $res ] || [[ $res == "null" ]]; then
      res=NotFound
   fi

   # debug                                                                                                         
   #grey "$(indent $align)${FUNCNAME[0]} :: result = $res" > $stderr

   ((align-=3))

   # just return the result
   echo ${res//\"/} ; return 0;
}




#-----------------------------------
#
#
#-----------------------------------
function check_path() {

   local mod=$1
   local ver=$2
   local res="NotFound"

   # is it installed in the dependency's path? 
   if [ -d $PWD/node_modules/$mod ]; then
      res="$PWD/node_modules/$mod"
   elif [ -d $rootdir/node_modules/$mod ]; then
      res="$rootdir/node_modules/$mod"
      # TODO: should really check the version to make sure it matches
   else
      # TODO: it actually could be installed as a dependency of another module
      res="NotFound"
   fi

   # just return the result
   echo ${res}; return 0;
}




#---------------------------------
#
#
#---------------------------------
function read_dev_dependencies() {

   local package=$1
   local version=$2
   local modpath=NotFound

   # set location for dependency file
   local pkgjsonfile=$PWD/package.json

   ((align+=3))

   # debug
   grey  "$(indent $align)read_dev_dependencies :: pkgpath = ${PWD}" &> ${output}


   # debug information
   green "$(indent $align)$package${version:+@$version} :: dev_dependencies" &> ${output}
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

      # debug
      blue -n "$(indent $align)+ adding "; white -n "$key@$value"

      # only add this dependency if not already in our list
      if [[ ! -z "${modules[${key}${value:+,$value}]:-}" ]]; then
         red " x"

         # no need to check for child dependencies
         continue
      else
         green " *"

         # now mark it as installed
         modules[${key}${value:+,$value}]="dependency,installed"
      fi

      # find where this module was installed
      modpath=$(check_path $key "$value")

      # add the desired install path for this package.
      # original : modpaths[${key}${value:+,$value}]=$PWD/node_modules/$key
      modpaths[${key}${value:+,$value}]=$modpath

      # debug reporting
      grey -n "$(indent $((align+2)))" &> ${output}
      grey "added modpaths[${key}${value:+,$value}] " \
           ":: ${modpaths[${key}${value:+,$value}]}" &> ${output}

      cyan -n "$(indent $((align+2)))" &> ${output}
      cyan "checking $key@$value for dev deps..." &> ${output}

      # get any dependencies added by this development dependency
      read_dependencies $key $value

   done < <(jq -r '.devDependencies | to_entries | .[] | .key + "=" + .value ' $pkgjsonfile );

   ((align-=3))  # this causes a $? == 1 for some reason

   return 0
}



#---------------------------------
#
#
#---------------------------------
function read_recursive_dependencies() {

   local package=$1
   local version=$2
   local pkgpath=${modpaths[${package}${version:+,$version}]}
   local hasdeps=0
   local modpath=NotFound
   local npmobjpath_history=$npmobjpath

   npmobjpath="${npmobjpath}.dependencies"

   echo "npmobjpath -> $npmobjpath"

   ((align+=2))
   local dep=""
   local ver=""
   local hasdeps=""
   local counter=1
   while read -r dep ver hasdeps; do
      echo "dep :: $dep"
      echo "ver :: $ver"
      echo "has :: $hasdeps"
      blue -n "$(indent $align) dependency[$counter] : "
      white "$dep"
      ((counter+=1))

      # conver to int
      #hasdeps=$(($hasdeps))
      # reporting
      if [ $((hasdeps)) -gt 0 ]; then 
         # yes!
         npmobjpath="${npmobjpath}.$dep"
         read_recursive_dependencies ${dep} ${ver} 
      fi
   done< <( cat $mapfile | jq --arg objpath ${npmobjpath##.} -r '.[$objpath] | to_entries[] | { package: .key, version: .value.version, hasdeps: .value.dependencies | length } | "\(.package) \(.version) \(.hasdeps)"')

   yellow "early abort for testing...."; exit 0

   ((align+=2))

   # initialize 'map' path
   npmobjpath="${npmobjpath}.dependencies.\"$package\""
   #grey -n "$(indent $align)npmobjpath => " &> ${output}
   #green "$npmobjpath" &> ${output} 

   # debug
   grey "$(indent $align)changing from $PWD -> $pkgpath." &> ${cwdoutput}

   # enter this packages directory
   pushd $PWD &> ${cwdoutput}
   cd $pkgpath

   # set location for dependency file
   local pkgjsonfile=$PWD/package.json

   # debug information
   grey "$(indent $align)path => $PWD" &> ${output}


   #-------------------------------------
   #  map.json method for this routine
   #-------------------------------------

   # use $rootdir/map.json to find dependency information
   hasdeps=$(cat $mapfile | jq "$npmobjpath.dependencies | length")

   # reporting
   if [ $hasdeps -lt 1 ]; then 
      white "$(indent $align)no deps." &> ${output}
   else
      white "$(indent $align)$hasdeps deps." &> ${output}
   fi

   # get a list of dependencies
   local deps=$( cat $mapfile | jq "$npmobjpath.dependencies | keys | .[]")

   # because we are completely tracking scope, we don't *need* to get
   # the version anymore, but we also *aren't* getting the version with
   # this method.  Some more exotic method would be needed in the 'deps'
   # determination above.

   # simple loop
   ((align+=3))
   for dep in $deps; do

      # bail on empty list
      if [ -z $dep ]; then continue; fi;

      # for each dependenc:
      #    - verify that its installed
      #    - get version
      #    - get path
      #    - iterate over dependencies

      blue -n "$(indent $align)"${dep//\"/}

      # build this dependencies object path
      depobjpath="$npmobjpath.dependencies.$dep"

      # make sure its an actual dependency
      valid=$(cat $mapfile | jq -r "$depobjpath._args[0][0] | length")
      if [ -z $valid ] || [ $valid -eq 0 ]; then
         grey -n " -"; echo -e $fg_yellow" skip"$reset
         #echo -e $fg_yellow"$package has empty reference to $dep"$reset
         continue
      fi

      # get requested version
      map_version_req=$(cat $mapfile | jq -r "$depobjpath._args[0][0].rawSpec")
      #grey "$(indent $align)map_version_req : $map_version_req" &> ${output}

      # get actual version
      map_version_actual=$(cat $mapfile | jq -r "$depobjpath.version")
      #grey "$(indent $align)map_version_actual : $map_version_actual" &> ${output}

      # debug
      grey -n " ["; yellow -n " $map_version_req"; grey -n " / ";

      # just report on what version was actually installed 
      if [[ ${map_version_req//[\^\~\ \*]/} == $map_version_actual ]]; then
         green -n "$map_version_actual"
      else
         red -n "$map_version_actual"
      fi
      grey " ]"

      # get path
      map_path=$(cat $mapfile | jq -r "$depobjpath.path")
      grey "$(indent $align) map_path : $map_path" &> ${output}

      # create record
               #modules[${key}${value:+,$value}]="NotInstalled;Optional"
      modules[${dep//\"/}${map_version_actual:+,$map_version_actual}]="installed"
      modpaths[${dep//\"/}${map_version_actual:+,$map_version_actual}]=${map_path}

      read_dependencies ${dep//\"/} ${map_version_actual}
   done
   ((align-=3))


   # reset to original npmobjpath
   npmobjpath=${npmobjpath_history}
   grey -n "npmobjpath => " &> ${output}
   green "$npmobjpath" &> ${output}
   ((align-=2))

   # return to starting point
   popd &> ${cwdoutput}
}

#---------------------------------
#
#
#---------------------------------
function read_dependencies() {

   local package=$1
   local version=$2
   local pkgpath=${modpaths[${package}${version:+,$version}]}
   local hasdeps=0
   local modpath=NotFound
   local npmobjpath_history=$npmobjpath


   ((align+=2))

   # initialize 'map' path
   npmobjpath="${npmobjpath}.dependencies.\"$package\""
   #grey -n "$(indent $align)npmobjpath => " &> ${output}
   #green "$npmobjpath" &> ${output} 

   # debug
   grey "$(indent $align)changing from $PWD -> $pkgpath." &> ${cwdoutput}

   # enter this packages directory
   pushd $PWD &> ${cwdoutput}
   cd $pkgpath

   # set location for dependency file
   local pkgjsonfile=$PWD/package.json

   # debug information
   grey "$(indent $align)path => $PWD" &> ${output}


   #-------------------------------------
   #  map.json method for this routine
   #-------------------------------------

   # use $rootdir/map.json to find dependency information
   hasdeps=$(cat $mapfile | jq "$npmobjpath.dependencies | length")

   # reporting
   if [ $hasdeps -lt 1 ]; then 
      white "$(indent $align)no deps." &> ${output}
   else
      white "$(indent $align)$hasdeps deps." &> ${output}
   fi

   # get a list of dependencies
   local deps=$( cat $mapfile | jq "$npmobjpath.dependencies | keys | .[]")

   # because we are completely tracking scope, we don't *need* to get
   # the version anymore, but we also *aren't* getting the version with
   # this method.  Some more exotic method would be needed in the 'deps'
   # determination above.

   # simple loop
   ((align+=3))
   for dep in $deps; do

      # bail on empty list
      if [ -z $dep ]; then continue; fi;

      # for each dependenc:
      #    - verify that its installed
      #    - get version
      #    - get path
      #    - iterate over dependencies

      blue -n "$(indent $align)"${dep//\"/}

      # build this dependencies object path
      depobjpath="$npmobjpath.dependencies.$dep"

      # make sure its an actual dependency
      valid=$(cat $mapfile | jq -r "$depobjpath._args[0][0] | length")
      if [ -z $valid ] || [ $valid -eq 0 ]; then
         grey -n " -"; echo -e $fg_yellow" skip"$reset
         #echo -e $fg_yellow"$package has empty reference to $dep"$reset
         continue
      fi

      # get requested version
      map_version_req=$(cat $mapfile | jq -r "$depobjpath._args[0][0].rawSpec")
      #grey "$(indent $align)map_version_req : $map_version_req" &> ${output}

      # get actual version
      map_version_actual=$(cat $mapfile | jq -r "$depobjpath.version")
      #grey "$(indent $align)map_version_actual : $map_version_actual" &> ${output}

      # debug
      grey -n " ["; yellow -n " $map_version_req"; grey -n " / ";

      # just report on what version was actually installed 
      if [[ ${map_version_req//[\^\~\ \*]/} == $map_version_actual ]]; then
         green -n "$map_version_actual"
      else
         red -n "$map_version_actual"
      fi
      grey " ]"

      # get path
      map_path=$(cat $mapfile | jq -r "$depobjpath.path")
      grey "$(indent $align) map_path : $map_path" &> ${output}

      # create record
               #modules[${key}${value:+,$value}]="NotInstalled;Optional"
      modules[${dep//\"/}${map_version_actual:+,$map_version_actual}]="installed"
      modpaths[${dep//\"/}${map_version_actual:+,$map_version_actual}]=${map_path}

      read_dependencies ${dep//\"/} ${map_version_actual}
   done
   ((align-=3))


   # reset to original npmobjpath
   npmobjpath=${npmobjpath_history}
   grey -n "npmobjpath => " &> ${output}
   green "$npmobjpath" &> ${output}
   ((align-=2))

   # return to starting point
   popd &> ${cwdoutput}
}


#---------------------------------
#  NOTE:  also need to get
#         "peerDependencies"
#---------------------------------
function install_package() {

   # $1 : the 'quarantine' directory (one up from package)
   # $2 : the package name (directory name of package)
   # $3 : the package *version* (can be empty)

   local package=$1
   local version=$2
   local ret=0

   # install the module without caching it in npm-proxy
   grey "Installing package locally :: $package${version:+@$version}" &> ${output}
   npm install -g ${ONLYOPTS} "$package${version:+@$version}" &> ${output}
   if [ $? -ne 0 ]; then
      red "Failed to install $package${version:+@$version}. Aborting"
      return $ret
   fi

   # mark this module as installed
   modules[${package}${version:+,$version}]="installed"
   modpaths[${package}${version:+,$version}]=$rootdir

   # record where we started
   pushd $PWD &> ${cwdoutput}

   # move to the top-level package directory; this is very important if
   # installing 'devDependencies'
   cd $rootdir

   #--------------------------------
   # all dependency 'reading' and
   # installing expects to be in
   # in the $rootdir
   #--------------------------------

   # debug announcement
   grey "install_package :: $PWD" &> ${output}


   # install all of the devDependencies at the 'global' scope
   if [[ $devFlag == "true" ]]; then

      # requires that we already be in $quarantine/lib/node_modules/$package
      grey "install_package :: installing $package development dependencies."
      npm install &> ${output}
      if [ $? -ne 0 ]; then
         red "install_package :: devDependencies installation failed for $package"
         exit 1
      fi

      # original: read_dev_dependencies $nodedir $package $version
      #read_dev_dependencies $package $version
   fi

   # generate a map of all the installed dependencies
   npm ls -l --json > "map.json"

   # debug
   green "$package"

   # get a recursive list of all dependencies for this package
   #read_dependencies $package $version
   read_recursive_dependencies $package $version

   # return to original location
   popd &> ${cwdoutput}
}


#---------------------------------

#---------------------------------
function publish_module() {

   # $1 : the package name (directory name of package)
   # $2 : the package *version* (can be empty)

   # get the 'actual' installed version, can be different than expected
   yellow -n "$(indent $align)publishing :: ${1}, version :: ${2}"
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
   local offset
   local key
   local -A founds
   local -A notfounds
   local -A optionals

   # sort the list of modules
   for key in ${!modules[@]}
   do
      # alignment formatting
      offset=${offset:-$(( 40+${#modules[${key}]}+5 ))}
      offset=$(( ${#modules[${key}]} > $((offset-40-5)) ?  $((40+${#modules[${key}]}+5)) : offset ))

      # sort into categories
      case "${modules[${key}]%%;*}" in
              NotFound ) notfounds[$key]=${modules[${key}]}; ;;
          NotInstalled ) optionals[$key]=${modules[${key}]}; ;;
                     * ) founds[$key]=${modules[${key}]}; ;;
      esac
   done

   # just create a module report
   echo -en "\n"
   magenta "$(indent $align)Module and Dependency Report: $1"
   white -n "$(indent $align)"
   white "-------------------------------------------------------------------------------------------------"

   # print all the modules that were found
   for key in ${!founds[@]}
   do
      # build a report of all modules with the path being optional
      blue -n "$(indent $align)$key $(indent 40)-> ${modules[${key}]} $(indent $offset)"
      case "$flag" in
          true ) grey " :: ${modpaths[${key}]}"; ;;
         false ) grey ""; ;; # just add the carriage return
             * ) grey ""; ;; # assume 'false'
      esac
   done

   # now print out the 'optional' report
   for key in ${!optionals[@]}
   do
      # build a report of all modules with the path being optional
      yellow -n "$(indent $align)$key $(indent 40)-> ${optionals[${key}]} $(indent $offset)"
      case "$flag" in
          true ) grey " :: ${modpaths[${key}]}"; ;;
         false ) grey ""; ;; # just add the carriage return
             * ) grey ""; ;; # assume 'false'
      esac
   done

   # now print out the error report
   for key in ${!notfounds[@]}
   do
      # build a report of all modules with the path being optional
      red -n "$(indent $align)$key $(indent 40)-> ${notfounds[${key}]} $(indent $offset)"
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
npmobjpath=""
cwdoutput=/dev/null
output=/dev/null
stderr=/dev/stderr
testFlag="false"
devFlag="false"
nocredFlag='false'
rebuildFlag=""
align=0
quarantine="/data/npm-quarantine"

declare -A modules   # an array with modules[<package name>,<package version>] = <status>
declare -A modpaths  # an array with modpaths[<package name>,<package version] = <path>

# need to make sure 'grep' and 'ls' aren't aliased
unalias grep &> ${output}
unalias ls &> ${output}

#
# argument processing and global var setup
#
parse_args $@

if [[ $devFlag == "false" ]]; then
   ONLYOPTS='--only=production'
fi

# error handling and exit cleanup
oldpath=$PATH
trap 'res=$?; config_npmrc 'safe'; export PATH=$oldpath; exit $res' INT EXIT


#--------------------------------------
# ensure local installation
#    - no escalated privileges
#--------------------------------------
if [ -d $quarantine ]; then
   if [[ $rebuildFlag == "" ]] ; then
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
if [ $? -ne 0 ] || [ ! -d $quarantine ]; then
   failure "Unable to create quarantine directory ($quarantine).  Aborting ..."
   exit 1
fi
npm config set prefix $quarantine
npm config set cache  $quarantine/.npm
export PATH=$quarantine/bin:$PATH


#--------------------------------------
#  Begin the installation process
#--------------------------------------

config_npmrc 'open' # Caution : npm set to access the internet registry

# update the root package dir
rootdir="${quarantine}/lib/node_modules/$NPMPACKAGE"
mapfile="${rootdir}/map.json"

#
#  Assumptions:
#
#    any 'npm ls -l --global <package>' will produce a file with
#    the topmost package listed as a primary dependency.  Each
#    additional dependency will be listed underneath it as an 
#    additional dependency and so on in a simple heirarchical 
#    fashion.
# 
#    So, the first one will be '.dependencies.karma', for instance.
#    The second one will be `

# download the package with dependencies.
echo -en "\n"
install_package ${NPMPACKAGE} ${NPMVERSION}
if [ $? -ne  0 ]; then
   echo "  Try rerunning with the '--debug' flag."
   exit 1
fi

# advertising
((align+=3))
report ${NPMPACKAGE}@${NPMVERSION} 'true' #&> ${output}
white -n "\n$(indent $align)installation of ${NPMPACKAGE}@${NPMVERSION}"; success;

# early abort for testing
if [[ $testFlag == "true" ]]; then
   yellow "Early abort for testing..."
   exit 0
fi

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
   # skip modules that failed
   if [[ ${modules[${key}]} == "NotFound" ]] || \
      [[ ${modules[${key}]%%;*]} == "NotInstalled" ]]; then
      continue
   fi

   # get module and version from key
   module=${key%%,*}
   version=${key##*,}
   if [[ $version == $module ]]; then
      version=""
   fi

   # work out of the locally installed module dir
   pushd $PWD &> ${cwdoutput}
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
   ((align+=2))

   # early skip for modules that are already imported
   if [[ $(npm view --json ${module}${actualver:+@$actualver} version 2> ${output}; ) != "" ]]; then #&> ${output}
      grey " $(indent $align)already published :: ${module}@${actualver}."
      modules[${key}]=$(echo "${modules[${module}${version:+,$version}]},published")
      ((align-=2))
      popd &> ${cwdoutput}
      continue
   fi

   # debug formatting
   ((align+=2))

   # scan the downloaded software
   blue -n "$(indent $align)virus scanning :: ${module}@${actualver}."
   LOGFILE="${module/\/-}-$(date +%T-%m%d%Y).clam"
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
      ((align-=2))
   fi

   ((align-=2))

   popd &> ${cwdoutput}
done

# summary report
report ${NPMPACKAGE}@${NPMVERSION}
