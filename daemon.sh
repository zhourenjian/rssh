#!/bin/sh
# 
# This script is a daemon template.
#
# Author: zhourenjian@gmail.com
# https://github.com/zhourenjian/rssh
# Date: May, 2019
# License: MIT
#

# Copy and uncomment the following line to daemon app script.
# daemonfilename=`basename "$0"`
if [ "" = "$daemonfilename" ] ; then
	echo "Variable "daemonfilename" needs to be set correctly before calling this daemon script."
	exit 0
fi

configdefaultextension=ini
daemonname=${daemonfilename%.*}.${configdefaultextension}
deamonallactions="start|stop|reload|restart|status|dailyclean"
printusage () {
	echo "Usage:"
	echo "  $0 [ [--config|-c] <config path> ] <$deamonallactions [days old]>"
	echo "  $0 <$deamonallactions> [ [--config|-c] <config path> ]"
	echo "     --config, -c  default config path is $daemonname, can be configured with file name with or without extension(.${configdefaultextension}) or absolute file path"
}

if [ "" = "$1" ] ; then
	printusage
	exit 0
fi

# If daemonhome is empty, the shell script's grandparent folder will be daemon home
daemonhome=
currentfolder=`pwd -P`
cd "`dirname $0`"
scriptfolder=`pwd -P`
if [ "" = "$daemonhome" ] ; then
	subfolder=`basename "$scriptfolder"`
	if [ "$subfolder" = "bin" ] ; then
		cd ..
	fi
	daemonhome=`pwd -P`
fi
cd "$currentfolder"
scriptpath=$scriptfolder/$daemonfilename

daemonaction=
if [ "`echo "$1" | grep -E "^($deamonallactions|run|monitor)$"`" != "" ] ; then
	daemonaction=$1
	shift
fi

# rawconfig* variables will keep origional arguments for sub-process
rawconfigprefix=
rawconfigpath=
if [ "$1" = "--config" ] || [ "$1" = "-c" ] ; then
	rawconfigprefix=$1
	if [ "" = "$2" ] ; then
		printusage
		exit 0
	fi
	rawconfigpath=$2
	daemonname=$2
	if [ "`echo "$daemonname" | grep -E "^.+\..+$"`" = "" ] && [ "`echo "$daemonname" | grep -E "^.+/.+$"`" = ""] ; then
		daemonname=${daemonname}.${configdefaultextension}
	fi
	shift
	shift
else
	if [ -f "$1" ] ; then
		rawconfigpath=$1
		daemonname=$1
		shift
	fi
fi


if [ "$daemonaction" = "" ] ; then
	if [ "`echo "$1" | grep -E "^($deamonallactions|run|monitor)$"`" != "" ] ; then
		daemonaction=$1
		shift
	fi
fi


# Construct absolute path of configuration file
if [ "`echo "$daemonname" | grep -E "^/.*$"`" != "" ] ; then
	daemonconfig=$daemonname
elif [ "`echo "$daemonname" | grep -E "^.+/.+$"`" != "" ] ; then
	cd "`dirname $daemonname`"
	daemonconfig=`pwd -P`/`basename "$daemonname"`
elif [ "$subfolder" = "bin" ] ; then
	daemonconfig=$daemonhome/etc/$daemonname
else
	daemonconfig=$daemonhome/$daemonname
fi

if [ ! -f $daemonconfig ] ; then
	echo "Configuration file $daemonconfig does not exist!"
	exit 0
fi

# generate secret key to avoid calling $0 run directly from command line
md5path=`which md5sum`
if [ "" = "$md5path" ] ; then
	# Mac OSX
	md5path=`which md5`
fi
if [ "" = "$md5path" ] ; then
	daemonhash=`echo "$daemonconfig" | sed "s/[\/ ]/./g"`
else
	daemonhash=`echo "$daemonconfig" | $md5path | awk '{print $1}'`
fi

# Some shells may have different arguments for "ps"
if [ "`uname -a | grep -E "(WRT|LEDE)"`" = "" ] ; then
	psargs=ax
else
	psargs=-w
fi

getconfigbykey () {
	if [ "" = "$daemoncfgcontent" ] ; then
		daemoncfgcontent=`cat $daemonconfig`
	fi
	echo "$daemoncfgcontent" | grep "$1" | grep -v "#" | tail -n 1 | awk -F '=' '{print $2}'
}

getpidbyargs () {
	ps $psargs | grep "$1" | grep "$2" | grep -v grep | awk '{print $1}'
}

