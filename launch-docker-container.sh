#!/bin/sh

name=$(basename $0)
if [ ".$name" = ".launch-docker-container.sh" ]; then
  cat <<EOF 
$0
please link this script to the container image you like to run

e.g. to launch latest alpine image with the current working directory mounted:

$ ln -s launch-docker-container.sh alpine
$ ./alpine
/u # ls
alpine                   launch-docker-container.sh
/u # uname -a
Linux 68b18fa5b4d4 4.9.75-linuxkit-aufs #1 SMP Tue Jan 9 10:58:17 UTC 2018 x86_64 Linux
/u # exit

It also accept arguments:

$ alpine uname -a
Linux 3b18ba5282f3 4.9.75-linuxkit-aufs #1 SMP Tue Jan 9 10:58:17 UTC 2018 x86_64 Linux
$
EOF
  exit 1
fi

img=$(docker images -q $name)
if [ -z "$img" ]; then
  echo "docker image $name doesn't exist"
fi

exec docker run -ti --rm -v ${PWD}:/u --workdir /u $name $@
