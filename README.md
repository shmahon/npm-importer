## General
This is a simple set of scripts that is just intended to make it easy for
someone to import an NPM package and all of its dependencies in a safe way.

In order to maintain _some_ notion of a clean software environment, our
organization maintains a private NPM registry that contains only assets
that have been virus scanned and then uploaded.  The process for downloading
an internet NPM package with all of its dependencies, scanning them for
viruses and then uploading them to the private registry is a bit onerous.
To make it easier, a few scripts were developed that will be described below.
The 3 primary scripts are:
1. config-npmrc - a convenience script to setup your personal `.npmrc` file correctly
2. npm-importer - a link to the latest version of the `npm-importer` script that takes an npm package and version in the _normal_ format and download it and all its dependencies to a quarantine location, scans them, and then publishes them to our local repo (if no viruses are found).
3. toa-ui-importer - this script is meant to grab a `package.json` file either directly or via an install package directory and grab all of its dependencies.  This script uses the `npm-importer` script to iterate over all the dependencies downloading, quarantining, scanning and publishing them.

Each of these sripts has a 'help' message that can be accessed by either just executing the script with no arguments or by typing `<script name> -h | --help`.
The sections below provide some additional insights into either how they work, why they work the way they do, and what you should know about what they do.  There is a _Future Improvements_ and _Troubleshooting_ section at the end of this README.

## config-npmrc
This script sets up your personal `.npmrc` file to either to either access the internet NPM registry, use our internal **proxy** to the internet, or use our private one.  The remaining scripts in this README use a `function` to perform the exact same outcome as this convenience script.  This script can be copied to a user's personal tool path, such as $HOME/bin, and used independently of the remaining scripts.  For a complete list of arguments, type `config-npmrc --help`.

#### Commandline Arguments
This script expects one commandline argument that specifies the 'mode' you want to set your `.npmrc` up for.  The list below describes the modes.  In all cases, your 'prefix' is only altered if you use the `--prefix` switch described in the "Switches and Flags" section, below.

1. 'open' :: use the https://registry.npmjs.org/ registry and delete all proxy configurations.  Your 'prefix' will be unaltered  access our local one (the one that does **not** proxy the internet).
2. 'proxy' :: use the internal 'npm-proxy' registry.  There is little reason to use this registry.  This proxy literally proxies requests to the https://registry.npmjs.org/ registry.  It first tries to find the package, and all its dependencies, in the local registry and then fetches and caches them if it can't.  While the local registry is occasionally virus scanned, this leaves a gap of time when the downloaded software is being used that its "hygiene" has not been validated.
3. 'safe' :: use the internal 'npm-mpf' registry.  This registry is **not** proxied and is supposed to represent all NPM modules that have been downloaded, scanned and then uploaded to the internal registry.  Typing `config-npmrc "safe"` ensures that you are using a registry that is **not** accessing the internet.

#### Switches and Flags
In addition to '--help', '--debug' and '--prefix' are the only real flags.
 * `--help` :: print the _help_ or _usage_ message and exit.
 * `--debug` :: collects all the output from debug level messages and bash / terminal commands and presents them as terminal output.  By default, the script redirects all this output to `/dev/null`.
 * `--prefix` :: This switch allows you to set the NPM prefix in your `.npmrc`.  When you type `npm install`, npm will, by default, create a local `node_modules` directory (in your `$CWD`) and start installing your packages into it.  If you use `npm install -g`, npm will install them into `$prefix/lib/node_modules`.  Once this _prefix_ is set in your `.npmrc` it will not be overriden in future calls to this script unless you use the `--prefix` option again to set it to a new path or `reset` it (delete the existing prefix in your `.npmrc` file).

