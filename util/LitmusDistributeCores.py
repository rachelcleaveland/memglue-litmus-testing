import sys
import re
import fileinput

litmusName = ''
numCores = 0
numAddrs = 0
vars = {}
cores = set()
instrs = {}
loads = {}          # maps load ids to location in instrs list
#rfInitial = {}      # maps cores to loads that read from initial memory (0)
numInitLoads = 0
initLoads = {}


def buildFuncName(cl,core):
    return "Cl" + cl + "Core" + core + "Instr" + litmusName + "();"


def writeToFile(oPath,fName,litmusProcedure):
    oFileName = oPath + "/" + fName[0:len(fName)-2] + litmusName + ".m" if ".m" in fName else oPath + "/" + fName + litmusName + ".m"  
    oFile = open(oFileName, "w")
    iFile = open(fName, "r")

    for line in iFile.readlines():
        if "ShimCount: _;" in line:
            oFile.write("  ShimCount: " + str(len(cores)) + ";      -- number of clusters / shims\n")
        elif "/* Litmus test */" in line:
            oFile.write(litmusProcedure)
        elif "/* InitLitmusTests(); */" in line:
            for key in instrs.keys():
                oFile.write("    Shim" + str(key+1) + "Instr" + litmusName + "();\n")
        #elif "/* WriteInitialData(); */" in line:

        elif "/* Forbidden function */" in line:
            oFile.write("        Forbidden" + litmusName + "();\n")
        else:
            oFile.write(line)


def writeLitmusToFile(oPath,fName,litmusTests):
    global litmusName
    for testName in litmusTests:
        oFileName = oPath + "/" + fName[7:len(fName)-2] + testName + ".m" if ".m" in fName else oPath + "/" + fName[7:] + testName + ".m"  
        oFile = open(oFileName, "w+")
        iFile = open(fName,"r")

        litmusProcedure, forbidden, funcNames, initData = litmusTests[testName]

        for line in iFile.readlines():
            if "ShimCount: _;" in line:
                oFile.write("  ShimCount: " + str(len(cores)) + ";      -- number of clusters / shims\n")
            elif "/* Litmus test */" in line:
                oFile.write(litmusProcedure)
                oFile.write(forbidden)
            elif "/* InitLitmusTests(); */" in line: #############333
                for funcName in funcNames:
                    oFile.write("    " + funcName + "\n")
            elif "/* WriteInitialData(); */" in line:
                oFile.write(initData)
            elif "/* Forbidden function */" in line:
                oFile.write("        Forbidden" + testName + "();\n")
            else:
                oFile.write(line)

    #for test in litmusTests:
    #    oFile.write(test)
    #    oFile.write(litmusTests[test])


def strenFromOrder(order):
    if order == "seq_cst":
        return "SC"
    elif order == "acquire":
        return "ACQ"
    elif order == "release":
        return "REL"
    elif order == "relaxed":
        return "RLX"
    else:
        print("Invalid instruction order:" + order)
        sys.exit(1)


def buildInstrFunc(cl,core):
    instrCore = str(int(core)+2)
    instrCl = str(int(cl)+1)
    fName = "  Procedure " + buildFuncName(instrCl,instrCore)
    coreInstrs = instrs.get(int(core),[])
    instrVars = "  "
    instrInstrs = ""
    for i in range(len(coreInstrs)):
        instrVars = instrVars + "var I" + str(i+1) + ": Instr; "
        instrInstrs = instrInstrs + "    I" + str(i+1) + ".access := " + coreInstrs[i][0] + ";\n"
        instrInstrs = instrInstrs + "    I" + str(i+1) + ".stren := " + strenFromOrder(coreInstrs[i][3]) + ";\n"
        instrInstrs = instrInstrs + "    I" + str(i+1) + ".addr := " + str(vars.get(coreInstrs[i][2])) + ";\n"
        if coreInstrs[i][0] == "load":
            instrInstrs = instrInstrs + "    I" + str(i+1) + ".data := undefined;\n"
        else:
            instrInstrs = instrInstrs + "    I" + str(i+1) + ".data := " + coreInstrs[i][1] + ";\n"
        instrInstrs = instrInstrs + "    AddInstr(" + instrCl + "," + instrCore + ",I" + str(i+1) + ");\n\n"
        
    instrFunc = fName + "\n" + instrVars + "\n  Begin\n" + instrInstrs + "  End;\n\n"

    return instrFunc

