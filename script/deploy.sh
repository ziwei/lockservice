#!/bin/sh
APP=lockservice

#Send all files
./execute.sh "rm $APP/src/* && rm $APP/ebin/* && rm $APP/include/* && rm $APP/rel/lockservice.config" 
./send.sh  '../src/*' "/home/chenli/$APP/src/"
./send.sh  '../rel/*' "/home/chenli/$APP/rel"
./send.sh  '../include/*' "/home/chenli/$APP/include"


./execute.sh "$APP/rel/$APP/bin/$APP stop" 
./execute.sh "rm -rf $APP/rel/$APP" 


./execute.sh "cd $APP && ./rebar compile" > /dev/null
./execute.sh "cd $APP && ./rebar generate"
./execute.sh "$APP/rel/$APP/bin/$APP stop"
#./execute.sh "$APP/rel/$APP/bin/$APP start"


#Start client
#./execute_client.sh "cd $APP && rm ebin/* && ./rebar compile"
