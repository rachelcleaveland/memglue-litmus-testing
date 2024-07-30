#!/bin/bash

export PATHTOMEMGLUEOUTPUTS=tests/MemGlueMSILitmusTests
PATHTOBASELITMUS=logs
TRANSLATELITMUSFILE=util/TranslateLitmus.py
MEMGLUETEMPLATE=MemGlueMSITemplate
LOGNAME=all-msi.log

PASSED=0
FAILED=0
INCONC=0
ALLRUN=0
ERRORS=0

${PATHTOLITMUSTESTS=tests/MemGlueLitmusTests}

if [ "$1" = "all" ]; then
  echo "Running all tests in $PATHTOLITMUSTESTS"
  mkdir -p $PATHTOMEMGLUEOUTPUTS
  rm "$PATHTOBASELITMUS"/$LOGNAME
  for file in $PATHTOLITMUSTESTS/*
  do
    echo "Translating $file..."
    python3 util/LitmusDistributeCores.py $file $PATHTOMEMGLUEOUTPUTS models/$MEMGLUETEMPLATE.m
  done
  for file in $PATHTOMEMGLUEOUTPUTS/*
  do
    echo "Filtering $file..."
    python3 util/filterWeakMSITests.py $file
  done
  
  for file in $PATHTOMEMGLUEOUTPUTS/*
  do
    filename=$(basename -- "$file")
    extension="${filename##*.}"
    litFile="${filename%.*}"	
    printFile="${litFile#"MemGlueMSITemplate"}"
    echo "=== Running litmus test $file ====================================="
    if [[ "$extension" == "m" ]]; then
      export MEMGLUELITMUSTEST=$PATHTOMEMGLUEOUTPUTS/"$litFile"
      make clean
      make
      $MEMGLUELITMUSTEST -m4000 -tv -d . > "$PATHTOBASELITMUS/$litFile".tmp
      ALLRUN=$((ALLRUN+1))
      if grep -q "No error found." "$PATHTOBASELITMUS/$litFile".tmp; then
	echo "Litmus test $printFile: UNOBSERVABLE"
        echo "Litmus test $printFile: UNOBSERVABLE" >> "$PATHTOBASELITMUS"/$LOGNAME
	PASSED=$((PASSED+1))
      else
	if grep -q "Error: Litmus Test Failed"  "$PATHTOBASELITMUS/$litFile".tmp; then
          echo "Litmus test $printFile: OUTCOME OBSERVED"
          echo "Litmus test $printFile: OUTCOME OBSERVED" >> "$PATHTOBASELITMUS"/$LOGNAME
          echo "See log file at $PATHTOBASELITMUS/$LOGNAME for details"
          FAILED=$((FAILED+1))
	else
          echo "Litmus test $printFile: unexpected outcome"
          echo "Litmus test $printFile: unexpected outcome" >> "$PATHTOBASELITMUS"/$LOGNAME
	  echo "See log file at $PATHTOBASELITMUS/$LOGNAME for details"
	  INCONC=$((INCONC+1))
	fi
      fi
      rm "$PATHTOBASELITMUS/$litFile".tmp
    else
      "Error - $file is not a MemGlue file. Skipping..."
    fi
    printf "\n\n"
  done
  echo "RESULTS:"
  echo "UNOBSERVABLE: $PASSED/$ALLRUN"
  echo "OBSERVABLE: $FAILED/$ALLRUN"
  echo "INCONCLUSIVE: $INCONC/$ALLRUN"
  echo "ERRORED: $ERRORS/$ALLRUN"
  rm -r $PATHTOMEMGLUEOUTPUTS
else 
  if [ "$1" != "" ]; then
    export MEMGLUELITMUSTEST=$PATHTOMEMGLUEOUTPUTS/$MEMGLUETEMPLATE"$1"
    echo $MEMGLUELITMUSTEST
    mkdir -p $PATHTOMEMGLUEOUTPUTS
    python3 $TRANSLATELITMUSFILE $PATHTOLITMUSTESTS/"$1".litmus $PATHTOMEMGLUEOUTPUTS models/$MEMGLUETEMPLATE.m
    if [ $? -ne 0 ]; then
      exit 1
    fi
    make clean
    make >/dev/null
    $MEMGLUELITMUSTEST -m4000 -tv -d . > "$PATHTOBASELITMUS/$1".tmp
    if grep -q "No error found." "$PATHTOBASELITMUS/$1".tmp; then
      echo "Litmus test $1: UNOBSERVABLE"
      rm "$PATHTOBASELITMUS/$1".tmp
    else
      if grep -q "Error: Litmus Test Failed"  "$PATHTOBASELITMUS/$1".tmp; then
         echo "Litmus test $1: OUTCOME OBSERVED"
         echo "See log file at $PATHTOBASELITMUS/$1.tmp for details"
      else
	 echo "Litmus test $1: unexpected outcome"
	 echo "See log file at $PATHTOBASELITMUS/$1.tmp for details"
      fi
    fi
    rm -r $PATHTOMEMGLUEOUTPUTS
  else
    echo "Must provide litmus test name, or \"all\" to run all tests in logs"
  fi
fi
