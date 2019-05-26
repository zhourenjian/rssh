#!/bin/sh
# 
# This script will provide a way to bring SSH remote login to intranet machine to public internet, using socat.
#
# Author: zhourenjian@gmail.com
# https://github.com/zhourenjian/rssh
# Date: May, 2019
# License: MIT
#

# Load port, mode, host and get daemon PID
loaddaemonpid () {
	port=`getconfigbykey daemon.port`
	if [ "" = "$port" ] ; then port=443 ; fi
	mode=`getconfigbykey daemon.mode`
	if [ "$mode" = "server" ] ; then
		daemonpid=`getpidbyargs socat ":${port}"`
	else
		host=`getconfigbykey daemon.host`
		daemonpid=`getpidbyargs socat "${host}:${port}"`
	fi
}

preparerun () {
	# determine socat location
	socatpath=`which socat`
	if [ "" = "$socatpath" ] ; then
		socatpath=`getconfigbykey daemon.socat.path`
		if [ "" = "$socatpath" ] ; then
			if [ "`uname -a | grep -E "(WRT|LEDE)"`" = "" ] ; then
				socatpath=/usr/bin/socat
			else
				socatpath=/opt/bin/socat
			fi
		fi
	fi
}

runapp () {
	sslkey=`getconfigbykey ssl.key`
	sslcert=`getconfigbykey ssl.cert`
	if [ "$mode" = "server" ] ; then
		sshlisten=`getconfigbykey ssh.listen`
		if [ "" = "$sslkey" ] ; then
			$socatpath ${verbose} TCP-LISTEN:${port},reuseaddr TCP-LISTEN:${sshlisten},reuseaddr
		else
			$socatpath ${verbose} OPENSSL-LISTEN:${port},reuseaddr TCP-LISTEN:${sshlisten},reuseaddr
		fi
		logging INFO "Daemon process exits. New deamon process will start."
		sleep 1
	else
		startedts=`date "+%s"`
		sshhost=`getconfigbykey ssh.host`
		if [ "" = "$sshhost" ] ; then sshhost=127.0.0.1 ; fi
		sshport=`getconfigbykey ssh.port`
		if [ "" = "$sshport" ] ; then sshport=22 ; fi
		if [ "" = "$sslkey" ] ; then
			$socatpath ${verbose} TCP:${host}:${port} TCP:${sshhost}:${sshport}
		else
			$socatpath ${verbose} OPENSSL-CONNECT:${host}:${port} TCP:${sshhost}:${sshport}
		fi
		logging INFO "Daemon process exits. New deamon process will start."
		# Sleep more seconds than server end. So its has time to be ready
		sleep 3
	fi
}

preparemonitor () {
	connoks=0
	connerrors=0
}

monitorapp () {
	# check ESTABLISHED connection status
	checkconnection=`netstat -tan 2>/dev/null | grep "${port} " | grep EST`
	if [ "" = "$checkconnection" ] ; then
		logging ERROR "Daemon is not being connected."
		connoks=0
		connerrors=`expr $connerrors + 1`
	else
		if [ $connerrors -gt 0 ] ; then logging INFO "Daemon is being connected again." ; fi
		connerrors=0
		connoks=`expr $connoks + 1`
	fi
	if [ $connerrors -gt $maxerrors ] ; then
		if [ "" != "$daemonpid" ] ; then
			echo "$daemonpid" | xargs kill -9
		fi
		logging ERROR "Daemon is not being connected for $connerrors times. Daemon is killed by monitor."
		connerrors=0
	fi
}

daemonfilename=`basename "$0"`

cd "`dirname $0`"
scriptfolder=`pwd -P`
source ${scriptfolder}/daemon.sh