# For run and monitor sub-process
logging () {
	if [ "" != "$verbose" ] ; then echo "[`date`] [$1] $2"; fi
}

# Run daemon in while loop to keep restarting daemon on crashes
if [ "$daemonaction" = "run" ] ; then
	# An extra argument to avoid calling $0 run directly from command line
	if [ "$1" != "$daemonhash" ] ; then
		printusage
		exit 0
	fi

	preparerun

	while [ 1 ] ; do
		daemoncfgcontent=
		verbose=`getconfigbykey daemon.verbose.flag`
		loaddaemonpid
		if [ "" != "$daemonpid" ] ; then
			echo "$daemonpid" | xargs kill -9
			logging WARN "Kill existed daemon process $daemonpid."
		fi

		runapp
	done
	exit 0
fi

# Monitor daemon. If daemon process is not providing services, kill process to restart daemon
if [ "$daemonaction" = "monitor" ] ; then
	# An extra argument to avoid calling $0 run directly from command line
	if [ "$1" != "$daemonhash" ] ; then
		printusage
		exit 0
	fi
	# check interval(unit:second)
	checkinterval=7
	maxerrors=3
	noprocesscount=0

	preparemonitor

	while [ 1 ] ; do
		daemoncfgcontent=
		verbose=`getconfigbykey daemon.verbose.flag`
		# Check daemon process
		loaddaemonpid
		if [ "" = "$daemonpid" ] ; then
			noprocesscount=`expr $noprocesscount + 1`
			if test $noprocesscount -gt 3 ; then
				runpid=`getpidbyargs " run $daemonhash" "$scriptpath"`
				if [ "" = "$runpid" ] ; then
					# Daemon run process does not exist, might be killed intentionally
					logging INFO "Monitor exits as daemon is detected as stopped."
					break
				fi
				if [ "`expr $noprocesscount % 7`" = "4" ] ; then
					logging INFO "No daemon is detected. Waiting for \"run\" process to bring it back."
				fi
			fi
			# Sleep and wait for "run" process to bring up daemon
			sleep 3
			continue
		else
			noprocesscount=0
		fi

		sleep $checkinterval

		monitorapp
	done
	exit 0
fi

# Stop daemon running
if [ "$daemonaction" = "stop" ] ; then
	runpid=`getpidbyargs " run $daemonhash" "$scriptpath"`
	if [ "" != "$runpid" ] ; then
		echo "$runpid" | xargs kill -9
		echo "Daemon has been stopped."
	else
		echo "Daemon is not running. Do nothing."
	fi
	monitorpid=`getpidbyargs " monitor $daemonhash" "$scriptpath"`
	if [ "" != "$monitorpid" ] ; then
		echo "$monitorpid" | xargs kill -9
		echo "Daemon monitor has been stopped."
	else
		echo "Daemon monitor is not running. Do nothing."
	fi
	loaddaemonpid
	if [ "" != "$daemonpid" ] ; then
		echo "$daemonpid" | xargs kill -9
		echo "Daemon has been stopped."
	else
		echo "Daemon is not running. Do nothing."
	fi
	exit 0
fi

# Restart daemon
if [ "$daemonaction" = "restart" ] ; then
	if [ "" = "$rawconfigpath" ] ; then
		$scriptpath stop
		$scriptpath start
	elif [ "" = "$rawconfigprefix" ] ; then
		$scriptpath "$rawconfigpath" stop
		$scriptpath "$rawconfigpath" start
	else
		$scriptpath $rawconfigprefix "$rawconfigpath" stop
		$scriptpath $rawconfigprefix "$rawconfigpath" start
	fi
	exit 0
fi

# Reload daemon
if [ "$daemonaction" = "reload" ] ; then
	loaddaemonpid
	if [ "" != "$daemonpid" ] ; then
		echo "$daemonpid" | xargs kill -9
		echo "Kill daemon(pid=$daemonpid), \"run\" process will restart daemon and reload updated configuration."
		echo -n "Waiting 5 seconds to check running status."
		for s in `seq 1 5` ; do sleep 1 ; echo -n "." ; done
		echo "."
		loaddaemonpid
		if [ "" = "$daemonpid" ] ; then
			echo "Daemon is not running again!"
		else
			echo "Daemon is running again, pid=$daemonpid"
		fi
	else
		echo "Daemon process doees not exist."
	fi
	exit 0
fi

