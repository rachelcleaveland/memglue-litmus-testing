import sys
import os
import pandas

# Categories for percentage of strong cores
# [0: 0, 1: 25, 2: 33, 3: 50, 4: 66, 5: 75, 6: 100]

corr_categories = [([],[]),([],[]),([],[])]
mp_categories = [([],[]),([],[]),([],[])]
sb_categories = [([],[]),([],[]),([],[])]
wrc_categories = [([],[]),([],[]),([],[]),([],[])]
iriw_categories = [([],[]),([],[]),([],[]),([],[]),([],[])]

def print_msi_results(test):
    msi_categories = []
    total = 0

    if "mp" in test:
        msi_categories = mp_categories
        total = 2
    elif "sb" in test:
        msi_categories = sb_categories
        total = 2
    elif "corr" in test:
        msi_categories = corr_categories
        total = 2
    elif "wrc" in test:
        msi_categories = wrc_categories
        total = 3
    else:
        msi_categories = iriw_categories
        total = 4

    for i in range(len(msi_categories)):
        o,u = msi_categories[i]
        print(str(i/total * 100) + "% Strong Cores")
        print("  ", len(o), "/", len(o) + len(u), "allowable tests observable")
        if len(u) != 0:
            print("   (" + str(100 * len(o) / (len(o) + len(u))) + "%)")
        else:
            if len(o) == 0:
                print("   (0.0%)")
            else:
                print("   (100.0%)")

def printKeys(dictionary):
    for key in dictionary.keys():
        print("   ", key)

def count_distro(core_distro):
    if core_distro == "x_":
        return 0
    
    return len(core_distro.split("_")) - 1


def categorize_core_distro(test,core_distro):
    c1 = count_distro(test.split("C1_")[1].split("C2")[0])
    if "mp" in test or "sb" in test or "corr" in test:
        c2 = count_distro(test.split("C2_")[1] + "_")
        l = [c1,c2]
        l.sort()
    elif "wrc" in test:
        c2 = count_distro(test.split("C2_")[1].split("C3")[0])
        c3 = count_distro(test.split("C3_")[1] + "_")
        l = [c1,c2,c3]
        l.sort()
    else:
        c2 = count_distro(test.split("C2_")[1].split("C3")[0])
        c3 = count_distro(test.split("C3_")[1].split("C4")[0])
        c4 = count_distro(test.split("C4_")[1] + "_")
        l = [c1,c2,c3,c4]
        l.sort()

    l = filter(lambda x: x != 0,l)

    return len(list(l))


def add_to_msi_dict(d,num_cores_used,category):
    subdict = d.get(num_cores_used)
    num_tests = subdict.get(category)
    if num_tests != None:
        d.update({category,num_tests+1})
    else:
        subdict[category] = 1
    d.update({num_cores_used,subdict})    