def buildInitialData(cl,core):
    global initLoads, numAddrs
    initData = ''

    instrCore = str(int(core)+2)
    instrCl = str(int(cl)+1)
    for addr_str in range(numAddrs):
        addr = str(addr_str)
        initData = initData + "    i_caches[" + instrCl + "][" + instrCore + "].CL[" + addr + "].cl := 0;\n"
        initData = initData + "    i_caches[" + instrCl + "][" + instrCore + "].CL[" + addr + "].State := cache_S;\n"
        initData = initData + "    i_directories[" + instrCl + "].CL[" + addr + "].State := directory_S;\n"
        initData = initData + "    i_directories[" + instrCl + "].CL[" + addr + "].cl := 0;\n"
        initData = initData + "    i_directories[" + instrCl + "].CL[" + addr + "].cache[" + instrCore + "] := Y;\n"
        initData = initData + "    CC.cache[" + addr + "].sharers[" + instrCl + "] := Y;\n"
        initData = initData + "    Shims[" + instrCl + "].state[" + addr + "].state := Valid;\n"
        initData = initData + "    Shims[" + instrCl + "].state[" + addr + "].data := 0;\n"
        initData = initData + "    Shims[" + instrCl + "].state[" + addr + "].ts := 0;\n"
        initData = initData + "    Shims[" + instrCl + "].state[" + addr + "].syncBit := false;\n"

    return initData

def buildInstrForbidden(d, litmusNameSpecific):
    #global numInitLoads
    forbFunc = "  Procedure Forbidden" + litmusNameSpecific + "();\n  var matches: 0.." \
        + str(len(loads.keys()) + numInitLoads) + ";\n  Begin\n    matches := 0;\n"
    for core in instrs.keys():
        cl = None
        for k in d:
            if str(core) in d[k]:
                cl = str(k+1)
        instrList = instrs.get(core)
        for i in range(len(instrList)):
            if instrList[i][0] == "load":
                forbFunc = forbFunc + "    if i_caches["+cl+"]["+str(core+2)+"].queue.Queue[" + str(i) \
                           + "].data = " + instrList[i][1] + " then\n      matches := matches + 1;\n    endif;\n"
    numMatches = len(loads.keys()) # + numInitLoads
    forbFunc = forbFunc + "\n    if matches = " + str(numMatches) + " then\n" \
                + "      error \"Litmus Test Failed\";\n    endif;\n  End;\n\n"

    return forbFunc


def addInstr(instr,core):
    if instrs.get(core) != None:
        prevInstrs = instrs.get(core)
        instrs.update({core:prevInstrs+[instr]})
    else:
        instrs.update({core:[instr]})

def dictLen(core):
    if instrs.get(core) == None:
        return 0
    else:
        return len(instrs.get(core))


