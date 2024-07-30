#!/bin/bash

export PATHTOMEMGLUEOUTPUTS=tests/MemGlueFenceLitmusFiles
PATHTOBASELITMUS=logs
TRANSLATELITMUSFILE=util/TranslateLitmus.py
MEMGLUETEMPLATE=UnorderedMemGlueTemplate
LOGNAME=all-unordered-fence.log

PASSED=0
FAILED=0
INCONC=0
ALLRUN=0
ERRORS=0

${PATHTOLITMUSTESTS=tests/MemGlueFenceLitmusTests}

if [ "$1" = "all" ]; then
  echo "Running all tests in $PATHTOLITMUSTESTS"
  mkdir -p $PATHTOMEMGLUEOUTPUTS
  rm "$PATHTOBASELITMUS"/$LOGNAME
  for file in $PATHTOLITMUSTESTS/*
  do
    filename=$(basename -- "$file")
    extension="${filename##*.}"
    litFile="${filename%.*}"	
    echo "=== Running litmus test $file ====================================="
    echo "=== Running litmus test $file =====================================" >> "$PATHTOBASELITMUS"/$LOGNAME
    if [[ "$extension" == "litmus" ]]; then
      echo "$litFile"
      export MEMGLUELITMUSTEST=$PATHTOMEMGLUEOUTPUTS/$MEMGLUETEMPLATE"$litFile"
      python3 $TRANSLATELITMUSFILE $file $PATHTOMEMGLUEOUTPUTS models/$MEMGLUETEMPLATE.m
      if [ $? -ne 0 ]; then
	echo "Litmus test $litFile: parsing failed"
	echo "Litmus test $litFile: parsing failed" >> "$PATHTOBASELITMUS"/$LOGNAME
	ALLRUN=$((ALLRUN+1))
	ERRORS=$((ERRORS+1))
	continue
      fi
      make clean
      make
      $MEMGLUELITMUSTEST -m4000 -tv -d . > "$PATHTOBASELITMUS/$litFile".tmp
      ALLRUN=$((ALLRUN+1))
      if grep -q "No error found." "$PATHTOBASELITMUS/$litFile".tmp; then
	echo "Litmus test $litFile: UNOBSERVABLE"
        echo "Litmus test $litFile: UNOBSERVABLE" >> "$PATHTOBASELITMUS"/$LOGNAME
	PASSED=$((PASSED+1))
      else
	if grep -q "Error: Litmus Test Failed"  "$PATHTOBASELITMUS/$litFile".tmp; then
          echo "Litmus test $litFile: OUTCOME OBSERVED"
          cat "$PATHTOBASELITMUS/$litFile".tmp >> "$PATHTOBASELITMUS"/$LOGNAME
          echo "Litmus test $litFile: OUTCOME OBSERVED" >> "$PATHTOBASELITMUS"/$LOGNAME
          echo "See log file at $PATHTOBASELITMUS/$LOGNAME for details"
          FAILED=$((FAILED+1))
	else
          echo "Litmus test $litFile: unexpected outcome"
      	  cat $PATHTOBASELITMUS/$litFile >> $PATHTOBASELITMUS/$LOGNAME
          echo "Litmus test $litFile: unexpected outcome" >> "$PATHTOBASELITMUS"/$LOGNAME
	  echo "See log file at $PATHTOBASELITMUS/$LOGNAME for details"
	  INCONC=$((INCONC+1))
	fi
      fi
      rm "$PATHTOBASELITMUS/$litFile".tmp
    else
      "Error - $file is not a litmus test. Skipping..."
    fi
    printf "\n\n"
    printf "\n\n" >> "$PATHTOBASELITMUS"/$LOGNAME
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
