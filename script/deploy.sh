#!/bin/sh
APP=lockservice

./send.sh '../src/*' "/home/chenli/$APP/src/"
./send.sh '../rel/*' "/home/chenli/$APP/rel"

./execute.sh "$APP/rel/$APP/bin/$APP stop"
./execute.sh "rm -rf $APP/rel/$APP"

./execute.sh "cd $APP && ./rebar compile && ./rebar generate"
./execute.sh "$APP/rel/$APP/bin/$APP start"

# generate and run the release
#./execute.sh 'cd ~/gaoler && ./rebar generate && rel/gaoler/bin/gaoler start'