def parseFuncBody(line, core):
    if re.search(r'int [a-z,A-Z]+[0-9]*[\s]*=[\s]*atomic_load_explicit\([a-z,A-Z]+[0-9]*,[\s]*memory_order_[_,a-z]+\);',line) != None:
        var = line.split("load_explicit(")[1].split(",")[0]
        if not var in vars.keys():
            print("Parsed unknown variable in", line)
            return
        atomic = line.split("memory_order_")[1].split(");")[0]
        loadId = line.split("int ")[1].split(" ")[0]
        loads.update({loadId:dictLen(core)}) # maps loadId to location in instrs list
        addInstr(("load",loadId,var,atomic),core)
        return
    elif re.search(r'atomic_store_explicit\([a-z,A-Z]+[0-9]*,[\s]*[0-9]+,[\s]*memory_order_[_,a-z]+\);',line) != None:
        var = line.split("store_explicit(")[1].split(",")[0]
        if not var in vars.keys():
            print("Parsed unknown variable in", line)
            sys.exit(1)
        atomic = line.split("memory_order_")[1].split(");")[0]
        value = line.split(",")[1].strip()
        addInstr(("store",value,var,atomic),core)
        return
    elif line == "\n":
        return
    else:
        print("Malformed function body in", line)
        sys.exit(1)

def parseVars(line):
    global vars
    lefts = line.split("[")
    for ele in lefts[1:]:
        var = ele.split("]")
        if var[0] == ele:
            continue
        vars.update({var[0]:len(vars.keys())})

def parseCond(line):
    global instrs
    #global numInitLoads
    global initLoads
    body = line.split("(")[1].split(")")[0]
    conds = body.split("/\\")
    rfInitial = {}
    for cond in conds:
        core = cond.split(":")[0].strip()
        if not core in cores:
            print("Unknown core at", line)
            sys.exit(1)
        loadId = cond.split(":")[1].split("=")[0].strip()
        if not loadId in loads.keys():
            print("Unknown load id at", line)
            sys.exit(1)
        instrIdx = loads.get(loadId)
        coreInstrs = instrs.get(int(core))
        value = cond.split("=")[1].strip()
        oldInstr = coreInstrs[instrIdx]
        newInstr = (oldInstr[0],value,oldInstr[2],oldInstr[3])
        coreInstrs = coreInstrs[0:instrIdx]+[newInstr] if len(coreInstrs) == instrIdx + 1 else coreInstrs[0:instrIdx]+[newInstr]+coreInstrs[instrIdx+1:]
        if value == '0':
            initLoads.update({int(core):(initLoads.get(int(core),[])+[(oldInstr[2])])})
            #newInitInstr = (oldInstr[0],value,oldInstr[2],"seq_cst")
            #rfInitial.update({int(core):rfInitial.get(int(core),[])+[newInitInstr]})
            #numInitLoads = numInitLoads + 1
        instrs.update({int(core):coreInstrs})

    #for core in cores:
    #    initialLoads = rfInitial.get(int(core),[])
    #    instrs.update({int(core):initialLoads+instrs.get(int(core),[])})

