#!/bin/bash -x -e
cd /quickstart-linux-utilities
source quickstart-cfn-tools.source
qs_retry_command 50 ls /opt/corda/logs/*log
qs_cloudwatch_tracklog $(/bin/ls /opt/corda/logs/*log)