## npm-importer
This script is intended to provide a convenience mechanism for a user to import, in a **safe** manner, an NPM module.  The script will generally perform the following steps:
1.  switch your `.npmrc` configuration to access the https://registry.npmjs.org/ registry.
2. Create a _quarantine_ location in which to download the requested NPM package and all of its dependencies.  The user must have `write` access to the directory location and will be given the chance to remove or keep any existing files at that location.
3. Download the request _package@version_ that the user requested.  The _version' is not necessary.
4. Make a full, and unique list of all dependencies that got downloaded with the package.  When adding dependencies to the list, you will see either a red '\*' or a green '+' indicating that the dependency is already in our list of packages that need to be imported, a red '\*', or is being added newly, a green '+'.
5. For each of the packages in the above list, the script will then check to see if the package and version are in our _internal_ registry.  If they are not, they will be virus scanned.  If a virus is detected in any package, the package is skipped, a noticable error message is printed and a report detailing that a virus was detected for this package is produced; it will be displayed at the end of the script for further action.
6. For all packages that are not in our internal registry and are not infected with a virus, we will publish the package and unique version to the registry.  As a result of a quirk in NPM, sometimes our primary package, the one used on the commandline for this script, will request a version like '2.0.1'.  While installing all the other dependencies, some other package may require a later version of that same package, in this case '3.0.0'.  What will actually get published to our internal registry is the '3.0.0' version.  This is annotated in the output status messages by a green version number at the end of the yellow "Publishing ..." message.  See troubleshooting section at the end of this README for why this is a problem and how to fix it.

#### Commandline Arguments
This script expects / requires only one commandline argument: the NPM package and, optionally, version that you want to **safely** import into our local registry.  For example:
```
npm-importer color@>2.0.0
```
This will import the `color` package that has any version greater than 2.0.0 with all of its dependencies.

#### Switches and Flags
All of these switches and flags are optional, but may be useful in either debugging a problem or fine tuning your use of this script for maximum efficiency.
 * `-h|--help` :: print the _help_ or _usage_ message and exit.
 * `-d|--debug` :: collects all the output from debug level messages and bash / terminal commands and presents them as terminal output.  By default, the script redirects all this output to `/dev/null`.
 * `-c|--cwd` :: much like the `--debug` switch, this switch controls the output from directory-based shell commands like `popd`, `pushd`, `pwd`, etc.  Using this flag will cause all output from those commands to be echoed to `stdout`.  This flag is largely just for development debug and is not needed for any normal operation.
 * `--align` :: This is just an output formatting flag.  It requires an integer argument and just sets an 'indent' of that many spaces at the beginning of every console output line.
 * `--dev` :: A switch that allows you to also download, scan and publish all development dependency packages like you would with `npm install`.  By default, this script acts like `npm install --only=production -g`.  This switch effectively causes a `npm install --development` to be done in the main package; pulling in all its development dependencies and, consequently, their dependencies.
 * `--rebuild-quarantine` :: The default behavior for this script is to check if the _default_ quarantine directory, `/data/npm-quarantine`, exists.  If it does, it will prompt the user to either reuse the directory and its contents or remove the existing directory and recreate it.  This flag is a binary flag that automatically selects the 'force and recreate' mode.  The quarantine directory location is not settable at this time via commandline switches and flags, but is easily settable by searching for `^quarantine=` and replacing the `/data/npm-quarantine` with whatever the user desires (or you could add a commandline flag if you are feeling industrious).
 * `--nocred` :: stands for 'no credentials'.  When you first go to `npm publish` a module, your registry credentials may not be in your `.npmrc`.  As such, this script _assumes_ you need to login initially and prompts you to supply user name, password, and an email address.  If you know your credentials are already valid and don't want to type them in, use `--nocred` and the script will skip the authentication stage.  If you are wrong and have not previously authenticated, the publish step of the script will fail and you'll have to try again.

## toa-ui-importer
While slightly misleading, this script is primarily intended to import all the dependencies (and eventually the development dependencies) for the TOA web UI.  It can generally be used to import all the dependencies listed in _any_ module's `package.json` file, but it was only tested on the TOA web UI.

