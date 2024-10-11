# MemGlue Litmus Testing Instructions

## Software dependencies
- Linux distribution (tested on Ubuntu 20.04)
- Python 3.8 or higher
- CMurphi 5.4.9.1 -- available at https://github.com/Errare-humanum-est/CMurphi

To setup CMurphi, clone the directory into the parent directory. From 
CMurphi's parent directory, run:
```
cd src && make
```

## Repository structure
* **models**

  Murphi model templates of Ordered MemGlue, Unordered MemGlue, and Unordered
  MemGlue with MSI clusters to be used during litmus testing. Also contains
  the cat model for RC11 for reference.

* **tests**

  Litmus tests in .litmus format, translated to Murphi format during litmus
  testing.

* **util**

  Scripts for generating litmus tests in Murphi format, analyzing logs after
  testing to compare MemGlue to C11.


The remaining scripts in the home directory are responsible for running
litmus tests for each MemGlue model.

## Running tests

Each script will compile each test in the suite and then run it. The tests
with MSI clusters will additionally first translate each test (by producing
one test for each distribution of threads to clusters) and filter out the
tests that are not relevant. The outcomes will be added to the `logs` directory
and will be of the form:
```
Litmus test corr_R_acquire_seq_cst_W_relaxed_release: UNOBSERVABLE
```
Each outcome is either `OUTCOME OBSERVED` or `UNOBSERVABLE`. If 
`unexpected outcome` is printed, check that the test compiled properly.

`compareLogs.py` will categorize each test based on its observability in
MemGlue compared to C11. `compareMSILogs.py` will separate tests by base type
(MP, SB, WRC, IRIW) and will distribute them based on the percentage of their
threads that are "strong". 

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
