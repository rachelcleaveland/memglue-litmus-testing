# Same as TranslateLitmus-New.py, but all cores that read initial data (0's)
# are initially sharers of ALL addresses, not just those that initial data
# is read from


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
#numInitLoads = 0
initLoads = {}


def writeToFile(oPath,fName,litmusProcedure):
    global initLoads, vars, numAddrs

    fNameTemplate = fName.split("models/")[1]

    oFileName = oPath + "/" + fNameTemplate[0:len(fNameTemplate)-2] + litmusName + ".m" if ".m" in fName else oPath + "/" + fNameTemplate + litmusName + ".m"  
    oFile = open(oFileName, "w")
    iFile = open(fName, "r")

    for line in iFile.readlines():
        if "ShimCount: _;" in line:
            oFile.write("  ShimCount: " + str(len(cores)) + ";      -- number of clusters / shims\n")
        elif "AddrCount:" in line:
            oFile.write("  AddrCount: " + str(numAddrs) + ";     -- number of addresses\n")
        elif "/* Litmus test */" in line:
            oFile.write(litmusProcedure)
        elif "/* InitLitmusTests(); */" in line:
            for key in instrs.keys():
                oFile.write("    Shim" + str(key+1) + "Instr" + litmusName + "();\n")
        elif "/* WriteInitialData(); */" in line:
            for loads in initLoads.keys():
                for addr_num in range(numAddrs):
                    shim = str(loads+1)
                    addr = str(addr_num)
                    initData = "    CC.cache[" + addr + "].sharers[" + shim + "] := Y;\n"
                    initData = initData + "    Shims[" + shim + "].state[" + addr + "].state := Valid;\n"
                    initData = initData + "    Shims[" + shim + "].state[" + addr + "].data := 0;\n"
                    initData = initData + "    Shims[" + shim + "].state[" + addr + "].ts := 0;\n"
                    initData = initData + "    Shims[" + shim + "].state[" + addr + "].syncBit := false;\n"
                    oFile.write(initData)
        elif "/* Forbidden function */" in line:
            oFile.write("        Forbidden" + litmusName + "();\n")
        else:
            oFile.write(line)


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

def buildInstrFunc(core):
    instrCore = str(int(core)+1)
    fName = "  Procedure Shim" + instrCore + "Instr" + litmusName + "();"
    coreInstrs = instrs.get(int(core),[])
    instrVars = "  "
    instrInstrs = ""
    for i in range(len(coreInstrs)):
        instrVars = instrVars + "var I" + str(i+1) + ": Instr; "
        instrInstrs = instrInstrs + "    I" + str(i+1) + ".access := " + coreInstrs[i][0] + ";\n"
        instrInstrs = instrInstrs + "    I" + str(i+1) + ".stren := " + strenFromOrder(coreInstrs[i][3]) + ";\n"
        if coreInstrs[i][0] == "fence":
            instrInstrs = instrInstrs + "    I" + str(i+1) + ".addr := undefined;\n"
        else:
            instrInstrs = instrInstrs + "    I" + str(i+1) + ".addr := " + str(vars.get(coreInstrs[i][2])) + ";\n"
        if coreInstrs[i][0] == "load" or coreInstrs[i][0] == "fence":
            instrInstrs = instrInstrs + "    I" + str(i+1) + ".data := undefined;\n"
        else:
            instrInstrs = instrInstrs + "    I" + str(i+1) + ".data := " + coreInstrs[i][1] + ";\n"
        instrInstrs = instrInstrs + "    AddInstr(" + instrCore + ",I" + str(i+1) + ");\n\n"
        
    instrFunc = fName + "\n" + instrVars + "\n  Begin\n" + instrInstrs + "  End;\n\n"

    return instrFunc

def buildInstrForbidden():
    #global numInitLoads
    forbFunc = "  Procedure Forbidden" + litmusName + "();\n  var matches: 0.." \
        + str(len(loads.keys())) + ";\n  Begin\n    matches := 0;\n"
        #+ str(len(loads.keys()) + numInitLoads) + ";\n  Begin\n    matches := 0;\n"
    for core in instrs.keys():
        #initialLoads = rfInitial.get(core)
        #for i in range(len(initialLoads)):
        #    forbFunc = forbFunc + "    if Shims["+str(core+1)+"].queue.Queue[" + str(i) \
        #        + "].data = 0 then\n      matches := matches + 1;\n    endif;\n"
        instrList = instrs.get(core)
        for i in range(len(instrList)):
            if instrList[i][0] == "load":
                forbFunc = forbFunc + "    if Shims["+str(core+1)+"].queue.Queue[" + str(i) \
                           + "].data = " + instrList[i][1] + " then\n      matches := matches + 1;\n    endif;\n"
    numMatches = len(loads.keys()) #+ numInitLoads
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
            print(vars)
            print("Parsed unknown variable in", line)
            sys.exit(1)
        atomic = line.split("memory_order_")[1].split(");")[0]
        value = line.split(",")[1].strip()
        addInstr(("store",value,var,atomic),core)
        return
    elif re.search(r'atomic_thread_fence\([\s]*memory_order_[_,a-z]+\);',line) != None:
        atomic = line.split("memory_order_")[1].split(");")[0]
        addInstr(("fence","undefined","undefined",atomic),core)
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
    global numCores, litmusName, initLoads, numAddrs

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
            #if numAddrs > 2:
            #    print("Error: cannot handle more than 2 addresses")
            #    sys.exit(1)
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

    finalProcedure = "-- Litmus Test: " + litmusName + " -------------\n"
    for key in instrs.keys():
        finalProcedure = finalProcedure + buildInstrFunc(str(key))

    finalProcedure = finalProcedure + buildInstrForbidden()

    litFile.close()

    return finalProcedure




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

    oPath = sys.argv[2]
    oPath = oPath if oPath[len(oPath)-1] != '/' else oPath[0:len(oPath)-1]

    #print(sys.argv[2], sys.argv[3], litmusProcedure)
    writeToFile(sys.argv[2], sys.argv[3], litmusProcedure)
