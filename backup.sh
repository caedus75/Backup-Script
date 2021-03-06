#!/bin/bash
#
# Copyright (c) 2014 Carlos Millett
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#


### Define some versioning variables.
PKG='backup'
VERSION='__version'
VDATE='__vdate'

### Set modes and traps.
set -o errexit

trap "cleanup 'Aborting'" ERR
trap "cleanup 'Terminated by user'" SIGINT SIGTERM SIGKILL
trap cleanup EXIT

### Define functions.
## Create folder on /tmp and return the path.
tempdir() {
    local dir="arch-$(date "+%Y-%m-%d")"
    local path="/tmp/${dir}"

    mkdir ${path}
    echo ${path}
}
## Use rsync to sync files.
bkp() {
    local SRC="${1}"
    local DEST="${2}"
    declare -a OPTS=("${!3}")

    printf "Sync %s\n" ${SRC}
    rsync "${OPTS[@]}" ${SRC} ${DEST} 2>/dev/null
    sleep 3
    printf "Done\n"
}

## Create a tar file with a README inside.
readme() {
    local TMP="${1}"

    cat <<-INFO > ${TMP}/README
Configuration files and folders.

The name of the folder here tells you were the config files goes!
    * dot = home folder, hidden files they are.
    * config = .config folder, put them where they belong.
    * localshare = .local/share, an unusual place to these important ones.

Now you know everything you should, restore your things! ;)
INFO

    tar -cf ${TMP}.tar --directory=${TMP} README
}

## Pack dotfiles in a nice tar file.
dot() {
    local TMP="${1}"
    local TAR="${2}"
    declare -a SRCS=("${!3}")

    [[ -e ${TAR} ]] || readme ${TMP}

    printf "Adding %s configuration files to tar archive\n" ${MODE}
    mkdir -p ${TMP}/home/{dot,config,localshare}
    for one in ${SRCS[@]}; do
        local one_="${HOME}/${one}"
        [[ -e ${one_} ]] || continue
        case $(echo ${one} | awk -F '/' '{ print $1 }') in
            ".config") cp -r ${one_} ${TMP}/home/config ;;
            ".local") cp -r ${one_} ${TMP}/home/localshare ;;
            *) cp -r ${one_} ${TMP}/home/dot/$(echo ${one} | sed 's/^.//') ;;
        esac
    done
    tar -rf ${TAR} --directory=${TMP} home
    sleep 3
}

## Compress tar file and send it to server with correct name.
gzipit() {
    local TAR="${1}"
    local DEST="${2}"
    local opts=('-a' '-i')

    printf "Compressing archive with gzip\n"
    gzip ${TAR}

    printf "Syncing archive to server\n"
    bkp "${TAR}.gz" "${DEST}" opts[@]
}

## Cleanup the mess.
cleanup() {
    [[ -n ${1} ]] && printf "%s\n" "${1}"
    [[ -e ${DIR} ]] && rm -r "${DIR}"
    exit
}

### Define main.
# Source config file.
[[ -e ${HOME}/.config/backup.conf ]] || printf "Can't read config file.\n"
source ${HOME}/.config/backup.conf

# Show message and exit if asking for help
if [[ ${1} =~ ^--?[hv] ]]; then
    case ${1} in
        "-h" | "--help")
            printf "\$ %s home  web  chrome  dotfiles\n" ${PKG}
            printf "%s\n"\
                "all        = execute all options below"\
                "home       = home folder"\
                "extra      = everything else"\
                "dotfiles   = .files and .folders"
            ;;
        "-v" | "--version")
            printf "%s © Caedus75\n" ${PKG}
            printf "Version %s (%s)\n" ${VERSION} "${VDATE}"
            ;;
    esac
    exit
fi

# Check if destination is remote and online.
if [[ -n ${SERVER} ]]; then
    ping -c 1 -w 5 ${SERVER} >/dev/null 2>&1
    SERVER+=":"
fi

# Loop through all CLI options.
while (( "$#" )); do
    case ${1} in
        all | home)
            DEST="${SERVER}${DESTH}"
            for per in ${HOMEDIR}; do
                [[ -n ${per} && -e ${per} ]] || continue
                bkp "${per}" "${DEST}" RSYNCOPT[@]
            done
            ;;&
        all | extra)
            DEST="${SERVER}${DESTO}"
            for ex in ${OTHERDIR}; do
                [[ -n ${ex} && -e ${ex} ]] || continue
                bkp "${ex}" "${DEST}" RSYNCOPT[@]
            done
            ;;&
        all | dotfiles)
            DIR="$(tempdir)"
            TAR="${DIR}.tar"
            DEST="${SERVER}${DESTD}"
            [[ ${#homeconf[@]} -ne 0 ]] && dot ${DIR} ${TAR} homeconf[@]
            [[ -e ${TAR} ]] && gzipit "${TAR}" "${DEST}"
            ;;&
        all)
            break
            ;;
    esac
    shift
done
