#!/bin/bash

# Configuration

. ./config.sh

echo "Setup sample JBoss A-MQ demo application: Scaling the application"
. ./setp-login.sh
echo "	--> Find the application replication controller"
OPENSHIFT_APPLICATION_REPLICATION_CONTROLLER=`oc get rc -l app=fuse-amq | sed '1d' | awk '$2 > 0 { printf $1 }'` || { echo "FAILED" && exit 1; }
echo "		--> Found ${OPENSHIFT_APPLICATION_REPLICATION_CONTROLLER}"
echo "	--> Scaling application to 3 instances"
oc scale rc/${OPENSHIFT_APPLICATION_REPLICATION_CONTROLLER} --replicas=3 || { echo "FAILED" && exit 1; }
echo "	--> press enter to continue" && read
echo "	--> Attempting to locate original pod"
OPENSHIFT_AMQ_BROKER_POD_ORIGINAL=`oc get pods | sed '1d' | head -n 1 | awk '{printf $1}'` || { echo "FAILED" && exit 1; }
echo "	--> Forcefully destroy the original pod"
oc delete pod ${OPENSHIFT_AMQ_BROKER_POD_ORIGINAL}

echo "Done"
