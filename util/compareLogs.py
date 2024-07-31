import sys
import os
import pandas

def printKeys(dictionary):
    for key in dictionary.keys():
        print("   ", key)

def compare(file1, file2):

    print(file1, file2)
    f1 = open(file1)
    f2 = open(file2)

    logResults = {}

    quadOO = {}
    quadOU = {}
    quadUO = {}
    quadUU = {}

    for line in f1.readlines():
        if "Litmus test " in line:
            test = line.split("Litmus test ")[1].split(": ")[0]
            result = line.split("Litmus test ")[1].split(": ")[1].replace("\n","")
            logResults.update({test:result})

    for line in f2.readlines():
        if "OBSERVABLE" in line:
            test = line.split()[0]
            result = line.split()[1].replace("\n","")
            memResult = logResults.get(test)
            if memResult != None:
                if "OUTCOME OBSERVED" == memResult and "OBSERVABLE" == result:
                    quadOO.update({test:result})
                if "OUTCOME OBSERVED" == memResult and "UNOBSERVABLE" == result:
                    quadOU.update({test:result})                
                if "UNOBSERVABLE" == memResult and "OBSERVABLE" == result:
                    quadUO.update({test:result})                
                if "UNOBSERVABLE" == memResult and "UNOBSERVABLE" == result:
                    quadUU.update({test:result})
            else:
                print("ERROR test not found")
    print("Tests observable in MemGlue and allowed in C11:")
    printKeys(quadOO)
    print("Tests observable in MemGlue but disallowed by C11:")
    printKeys(quadOU)
    print("Tests unobservable in MemGlue but allowed by C11:")
    printKeys(quadUO)
    print("Tests unobservable in MemGlue and disallowed by C11:")
    printKeys(quadUU)

    print("\nSummary:")
    data = {
        "Allowed in C11": [len(quadOO.keys()), len(quadUO.keys())],
        "Disallowed in C11": [len(quadOU.keys()), len(quadUU.keys())],
    }

    df = pandas.DataFrame(data,index=["Observable in MemGlue", "Unobservable in MemGlue"])
    print(df)

    f1.close()
    f2.close()

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 compareLogs.py <path to MemGlue log of all tests>")
        exit()
    current_directory = os.path.dirname(os.path.realpath(__file__))
    log1 = sys.argv[1]
    log2 = current_directory + "/C11-MCM-tests.log"
    compare(log1,log2)
