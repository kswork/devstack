#!/usr/bin/env bash

# **exercise.sh** - using the cloud can be fun

# we will use the ``nova`` cli tool provided by the ``python-novaclient``
# package
#


# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace


# Settings
# ========

# Use openrc + stackrc + localrc for settings
source ./openrc

# Get a token for clients that don't support service catalog
# ==========================================================

# manually create a token by querying keystone (sending JSON data).  Keystone
# returns a token and catalog of endpoints.  We use python to parse the token
# and save it.

TOKEN=`curl -s -d  "{\"auth\":{\"passwordCredentials\": {\"username\": \"$NOVA_USERNAME\", \"password\": \"$NOVA_API_KEY\"}}}" -H "Content-type: application/json" http://$HOST_IP:5000/v2.0/tokens | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['access']['token']['id'];"`

# Launching a server
# ==================

# List servers for tenant:
nova list

# Images
# ------

# Nova has a **deprecated** way of listing images.
nova image-list

# But we recommend using glance directly
glance -A $TOKEN index

# Let's grab the id of the first AMI image to launch
IMAGE=`glance -A $TOKEN index | egrep ami | cut -d" " -f1`

# Security Groups
# ---------------
SECGROUP=test_secgroup

# List of secgroups:
nova secgroup-list

# Create a secgroup
nova secgroup-create $SECGROUP "test_secgroup description"

# determine flavor
# ----------------

# List of flavors:
nova flavor-list

# and grab the first flavor in the list to launch
FLAVOR=`nova flavor-list | head -n 4 | tail -n 1 | cut -d"|" -f2`

NAME="myserver"

nova boot --flavor $FLAVOR --image $IMAGE $NAME --security_groups=$SECGROUP

# Testing
# =======

# First check if it spins up (becomes active and responds to ping on
# internal ip).  If you run this script from a nova node, you should
# bypass security groups and have direct access to the server.

# Waiting for boot
# ----------------

# let's give it 10 seconds to launch
sleep 10

# check that the status is active
nova show $NAME | grep status | grep -q ACTIVE

# get the IP of the server
IP=`nova show $NAME | grep "private network" | cut -d"|" -f3`

# for single node deployments, we can ping private ips
MULTI_HOST=${MULTI_HOST:-0}
if [ "$MULTI_HOST" = "0" ]; then
    # ping it once (timeout of a second)
    ping -c1 -w1 $IP || true

    # sometimes the first ping fails (10 seconds isn't enough time for the VM's
    # network to respond?), so let's wait 5 seconds and really test ping
    sleep 5

    ping -c1 -w1 $IP
fi

# Security Groups & Floating IPs
# ------------------------------

# allow icmp traffic (ping)
nova secgroup-add-rule $SECGROUP icmp -1 -1 0.0.0.0/0

# List rules for a secgroup
nova secgroup-list-rules $SECGROUP

# allocate a floating ip
nova floating-ip-create

# store  floating address
FLOATING_IP=`nova floating-ip-list | grep None | head -1 | cut -d '|' -f2 | sed 's/ //g'`

# add floating ip to our server
nova add-floating-ip $NAME $FLOATING_IP

# sleep for a smidge
sleep 5

# ping our floating ip
ping -c1 -w1 $FLOATING_IP

# pause the VM and verify we can't ping it anymore
nova pause $NAME

sleep 1

if ( ping -c1 -w1 $FLOATING_IP ); then
    echo "Pause failure - ping shouldn't work"
    exit 1
fi

# unpause the VM and verify we can ping it again
nova unpause $NAME

sleep 1

ping -c1 -w1 $FLOATING_IP

# dis-allow icmp traffic (ping)
nova secgroup-delete-rule $SECGROUP icmp -1 -1 0.0.0.0/0

# sleep for a smidge
sleep 5

# ping our floating ip
if ( ping -c1 -w1 $FLOATING_IP ); then
    print "Security group failure - ping should not be allowed!"
    exit 1
fi

# de-allocate the floating ip
nova floating-ip-delete $FLOATING_IP

# shutdown the server
nova delete $NAME

# Delete a secgroup
nova secgroup-delete $SECGROUP

# FIXME: validate shutdown within 5 seconds
# (nova show $NAME returns 1 or status != ACTIVE)?

# Testing Euca2ools
# ==================

# make sure that we can describe instances
euca-describe-instances