#### Commandline Arguments
Although the 'help' or 'usage' message makes it appear that you can only provide the `package.json` file for which you are trying to import all the dependencies, you can also use the topmost directory of the module who's dependencies you are trying to satisfy.  For instance, either the following commands will work:
```
toa-ui-importer --nocred $HOME/git/toa/toa-core/web

# or
cd $HOME/git/toa/toa-core/web             # this is optional / for demonstration
toa-ui-importer --nocred package.json
```
#### Switches and Flags
All of these switches and flags are optional, but may be useful in either debugging a problem or fine tuning your use of this script for maximum efficiency.
 * `-h|--help` :: print the _help_ or _usage_ message and exit.
 * `-d|--debug` :: collects all the output from debug level messages and bash / terminal commands and presents them as terminal output.  By default, the script redirects all this output to `/dev/null`.
 * `-c|--cwd` :: much like the `--debug` switch, this switch controls the output from directory-based shell commands like `popd`, `pushd`, `pwd`, etc.  Using this flag will cause all output from those commands to be echoed to `stdout`.  This flag is largely just for development debug and is not needed for any normal operation.
 * `--dev` :: A switch that allows you to also download, scan and publish all development dependency packages like you would with `npm install`.  By default, this script acts like `npm install --only=production -g`.  This switch effectively causes a `npm install --development` to be done in the main package; pulling in all its development dependencies and, consequently, their dependencies.  On the `toa-ui-importer` script, this switch is largely a pass through to the `npm-imporer` script.
 * `--nocred` :: stands for 'no credentials'.  When you first go to `npm publish` a module, your registry credentials may not be in your `.npmrc`.  As such, this script _assumes_ you need to login initially and prompts you to supply user name, password, and an email address.  If you know your credentials are already valid and don't want to type them in, use `--nocred` and the script will skip the authentication stage.  If you are wrong and have not previously authenticated, the publish step of the script will fail and you'll have to try again.  **Note**: if you are trying to import a lot of dependencies, like the TOA UI has, you will absolutely want to use this switch or you will be prompted to authenticate with the local registry for **each** dependency; very annoying!  To authenticate once, just type `config-npmrc 'safe' && npm adduser`.  It will prompt you for your credentials.  Then use this `--nocred` switch which will, in turn, be passed to the `npm-importer` script.

## Troubleshooting
Don't forget about the `--debug` flag on both the `npm-importer` and
`toa-ui-importer` scripts.  The flag will show you the output that tne various
`npm` commands are producing as well as track all the directory traversal that
the script is doing; which is very important to the way NPM works.

#### 'No compatible version found : \<package\>@\<version\>' when trying to install from local registry.
There are two possible reasons you are seeing this error message.
1. If you haven't used `npm-importer` to import the package then, no surprise, its not there and you should use `npm-importer` to import it (That's why I spent all the time writing and documenting it).
2. If you get this error when trying to install some other package that you think you already imported, then you have probably run into the NPM dependency hell problem (affectionately named).  When NPM installs the dependencies of a package, it installs them all in the `node_modules` directory of the parent package.  For instance, if you typed `toa-ui-importer package.json` to import all its dependencies, they will all go in `/data/npm-quarantine/lib/node_modules/toa-ui`.  In addition, dependencies of `toa-ui's` dependencies will also get put in that same location, occasionally changing the version of the package that exists there.  When we publish them to the local registry, we get whatever version exists at that time.  It may **not** be the version that the `toa-ui package.json` file requires.

##### Fixes
For case #1 above, just type `npm-importer <package>@<version>` and then try installing whatever you tried when you got the error message.
For case #2 above, the remedy is acutally the same.  Just type `npm-importer <package>@<version>` and then try importing the `toa-ui` (or whatever package) again.  (I just wanted you to understand **why** you were getting the error)  To date, I think there are about half a dozen packages that the `toa-ui` requires that end up triggering this error.  Since they've been imported (as of 03/19/2020) to our local registry, you should see it happen again until dependency versions or packages are updated for the TOA web UI.


#### 'NotFound : \<package\>@\<version\>'
This error most often occurs with "optional" dependencies.  For whatever
reason, intalling a package with its development dependencies doesn't pick up
one of its dependencies.  This happens, for instance with `chokidar@^1.7.0`.
It always fails to pick up `fsevents@^1.0.0` (in this case its becasue
`fsevents` is intended for another os/arch).  If you determine you need this
package, just try running:
``` bash
# example from grunt-eslint@17.3.1 install
npm-importer --nocred --rebuild-quarantine true --debug esprima@~1.0.2
```

## Future Improvements
 * ~~Add documentation~~ Better than most so I'm calling this 'Done'!
