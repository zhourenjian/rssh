# rssh
A reverse SSH remote login daemon. This daemon script is based on socat network utilities. And it requires to be run on both client machine and server. 

## Install socat
### Linux
```
sudo yum install socat
```

### Mac
```
brew install socat
```

### OpenWRT Router
```
opkg update 
opkg upgrade
opkg install socat
```

## Run Daemon on Server with Public Internet
```
mkdir rssh
cd rssh
wget https://github.com/zhourenjian/rssh/blob/master/daemon.sh
wget https://github.com/zhourenjian/rssh/blob/master/mbp.server.ini
chmod +x daemon.sh
./daemon.sh mbp.server.ini start
```
Please modify the listening port in the configuration file before running daemon.sh.
Here is the example configuration:
```
daemon.mode=server
daemon.port=2332
daemon.ssh.listen=2002
daemon.socat.path=/usr/bin/socat
daemon.verbose.flag=-d -d
daemon.logs.path=/tmp/rssh
```
The daemon.port is the port for remote target machine to connect. The daemon.ssh.listen is the port for public SSH port to access target machine.


## Run Daemon on Target Machine
```
mkdir rssh
cd rssh
wget https://github.com/zhourenjian/rssh/blob/master/daemon.sh
wget https://github.com/zhourenjian/rssh/blob/master/mbp.client.ini
chmod +x daemon.sh
vim mbp.client.ini
./daemon.sh mbp.server.ini start
```
Please modify server IP or port in the configuration file before running daemon.sh.
Here is the example configuration:
```
daemon.mode=client
daemon.host=###.###.###.###
daemon.port=2332
daemon.ssh.host=127.0.0.1
daemon.ssh.port=22
daemon.socat.path=/usr/local/bin/socat
daemon.verbose.flag=-d -d
daemon.logs.path=/tmp/rssh
```
The daemon.port is the remote server port for target machine to connect. 

## Access Target Machine

```
ssh -p #### user@###.###.###.###
```
The port is the port configured daemon.ssh.listen item and the IP is the server IP.


## Features
1. Both server and target machine can run multiple daemons
2. The reverse SSH daemon is always be running and there is monitors keeping both sides working.
3. No root privileges are required on servers, not harming servers

## Known Faults
1. Only one SSH login sessions is supported for a time.
Solution: Use SSH tunnel, if you need more sessions simulataneously.

2. After SSH logout, there are about 10 seconds gap
Solution: Adjust the sleep time in the daemon script