# Check daemon status
if [ "$daemonaction" = "status" ] ; then
	loaddaemonpid
	if [ "" = "$daemonpid" ] ; then
		echo "Daemon is not running."
	else
		echo "Daemon is running, pid=$daemonpid"
	fi
	exit 0
fi

# Prepare logging
logspath=`getconfigbykey daemon.logs.path`
if [ "" = "$logspath" ] ; then
	if [ "$subfolder" = "bin" ] ; then
		logspath=$daemonhome/logs
	else
		logspath=$daemonhome
	fi
fi
if [ ! -d $logspath ] ; then
	mkdir -p $logspath
fi

daemonname=`basename "$daemonconfig"`
daemonlogprefix=${daemonname%.*}.run
monitorlogprefix=${daemonname%.*}.monitor
errsuffix=err
logsuffix=log

# Start daemon
if [ "$daemonaction" = "start" ] ; then
	runpid=`getpidbyargs " run $daemonhash" "$scriptpath"`
	if [ "" != "$runpid" ] ; then
		echo "$runpid" | xargs kill -9
	fi
	monitorpid=`getpidbyargs " monitor $daemonhash" "$scriptpath"`
	if [ "" != "$monitorpid" ] ; then
		echo "$monitorpid" | xargs kill -9
	fi
	echo "Daemon is starting..."
	daemonlogpath=$logspath/${daemonlogprefix}.${logsuffix}
	daemonerrpath=$logspath/${daemonlogprefix}.${errsuffix}
	monitorlogpath=$logspath/${monitorlogprefix}.${logsuffix}
	monitorerrpath=$logspath/${monitorlogprefix}.${errsuffix}
	if [ "" = "$rawconfigpath" ] ; then
		$scriptpath run $daemonhash >>$daemonlogpath 2>>$daemonerrpath &
		sleep 3
		$scriptpath status
		$scriptpath monitor $daemonhash >>$monitorlogpath 2>>$monitorerrpath &
	elif [ "" = "$rawconfigprefix" ] ; then
		$scriptpath "$rawconfigpath" run $daemonhash >>$daemonlogpath 2>>$daemonerrpath &
		sleep 3
		$scriptpath "$rawconfigpath" status
		$scriptpath "$rawconfigpath" monitor $daemonhash >>$monitorlogpath 2>>$monitorerrpath &
	else
		$scriptpath $rawconfigprefix "$rawconfigpath" run $daemonhash >>$daemonlogpath 2>>$daemonerrpath &
		sleep 3
		$scriptpath $rawconfigprefix "$rawconfigpath" status
		$scriptpath $rawconfigprefix "$rawconfigpath" monitor $daemonhash >>$monitorlogpath 2>>$monitorerrpath &
	fi
	exit 0
fi

rotating() {
	/bin/cp -f $logspath/${1}.${2} $logspath/${1}.${3}.${2}
	echo -n "" >$logspath/${1}.${2}
}

# Clean old log files
if [ "$daemonaction" = "dailyclean" ] ; then
	daysold=14
	if [ "" != "$1" ] ; then
		if [ "`echo "$1" | grep -E "^[0-9]+$"`" != ""] ; then
			daysold=$1
		else
			printusage
			exit 0
		fi
	fi
	if [ -d "$logspath" ] ; then
		now=`date "+%s"`
		daysago=`expr $now - $daysold \* 86400`
		if [ "`echo "$OSTYPE" | grep -E "^darwin.*$"`" != "" ]; then
			oldlogpattern=`date -r $daysago "+%Y-%m-%d"`
			nowlogpattern=`date -r $now "+%Y-%m-%d"`
		else
			oldlogpattern=`date --date="@$daysago" "+%Y-%m-%d"`
			nowlogpattern=`date --date="@$now" "+%Y-%m-%d"`
		fi
		# Use "/bin/" to avoid using aliased command
		/bin/rm -f $logspath/*${oldlogpattern}.${logsuffix}
		/bin/rm -f $logspath/*${oldlogpattern}.${errsuffix}
		rotating $daemonlogprefix ${logsuffix} $nowlogpattern
		rotating $daemonlogprefix ${errsuffix} $nowlogpattern
		rotating $monitorlogprefix ${logsuffix} $nowlogpattern
		rotating $monitorlogprefix ${errsuffix} $nowlogpattern
		echo "Logs files are rotated."
	else
		echo "Logs path $logspath does not exist!"
	fi
	exit 0
fi

echo "Unknown arguments: $*"
printusage