def parse(litmusFile):
    global numCores, litmusName, numAddrs

    litFile = open(litmusFile)
    litTest = litFile.read()

    lBreak = r'[\s,\n]+'
    ltName = r'C [ -~]*' #[\s,\n]+
    ltInit = r'\{[\n,\s]*([\s]*\[[\s]*[a-z,A-Z,0-9]*[\s]*\][\s]*=[\s]*0[\s]*;[\s,\n]*)+[\s]*[\n,\s]*\}'
    funOpn = r'P[0-9]+ \(atomic_int\* [a-z,A-Z,0-9]+(,[\s]*atomic_int\* [a-z,A-Z,0-9]+)*\)[\s]*\{'
    ltFunc = r'((' + funOpn + lBreak + r'.*\}[\n]+)+)'
    ltCond = r'exists[\n,\s]*\([0-9]+:[a-z,A-Z,0-9]+[\s]*=[\s]*[0-9]+[\s]*(/\\[\s]*[0-9]+:[a-z,A-Z,0-9]+[\s]*=[\s]*[0-9]+[\s]*)*\)'
    ltComm = r'(//[\s]*[ -~]*)*' #\s,a-z,A-Z,0-9,\+]*)'

    x = re.search(ltName+lBreak+ltInit+lBreak+ltComm+lBreak+ltFunc+lBreak+ltCond, litTest, re.DOTALL)

    if x == None:
        print("Malformed litmus test: does not parse")
        print(re.search(ltName+lBreak+ltInit+lBreak+ltComm+lBreak+ltFunc+lBreak+ltCond, litTest, re.DOTALL))
        if re.search(ltName,litTest,re.DOTALL) == None:
            print("Error in ltName")
        if re.search(ltInit,litTest,re.DOTALL) == None:
            print("Error in ltInit")
        if re.search(funOpn,litTest,re.DOTALL) == None:
            print("Error in funOpn")
        if re.search(ltFunc,litTest,re.DOTALL) == None:
            print("Error in ltFunc")
        if re.search(ltCond,litTest,re.DOTALL) == None:
            print("Error in ltCond")
        if re.search(r'\{([\s]*\[[\s]*[a-z,A-Z,0-9]*[\s]*\][\s]*=[\s]*0[\s]*;[\s]*)+[\s]*\}', litTest) == None:
            print("Initial values must be 0")
        sys.exit(1)

    litFile.seek(0)
    inFunc = -1
    openParen = False
    expectExists = False
    for line in litFile.readlines():
        if inFunc >= 0:
            if re.search(r'\}', line) != None:
                inFunc = -1
                continue
            parseFuncBody(line, inFunc)

        if re.search(ltName, line) != None:
            #litmusName = line.split("C ")[1].split("\n")[0]
            continue

        if re.search(ltInit, line) != None:
            parseVars(line)
            numAddrs = len(vars.keys())
            if numAddrs > 2:
                print("Error: cannot handle more than 2 addresses")
                sys.exit(1)
            continue

        if re.search(funOpn, line) != None:
            core = line.split("P")[1].split()[0]
            cores.add(core)
            numCores = numCores + 1
            inFunc = int(core)
            continue

        if re.search(ltCond, line) != None:
            parseCond(line)
            continue

        if re.search(r'\{[\s,\n]+', line) != None:
            openParen = True

        if openParen and re.search(r'([\s]*\[[\s]*[a-z,A-Z,0-9]*[\s]*\][\s]*=[\s]*0[\s]*;[\s]*)+', line) != None:
            parseVars(line)
            numAddrs = len(vars.keys())

        if openParen and re.search(r'\}[\s,\n]+',line) != None:
            openParen = False

        if re.search(r'exists', line) != None:
            expectExists = True

        if expectExists and re.search(r'\([0-9]+:[a-z,A-Z,0-9]+[\s]*=[\s]*[0-9]+[\s]*(/\\[\s]*[0-9]+:[a-z,A-Z,0-9]+[\s]*=[\s]*[0-9]+[\s]*)*\)',line) != None:
            expectExists = False
            parseCond(line)

    #finalProcedure = "-- Litmus Test: " + litmusName + " -------------\n"


    litFile.close()
    #for key in instrs.keys():
    #    finalProcedure = finalProcedure + buildInstrFunc(str(key))

    #finalProcedure = finalProcedure + buildInstrForbidden()

    #litFile.close()

    #return finalProcedure


# Returns a list of dictionaries, where each dictionary maps a number of 
# cores to the number of clusters with that many cores. Represents all 
# ways to distribute numInstrs cores across numCls clusters.
def distributeInstrs2(numCls, numInstrs, start):
    # If there is only one cluster, we put all cores on it
    # If there are n clusters, we can:
    #   Put one core on the first, n-1 cores on the rest
    #   Put two cores on the first, n-2 cores on the rest
    #   etc
    #
    # If function specifically creates a list of dictionaries, where each
    # dictionary can be thought of as a multiset. The multiset gives the 
    # number of cores per cluster. 
    if numCls == 1:
        return [{numInstrs : 1}]
    elif numInstrs == 0:
        return [{}]
    else:
        res = []
        for i in range(1,numInstrs+1):
            rest = distributeInstrs2(numCls-1,numInstrs-i,start+1)
            for dist in rest:
                dist[i] = 1 if i not in dist else dist[i] + 1
            res = res + rest

        return res