# Returns true if the test should be removed
# Returns true for tests where the same-cluster cores
# have instructions that are not SC
def filter_test(test):
    # Test format: wrc_R_seq_cst_seq_cst_relaxed_W_seq_cst_seq_cst__C1_4_C2_2_C3_3
    test = test.replace("seq_cst","seq-cst")

    C1 = test.split("C1_")[1].split("_C2")[0].split("_")
    C1 = [] if len(C1) == 1 else C1

    reads = test.split("_R_")[1].split("_W_")[0].split("_")
    writes = test.split("_W_")[1].split("__")[0].split("_")

    # Filter out tests where non-SC instructions appear on
    # cores that are in a multi-core cluster
    # Return None for tests we want to filter out, otherwise
    # return the number of cores that are "strong"
    if "sb" in test or "mp" in test or "corr" in test:
        C2 = test.split("C2_")[1].split("_")
        C2 = [] if len(C2) == 1 else C2

        if len(C1) == 2 or len(C2) == 2:
            for read in reads:
                if read != "seq-cst":
                    return None
            for write in writes:
                if write != "seq-cst":
                    return None
            return 1

        else:
            res = 0
            # each cluster has one core
            if "sb" in test:
                if writes[0] == "seq-cst" and reads[0] == "seq-cst":
                    res = res + 1
                if writes[1] == "seq-cst" and reads[1] == "seq-cst":
                    res = res + 1
                return res

            elif "mp" in test or "corr" in test:
                if writes[0] == "seq-cst" and writes[1] == "seq-cst":
                    res = res + 1
                if reads[0] == "seq-cst" and reads[1] == "seq-cst":
                    res = res + 1
                return res    

    elif "wrc" in test:
        C2 = test.split("C2_")[1].split("_C3")[0].split("_")
        C2 = [] if len(C2) == 1 else C2
        C3 = test.split("C3_")[1].split("_")
        C3 = [] if len(C3) == 1 else C3

        seq_cores = C1 + C2 + C3

        for core in seq_cores:
            if core == "2":
                if writes[0] != "seq-cst":
                    return None
            elif core == "3":
                if reads[0] != "seq-cst" or reads[1] != "seq-cst":
                    return None
            elif core == "4":
                if writes[1] != "seq-cst" or reads[2] != "seq-cst":
                    return None
            else:
                print("Bad core")
                exit(1)
            
        res = 0

        if writes[0] == "seq-cst":
            res = res + 1
        if reads[0] == "seq-cst" and reads[1] == "seq-cst":
            res = res + 1
        if reads[2] == "seq-cst" and writes[1] == "seq-cst":
            res = res + 1

        return res

    elif "iriw" in test:
        C2 = test.split("C2_")[1].split("_C3")[0].split("_")
        C2 = [] if len(C2) == 1 else C2
        C3 = test.split("C3_")[1].split("_C4")[0].split("_")
        C3 = [] if len(C3) == 1 else C3
        C4 = test.split("C4_")[1].split("_")
        C4 = [] if len(C4) == 1 else C4

        seq_cores = C1 + C2 + C3 + C4

        for core in seq_cores:
            if core == "2":
                if writes[0] != "seq-cst":
                    return None
            elif core == "3":
                if writes[1] != "seq-cst":
                    return None
            elif core == "4":
                if reads[0] != "seq-cst" or reads[1] != "seq-cst":
                    return None
            elif core == "5":
                if reads[2] != "seq-cst" or reads[3] != "seq-cst":
                    return None                    
            else:
                print("Bad core")
                exit(1)
        
        res = 0

        if writes[0] == "seq-cst":
            res = res + 1
        if writes[1] == "seq-cst":
            res = res + 1
        if reads[0] == "seq-cst" and reads[1] == "seq-cst":
            res = res + 1
        if reads[2] == "seq-cst" and reads[3] == "seq-cst":
            res = res + 1

        return res

    else:
        print("Bad litmus test")
        exit(1)


def insert_to_msi_results(test,obs,strong_category):
    global corr_categories, mp_categories
    global sb_categories, wrc_categories, iriw_categories

    test_category = []
    if "mp" in test:
        test_category = mp_categories

    elif "sb" in test:
        test_category = sb_categories

    elif "corr" in test:
        test_category = corr_categories

    elif "wrc" in test:
        test_category = wrc_categories

    elif "iriw" in test:
        test_category = iriw_categories

    else:
        print("Bad test")
        exit(1)

    o,u = test_category[strong_category]
    if obs:
        for t in u:
            if t == test:
                u.remove(t)
        o = o + [test]
    else:
        if not test in u:
            u = u + [test]
    if "mp" in test:
        mp_categories[strong_category] = (o,u)
    elif "sb" in test:
        sb_categories[strong_category] = (o,u)
    elif "corr" in test:
        corr_categories[strong_category] = (o,u)
    elif "wrc" in test:
        wrc_categories[strong_category] = (o,u)
    else:
        iriw_categories[strong_category] = (o,u)


def coreListToString(cores):
    string = ""
    for c in cores:
        string = string + c + "_"
    return string[:-1]


# Rewrite the name of the test so that the cores in each cluster are sorted
# This makes comparing tests beteen different runs possible
def rewriteTestName(test):
    base_test = test.split("__")[0]
    if "mp" in test or "sb" in test or "corr" in test:
        C1 = test.split("C1_")[1].split("_C2")[0].split("_")
        C2 = test.split("C2_")[1].split("_")
        C1.sort()
        C2.sort()
        if len(C1) == 1 and len(C2) == 1 and C1[0] == "3":
            Ctmp = C2
            C2 = C1
            C1 = Ctmp
        return base_test + "__C1_" + coreListToString(C1) + "_C2_" + coreListToString(C2)

    if "wrc" in test:
        C1 = test.split("C1_")[1].split("_C2")[0].split("_")
        C2 = test.split("C2_")[1].split("_C3")[0].split("_")
        C3 = test.split("C3_")[1].split("_")
        C1.sort()
        C2.sort()
        C3.sort()
        if len(C1) == 1 and len(C2) == 1 and len(C3) == 1:
            C1 = ['2']
            C2 = ['3']
            C3 = ['4']

        return base_test + "__C1_" + coreListToString(C1) + "_C2_" + coreListToString(C2) \
            + "_C3_" + coreListToString(C3)
    if "iriw" in test:
        C1 = test.split("C1_")[1].split("_C2")[0].split("_")
        C2 = test.split("C2_")[1].split("_C3")[0].split("_")
        C3 = test.split("C3_")[1].split("_C4")[0].split("_")
        C4 = test.split("C4_")[1].split("_")
        C1.sort()
        C2.sort()
        C3.sort()
        C4.sort()

        if len(C1) == 2 and len(C2) == 2:
            if C1[0] != "2":
                Ctmp = C1
                C1 = C2
                C2 = Ctmp

        if len(C2) == 2 and len(C3) == 1 and len(C4) == 1 and C3[0] != "x":
            if int(C3[0]) > int(C4[0]):
                Ctmp = C3
                C3 = C4
                C4 = Ctmp

        if len(C1) == 1 and len(C2) == 1 and len(C3) == 1 and len(C4) == 1:
            C1 = ['2']
            C2 = ['3']
            C3 = ['4']
            C4 = ['5']


        return base_test + "__C1_" + coreListToString(C1) + "_C2_" + coreListToString(C2) \
            + "_C3_" + coreListToString(C3) + "_C4_" + coreListToString(C4)


