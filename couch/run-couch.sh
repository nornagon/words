#!/bin/sh
cd `dirname $0`
couchdb -a default.ini -b