# Returns a list of sets of core ids, all possible sets of n
# cores out of the set coreIds.
def possibilities(n, coreIds, indent):

    if n == 0:
        return [set()] 

    if n == len(coreIds):
        return [coreIds]

    res = []

    # Pick some core out of coreIds and either add it to the
    # set, or don't. Add both resulting list of sets to 
    # the final output. 
    for core in coreIds:
        break
    
    copyCores = coreIds.copy()
    copyCores.remove(core)

    withCore = possibilities(n-1,copyCores, indent + "  ")
    withoutCore = possibilities(n,copyCores, indent + "  ")

    for group in withCore:
        group.add(core)
        res.append(group) 

    for group in withoutCore:
        res.append(group) 

    return res

# Returns all possible ways of partitioning the core ids in rest
# among v clusters (d cores per cluster)
# Recursively adds clusters from rest into first until first is full
# (contains d cores).  
# Returns a list of lists of sets. Each list of sets has length equal
# to the number of clusters that we're distributing cores to. Each list
# of sets represents one unique way of distributing d*v cores across
# v clusters. 
def distSameNum(first, rest, d, v, indent):
    if len(first) == d:
        # Final phase: all v clusters filled with d cores. Just return the 
        # final cluster, which is the variable first.
        if v == 0:
            return [[first]]
        # Phase 2: first has filled up, but we still have more clusters
        # to distribute cores to. Recursively call distSameNum with v-1.
        # This will return a list of lists of sets of core ids.
        # Iterate through the list of lists of sets to add first (a set)
        # to each one.
        else:
            for se in rest:
                break
            restCopy = rest.copy()
            restCopy.remove(se)
            res = distSameNum({se},restCopy,d,v-1,indent + "  ")
            finalRes = []
            for r in res:
                finalRes.append(r + [first])

            return finalRes

    # Phase 1: adding cores to first until it fills up
    fullRes = []
    for s in rest:
        restCopy = rest.copy()
        restCopy.remove(s)
        firstCopy = first.copy()
        firstCopy.add(s)
        res = distSameNum(firstCopy,restCopy,d,v,indent + "  ")
        fullRes = fullRes + res
    return fullRes


# Creates list of dictionaries that map cluster id to the set of core ids
# that are in that cluster. Each dictionary represents a unique distribution
# of cores to clusters
# coreIds: set of core ids that have not yet been mapped to a cluster
# distr: a single distribution in the form of a dictionary mapping a 
# number of core ids to the number of clusters that have that many cores
# cl: current cluster id that we are distributing cores to
def distributeInstructions(coreIds, distr, cl, indent):
    if distr == {}:
        return [{}]

    for d in distr: # Grab some entry in the dictionary
        break

    v = distr[d]    # v is the number of clusters that have d cores
    del distr[d]

    # Isomorphism removal: the second source of isormorphic distributions 
    # is from multiple clusters having the same number of cores. Then we 
    # could have both {cl A: {core 0}; cl B: {core 1}} as well as 
    # {cl A: {core 1}; cl B: {core 0}}. We remove these isomorphisms by
    # getting the possible sets of d*v coreIds, and then distribute 
    # them among the v cores without duplication. 
    poss = possibilities(d * v, coreIds, indent)
    currMap = poss
    res = []

    for p in poss:
        curMap = [[p]]
        # If there is more than one cluster with d cores, we insert into 
        # curMap all the possible ways to distribute the d*v cores in p
        # among the d cores
        if v > 1:
            for first in p:
                break
            pCopy = p.copy()
            pCopy.remove(first)
            curMap = distSameNum({first}, pCopy, d, v-1, indent + "  ")       

        # Returns list of dictionaries of cluster to core mappings
        distrCopy = distr.copy()
        copyCore = coreIds.copy()
        distrs = distributeInstructions(copyCore-p, distrCopy, cl+v, indent + "  ")
        for di in distrs:
            for i in range(len(curMap)):
                diCopy = di.copy()
                for j in range(v):
                    diCopy[cl+j] = curMap[i][j]
                res.append(diCopy)

    return res