def compare(file1, file2, testType):

    print(file1, file2)
    f1 = open(file1)
    f2 = open(file2)

    herdResults = {}

    quadOO = {}
    quadOU = {}
    quadUO = {}
    quadUU = {}

    def single_test_filter(test_name):
        if testType == None:
            return True 
        else:
            return (testType in test_name)

    for line in f2.readlines():
        if "OBSERVABLE" in line:
            test = line.split()[0]
            result = line.split()[1].replace("\n","")
            herdResults.update({test:result})

    for line in f1.readlines():
        if "Litmus test " in line:
            old_test = line.split("Litmus test ")[1].split(": ")[0]
            
            herdTest = old_test
            if "__" in old_test:
                herdTest = old_test.split("__")[0]

            herdResult = herdResults.get(herdTest)

            test = rewriteTestName(old_test)
            memResult = line.split("Litmus test ")[1].split(": ")[1].replace("\n","")
            
            core_distro = test.split("__")[1]

            strong_category = filter_test(test)

            if strong_category == None:
                continue

            num_cores_used = categorize_core_distro(test,core_distro)

            if herdResult != None:
                if "OUTCOME OBSERVED" == memResult and "OBSERVABLE" == herdResult:
                    quadOO.update({test:result})
                    if not "corr" in test and single_test_filter(test): 
                        insert_to_msi_results(test,True,strong_category)

                if "OUTCOME OBSERVED" == memResult and "UNOBSERVABLE" == herdResult:
                    quadOU.update({test:result})    
                    if not "corr" in test and single_test_filter(test):
                        insert_to_msi_results(test,True,strong_category)

                if "UNOBSERVABLE" == memResult and "OBSERVABLE" == herdResult:
                    quadUO.update({test:result})       
                    if not "corr" in test and single_test_filter(test):
                        insert_to_msi_results(test,False,strong_category)

                if "UNOBSERVABLE" == memResult and "UNOBSERVABLE" == herdResult:
                    quadUU.update({test:result})
                    if not "corr" in test and single_test_filter(test):
                        insert_to_msi_results(test,False,strong_category)

            else:
                print("ERROR test not found")

    print("\nSummary:")
    data = {
        "Allowed in C11": [len(quadOO.keys()), len(quadUO.keys())],
        "Disallowed in C11": [len(quadOU.keys()), len(quadUU.keys())],
    }

    df = pandas.DataFrame(data,index=["Observable in MemGlue", "Unobservable in MemGlue"])
    print(df)

    if testType == None or "mp" in testType:
        print("\nMP Results:")
        print_msi_results("mp")

    if testType == None or "sb" in testType:
        print("\nSB Results:")
        print_msi_results("sb")
        
    if testType == None or "wrc" in testType:
        print("\nWRC Results:")
        print_msi_results("wrc")

    if testType == None or "iriw" in testType:
        print("\nIRIW Results:")
        print_msi_results("iriw")

    f1.close()
    f2.close()

if __name__ == '__main__':
    if len(sys.argv) != 2 and len(sys.argv) != 3:
        print("Usage: python3 filterWeakMSILogs.py <path to weak MemGlue log> <optional test type filter e.g. mp>")
        exit()
    log1 = sys.argv[1]
    current_directory = os.path.dirname(os.path.realpath(__file__))
    herdLog = current_directory + "/C11-MCM-tests.log"
    testType = None if len(sys.argv) != 3 else sys.argv[2]
    compare(log1,herdLog,testType)
