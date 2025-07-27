#!/bin/bash
forever list | while read line
do
  if [ "`echo $line | grep 'obata_test.js'`" ]; then
    bno=$(grep -oP '\[[0-9]+\]' <<< "$line")
    fno=$(grep -oP '[0-9]+' <<< "$bno")
    cmd="forever restart ${fno}"
    eval ${cmd}
  fi
  #echo "$line"
done
