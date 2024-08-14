# MemGlue Litmus Testing Instructions

## Software dependencies
- Linux distribution (tested on Ubuntu 20.04)
- Python 3.8 or higher
- CMurphi 5.4.9.1 -- available at https://github.com/Errare-humanum-est/CMurphi-

To setup CMurphi, clone the directory into the parent directory. From 
CMurphi's parent directory, run:
```
cd src && make
```

## Repository structure
* **models**

  Murphi model templates of Ordered MemGlue, Unordered MemGlue, and Unordered
  MemGlue with MSI clusters to be used during litmus testing. Also contains
  the RC11 cat model used in this work.

* **tests**

  Litmus tests in .litmus format, translated to Murphi format during litmus
  testing.

* **util**

  Scripts for generating litmus tests in Murphi format, analyzing logs after
  testing to compare MemGlue to C11.


The remaining scripts in the home directory are responsible for running
litmus tests for each MemGlue model.

## Running tests

### Running MemGlueO tests

Litmus tests with no fences
```
./runOrderedLitmusTest.sh all
python3 util/compareLogs.py logs/all-ordered.log
```

Litmus tests with fences
```
./runOrderedFenceTest.sh all
python3 util/compareLogs.py logs/all-ordered-fence.log
```

### Running MemGlueU tests

Litmus tests with no fences
```
./runUnorderedLitmusTest.sh all
python3 util/compareLogs.py logs/all-unordered.log
```

Litmus tests with fences
```
./runUnorderedFenceTest.sh all
python3 util/compareLogs.py logs/all-unordered-fence.log
```

### Runing MemGlueU with MSI clusters
```
./runMSITest.sh all
python3 util/compareMSILogs.py logs/all-msi.log <optional test type: mp, sb, wrc, iriw>
```
