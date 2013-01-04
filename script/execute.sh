#!/bin/sh

for i in 1 2 3 4 5
do

echo "Executing '$1' on lakka-$i.it.kth.se"
  ssh -o ConnectTimeOut=1 chenli@lakka-$i.it.kth.se $1

done
