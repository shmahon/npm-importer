#!/bin/bash

# import our utilities
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi
   . "$DIR/term_color.sh"


#---------------------------------
#
#
#---------------------------------
function read_recursive_dependencies() {

   local package=$1
   local version=$2

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
         npmobjpath="${npmobjpath}.\"$dep\""
         read_recursive_dependencies ${dep} ${ver}
      fi
   done< <( cat $mapfile | jq -r "$npmobjpath | to_entries[] | { package: .key, version: .value.version, hasdeps: .value.dependencies | length } | "'"\(.package) \(.version) \(.hasdeps)"'"") 
   yellow "early abort for testing...."; exit 0
}

#
# Main
#
npmobjpath=""
mapfile=$1
package=$(cat $mapfile | jq -r '.name')
version=$(cat $mapfile | jq -r '.version')
read_recursive_dependencies $package $version
