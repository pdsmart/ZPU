#!/bin/bash -x
#########################################################################################################
##
## Name:            run_quartus.sh
## Created:         August 2019
## Author(s):       Philip Smart
## Description:     A shell script to start the Quartus Prime Docker image.
##
## Credits:         
## Copyright:       (c) 2019 Philip Smart <philip.smart@net2net.org>
##
## History:         August 2019   - Initial module written.
##
#########################################################################################################
## This source file is free software: you can redistribute it and#or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This source file is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
#########################################################################################################

# Configurable parameters. The MAC_ADDRESS is needed if you are using a licensed Quartus as it uses the hostid which is the mac address.
# Set a default for the X-Display if the environment hasnt set it.
#
MAC_ADDR="02:50:dd:72:03:01"
PROJECT_DIR_HOST=/srv/quartus
PROJECT_DIR_IMAGE=/srv/quartus
DISPLAY=${DISPLAY:-192.168.15.210:0}
VERSION=$1

if [ "${VERSION}" = "17.1.1" -o "X${VERSION}" = "X" ]; then
    VERSION=17.1.1
elif [ "${VERSION}" != "13.0.1" -a "${VERSION}" != "13.1" ]; then
    echo "Unknown QuartusII version:$1"
fi
# In order to get X-Forwarding from the container, we need to update the X Authorities and bind the authorisation file inside the virtual machine.
XSOCK=/tmp/.X11-unix
XAUTH=/tmp/.docker.xauth
NLIST=`xauth nlist $DISPLAY | sed -e 's/^..../ffff/'`
if [ "${NLIST}" != "" ]; then
    echo ${NLIST} | xauth -f $XAUTH nmerge -
fi
chmod 777 $XAUTH

# Run the Ubuntu hosted Quartus Prime service.
docker run --rm \
		   --mac-address "${MAC_ADDR}" \
		   --env DISPLAY=${DISPLAY} \
		   --ipc=host \
		   --env XAUTHORITY=${XAUTH} \
		   --privileged \
		   --volume /dev:/dev \
		   --volume ${PROJECT_DIR_HOST}:${PROJECT_DIR_IMAGE} \
		   --volume ${XAUTH}:${XAUTH} \
		   --volume ${XSOCK}:${XSOCK} \
		   --volume /sys:/sys:ro \
		   --name quartus${VERSION} \
		   quartus-ii-${VERSION} &

# Bring up a terminal session for any local changes.
sleep 5
docker exec -it quartus${VERSION} bash
