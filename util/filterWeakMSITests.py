import sys
import os

# Categories for percentage of strong cores
# [0: 0, 1: 25, 2: 33, 3: 50, 4: 66, 5: 75, 6: 100]

msi_results = [(0,0), (0,0), (0,0), (0,0), (0,0), (0,0), (0,0)]
msi_categories = [([],[]),([],[]),([],[]),([],[]),([],[]),([],[]),([],[])]

def print_msi_results():
    global msi_results
    for i in range(7):
        o,u = msi_categories[i]
        print("i =", i)
        print(len(o), "/", len(o) + len(u))
        if len(u) != 0:
            print("(" + str(100 * len(o) / (len(o) + len(u))) + ")")
        else:
            if len(o) == 0:
                print("(0.0)")
            else:
                print("(100.0)")

class TestBreakdown:

    def __init__(self):
        self.OO = set()
        self.OU = set()
        self.UO = set()
        self.UU = set()

    def addTo(self,category,test):
        if category == "OO":
            self.OO.add(test)
        elif category == "OU":
            self.OU.add(test)
        elif category == "UO":
            self.UO.add(test)
        elif category == "UU":
            self.UU.add(test)
        else:
            print("Can't add to category", category)
            exit(1)

    def print_breakdown(self):
        print("  OO:", len(self.OO))
        print("  OU:", len(self.OU))
        print("  UO:", len(self.UO))
        print("  UU:", len(self.UU))
        if len(self.OO) + len(self.UO) != 0:
            print("  Percentage:", 100 * len(self.OO) / (len(self.OO) + len(self.UO)))

class TwoCore:
    def __init__(self):
        self.one_cluster = TestBreakdown()
        self.two_cluster = TestBreakdown()

    def add_to_msi_dict(self,num_cores_used,category,test):
        if num_cores_used == 1:
            self.one_cluster.addTo(category,test)
        elif num_cores_used == 2:
            self.two_cluster.addTo(category,test)
        else:
            print("Wrong number of cores provided")
            exit(1)
    
    def print_breakdown(self):
        print("Single cluster:")
        self.one_cluster.print_breakdown()
        print("Two clusters:")
        self.two_cluster.print_breakdown()

class ThreeCore:
    def __init__(self):
        self.one_cluster = TestBreakdown()
        self.two_cluster = TestBreakdown()
        self.three_cluster = TestBreakdown()

    def add_to_msi_dict(self,num_cores_used,category,test):
        if num_cores_used == 1:
            self.one_cluster.addTo(category,test)
        elif num_cores_used == 2:
            self.two_cluster.addTo(category,test)
        elif num_cores_used == 3:
            self.three_cluster.addTo(category,test)
        else:
            print("Wrong number of cores provided")
            exit(1)

    def print_breakdown(self):
        print("Single cluster:")
        self.one_cluster.print_breakdown()
        print("Two clusters:")
        self.two_cluster.print_breakdown()
        print("Three clusters:")
        self.three_cluster.print_breakdown()

class FourCore:
    def __init__(self):
        self.one_cluster = TestBreakdown()
        self.two_cluster = TestBreakdown()
        self.three_cluster = TestBreakdown()
        self.four_cluster = TestBreakdown()

    def add_to_msi_dict(self,num_cores_used,category,test):
        if num_cores_used == 1:
            self.one_cluster.addTo(category,test)
        elif num_cores_used == 2:
            self.two_cluster.addTo(category,test)
        elif num_cores_used == 3:
            self.three_cluster.addTo(category,test)
        elif num_cores_used == 4:
            self.four_cluster.addTo(category,test)
        else:
            print("Wrong number of cores provided")
            exit(1)

    def print_breakdown(self):
        print("Single cluster:")
        self.one_cluster.print_breakdown()
        print("Two clusters:")
        self.two_cluster.print_breakdown()
        print("Three clusters:")
        self.three_cluster.print_breakdown()
        print("Four clusters:")
        self.four_cluster.print_breakdown()


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
    global msi_results, msi_categories
    category = 0

    if "mp" in test or "sb" in test or "corr" in test:
        if strong_category == 0:
            category = 0
        elif strong_category == 1:
            category = 3
        elif strong_category == 2:
            category = 6
        else:
            print("Bad strong_category")
            exit(1)

    elif "wrc" in test:
        if strong_category == 0:
            category = 0
        elif strong_category == 1:
            category = 2
        elif strong_category == 2:
            category = 4
        elif strong_category == 3:
            category = 6
        else:
            print("Bad strong_category")
            exit(1)   

    elif "iriw" in test:
        if strong_category == 0:
            category = 0
        elif strong_category == 1:
            category = 1
        elif strong_category == 2:
            category = 3
        elif strong_category == 3:
            category = 5
        elif strong_category == 4:
            category = 6
        else:
            print("Bad strong_category")
            exit(1)

    else:
        print("Bad test")
        exit(1)

    if category == 0 and not obs:
        print(test)

    #a,b = msi_results[category]
    #b = b + 1 if not obs else b
    #a = a + 1 if obs else a

    #msi_results[category] = a,b 
    o,u = msi_categories[category]
    if obs:
        for t in u:
            if t == test:
                u.remove(t)
        o = o + [test]
    else:
        if not test in u:
            u = u + [test]
    msi_categories[category] = (o,u)


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


def compare(file1):
    old_test = file1.split("tests/MemGlueMSILitmusTests/MemGlueMSITemplate")[1].split(".m")[0]

    if "corr" in old_test:
        os.remove(file1)
        return
            
    test = rewriteTestName(old_test)
            
    strong_category = filter_test(test)

    if strong_category == None:
        os.remove(file1)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 filterWeakMSITests.py <test name>")
        exit()
    testname = sys.argv[1]
    compare(testname)