# Remove duplicated distributions. d is a list of dictionaries, where each
# dictionary maps the cluster id to the core ids in that cluster
def removeIso(d):
    res = []

    for i in range(len(d)):
        if d[i] == None:
            continue
        for j in range(i+1,len(d)):
            if d[i] == d[j]:
                d[j] = None
        res.append(d[i])

    return res


# Creates unique litmus test name based on distribution of cores to clusters
def createSuffix(d):
    global cores
    global litmusName
    global instrs

    suffix = ""
    for i in range(len(cores)): # Iterate through all possible cluster ids (same number as cores)
        if i in d:
            suffix = suffix + "_C" + str(i+1)
            if len(d[i]) == 0:
                suffix = suffix + "_x"
            else:
                for j in d[i]:
                    suffix = suffix + "_" + str(int(j)+2)
        else:
            suffix = suffix + "_C" + str(i+1) + "_x"
    return suffix


# Creates a separate litmus test for each possible distribution of cores across clusters
def distributeInstrs():
    global instrs
    global cores
    global initLoads

    distrs = []

    # Step 1: create list of dictionaries, each dictionary mapping a number of cores to
    # number of clusters that have that many cores. Remove isomorphic distributions
    dists = removeIso(distributeInstrs2(len(cores),len(cores),0))

    totalCores = cores.copy()

    # Step 2: create list of dictionaries that map a cluster id to the set of 
    # core ids within that cluster
    for distr in dists:
        res = distributeInstructions(totalCores, distr, 0, "")
        distrs = distrs + res



    litmusTests = {}

    # Step 3: create a litmus test for each unique distribution
    for d in distrs:
        suffix = createSuffix(d)
        litmusNameSpecific = litmusName + "_" + suffix
        test = "-- Litmus Test: " + litmusNameSpecific + " -------------\n"
        funcNames = []
        initData = ""
        for cl in d:
            for i in d[cl]:
                test = test + buildInstrFunc(cl,i)
                if int(i) in initLoads.keys():
                    initData = initData + buildInitialData(cl,i)
                funcNames.append(buildFuncName(str(int(cl)+1),str(int(i)+2)))

        #litmusTests.append(test)
        forbidden = buildInstrForbidden(d,litmusNameSpecific)
        litmusTests[litmusNameSpecific] = (test,forbidden,funcNames,initData)
                

    #print(litmusTests)

    #for key in instrs.keys():
    #    finalProcedure = finalProcedure + buildInstrFunc(str(key))
    #finalProcedure = finalProcedure + buildInstrForbidden()

    #print(finalProcedure)

    return litmusTests

if __name__ == '__main__':
    #global litmusName
    if (len(sys.argv) != 4):
        print("Usage: python3 TranslateLitmus.py <litmus test file> <Path to desired output directory> <Memglue Template file>")
        sys.exit(1)

    litmusName = (sys.argv[1].split(".litmus")[0]).split("/")[-1]
        
    if "-" in litmusName:
        print("Litmus test name cannot contain -")
        sys.exit(1)

    litmusProcedure = parse(sys.argv[1])

    litmusTests = distributeInstrs()

    #print(litmusTests)

    #for test in litmusTests:

    #print(litmusProcedure)

    oPath = sys.argv[2]
    oPath = oPath if oPath[len(oPath)-1] != '/' else oPath[0:len(oPath)-1]

    #print(sys.argv[2], sys.argv[3], litmusProcedure)
    #writeToFile(sys.argv[2], sys.argv[3], litmusProcedure)
    writeLitmusToFile(sys.argv[2], sys.argv[3], litmusTests)
