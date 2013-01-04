#!/bin/sh


for i in 1 2 3 4 5
do

echo "Sending to lakka-$i.it.kth.se"
`scp -o ConnectTimeOut=1 -r $1 chenli@lakka-$i.it.kth.se:$2`

done
