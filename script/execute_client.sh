#!/bin/sh


echo "Executing '$1' on lakka-6.it.kth.se"
  ssh -o ConnectTimeOut=1 chenli@lakka-6.it.kth.se $1
