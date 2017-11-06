#!/bin/bash

_scriptname="dstds-tools.sh"

#_STEAMPATH="/home/steam/steamcmd/steamcmd.sh"
_STEAMPATH="$(which steamcmd)"
_STEAMUPDARGS="validate"
_DSROOT="/home/dontstarve/DST"
_DSBIN="dontstarve_dedicated_server_nullrenderer"
#_DSARGS="-console" # this arg is deprecated, console is configure in cluster.ini
_DSARGS=
unset _PSR
unset _CONFDIR
unset _CLUSTER

set -x
set -e
export _top_pid=$$
trap "exit 1" TERM

function parse_cluster_directory {
# $1 = path to cluster
	local _cluster_canonical="$(readlink -m "$1")"
	_CLUSTER="$(basename "$_cluster_canonical")"
	_cluster_canonical="$(readlink -m ${_cluster_canonical}/..)"
	_CONFDIR="$(basename "$_cluster_canonical")"
	_PSR="$(readlink -m ${_cluster_canonical}/..)"
	if [[ "$_CONFDIR" == "/" ]]; then
		echo "WARN: Confdir ($_CONFDIR) must not contain slashes! Changing to (.)" >&2
		_CONFDIR="."
	fi
}

function create_cluster {
# $1 = path to cluster
#	TODO
	echo TODO
}

function validate_cluster {
# $1 = path to cluster
	[ -f "$1/cluster.ini" ] || { echo "ERROR: cluster.ini not found." >&2; kill -s TERM $_top_pid; }
# TODO?
}

function start_cluster {
# $1 = path to cluster
	# cluster named by its directory name
	parse_cluster_directory "$1"
	local _cluster_canonical="$(readlink -m "$1")"
	screen -S "$_CLUSTER" -Q select . && {\
		echo "ERROR: screen session already exists, cluster is already running." >&2 ; kill -s TERM  $_top_pid; }
	# check if we should be using shards
	local _use_shard=$(sed -ne '/^shard_enabled/ s/.*= *//p' "$_cluster_canonical"/cluster.ini)
	shopt -s nocasematch
	# If there's no setting or it's garbage, set default here
	[[ "$_use_shard" =~ "true" ]] || [[ "$_use_shard" =~ "false" ]] || \
		_use_shard="true"
	# When shards are used, unset the variable (to enable substituion). Otherwise, set to null value, which will be use in master shard's command line
	[[ $_use_shard =~ "false" ]] && _use_shard="" ||  unset _use_shard

	(
		cd "${_DSROOT}/bin"
		screen -dm -S "$_CLUSTER" -p + -t Master ./$_DSBIN $_DSARGS -persistent_storage_root $_PSR -conf_dir $_CONFDIR -cluster $_CLUSTER ${_use_shard--shard Master}
		sleep 4
#		[ -d "$_cluster_canonical/Caves" ] && \
		[ -z ${_use_shard+x} ] && \
			screen -S "$_CLUSTER" -X screen -t Caves ./$_DSBIN $_DSARGS -persistent_storage_root $_PSR -conf_dir $_CONFDIR -cluster $_CLUSTER -shard Caves
	)

}

function stop_cluster {
# $1 = cluster name (NOT PATH!)
# $2 = announce message (optional)
# $3 = timeout (optional)
	# Stop if screen with such name isn't found
	screen -S $1 -Q select . || {\
		echo "ERROR: screen session with specified name not found." >&2 ; kill -s TERM $_top_pid; }
	# Get list of windows in the session and parse it
	local _swindows=( $(screen -S $1 -Q windows) )
	local _skip="yes"
	local _timeout=${3:-"90"}
	for WINDOW in ${_swindows[@]}; do
		[[ "$_skip" == "yes" ]] && { _skip="no"; continue; }
		(
			[[ "$WINDOW" == "Master" ]] && \
				screen -S $1 -p $WINDOW -X stuff $'c_announce("'"${2:-"Server is shutting down in $_timeout seconds."}"'",nil,"leave_game")\r'
			sleep $_timeout
			# Ctrl+C (SIGINT)
			screen -S $1 -p $WINDOW -X stuff $'\cc'
			# c_shutdown() results in duplicated snapshots
			# screen -S $1 -p $WINDOW -X stuff $'c_shutdown()\r'
		) & sleep 4
		_skip="yes"
	done
	wait
}

function usage {
	cat << EOF
Usage:				dstds-tools.sh [OPTION] [CLUSTER]

This script is a tool to control the execution of the dedicated server executable for Don\'t Starve Together.

Available options are:
  -s CLUSTERPATH		Start DS server cluster located in CLUSTERPATH
  -n CLUSTERPATH		Create new DS server cluster in CLUSTERPATH (start without checking for existence)
  -t CLUSTER			Terminate cluster with specified name
  -b MESSAGE			Broadcast message to all running clusters
  -u				Update infrastructure:
				 0. Notify all clusters about upcoming downtime (90 seconds)
				 1. Terminate all clusters
				 2. Update DST DS steam app.
				 3. Update mods.
				 4. Restart previously running clusters.

EOF
}

function update_all {
# TODO
	echo TODO
#	exit 1
	# Work-in-progress
	# TODO - note and stop all running clusters
	"$_STEAMPATH" \
		+@ShutdownOnFailedCommand 1 \
		+@NoPromptForPassword 1 \
		+login anonymous \
		+force_install_dir "$_DSROOT" \
		+app_update 343050 \
		+quit
	sleep 10
#	(
#		cd "${_DSROOT}/bin"
#		./$_DSBIN -only_update_server_mods
#	)
	# TODO - restart noted clusters
}

while getopts "s:n:t:b:u" OPT; do
	case $OPT in
	  s)
		# Start existing cluster
		validate_cluster "$OPTARG"
		start_cluster "$OPTARG"
		;;
	  n)
		# Create new cluster
		start_cluster "$OPTARG"
		;;
	  t)
		# Terminate cluster by name
		stop_cluster "$OPTARG" '' "15"
		;;
	  b)
		# TODO
		echo "NOT IMPLEMENTED"
		;;
	  u)
		update_all
		;;
	  \?)
		echo "Invalid option: -$OPTARG" >&2
		usage
		;;
	  :)
		echo "Option $OPTARG requires an argument." >&2
		;;
	  *)
		usage
		;;
	esac
done
