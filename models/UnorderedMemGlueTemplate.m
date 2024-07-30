
-- MemGlue Protocol

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
const
  ShimCount: _;      -- number of clusters / shims
  DataCount: 2;			 -- number of data values
  NetMax: 10;        -- 2*ShimCount+1;		-- max messages in the network (change?)
  AddrCount: 2;			 -- number of memory addresses
  MaxTimestamp: 100; -- bound on message timestamps
  MaxMsgCount: 100;
  MaxWrite: 100;
  MaxFence: 100;     -- max number of fences sent to a shim

  InstrCount: 4;		 -- Litmus test-dependent

  MaxSeenSet: 10;     -- Maximum seen ids in seen set of each shim

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------
type
  ShimId: 1..ShimCount;   --+1;		-- For indexing into list of shims
  Addr: 0..AddrCount-1;		-- For indexing into cache
  --CCId: 0; 
  Data: 0..DataCount;
  Timestamp: 0..MaxTimestamp;
  Node: 0..ShimCount; --+1;		-- This represents the CC plus the shims: CC = 0, Shims = 1..ShimCount+1
  MsgCount: 0..MaxMsgCount;
  FenceCnt: 0..MaxFence;
  WriteId: 0..MaxWrite;
  QueueInd: 0..InstrCount+1;
  SeenIdx: 0..MaxSeenSet-1;

  MessageType: enum {
    WRITE,
    WRITE_ACK,
    RREQ,
    EVICT,
    FREQ,
    RRESP,
    FRESP
  };

  OpStrength: enum {
    RLX,
    REL,
    ACQ,
    SC
  };

  Message: 
    Record
    mtype: MessageType;
    stren: OpStrength;
    src: Node; ------------------
    dst: Node; ------------------
    data: Data;
    addr: Addr;
    ts: Timestamp;
    cnt: MsgCount;
    fenceCnt: FenceCnt;
    writeId: WriteId;
    seenId: WriteId;
    qInd: QueueInd;
    wCntr: WriteId;
    End;

  -- NETOrdered: array[Node] of array[0..NetMax-1] of Message;
  -- NETOrderedCount: array[Node] of 0..NetMax;
  NETUnordered: array[Node] of multiset[NetMax] of Message; -- also used for partially ordered, with some extra checks in PopMessage

  CacheState: enum { Invalid, Valid };

  CCElemLastWrite: 
    Record
    writeId: WriteId;     -- write id of the last write to the address
    stren: OpStrength;    -- strength of the last write
    seenId: WriteId;      -- what the last write to the address saw
    shimId: Node;         -- unused
    wCntr: WriteId;       -- number of writes to the address from the shim that have reached the CC
    End;

  CCElemLastWritePerAddr: array[Addr] of CCElemLastWrite;

  SeenIdsElement: 
    Record
      seenIds: CCElemLastWritePerAddr;
      seenPerShim: WriteId;
      --writePerShim: WriteId;
    End;

  ShimElemState:
    Record
    state: CacheState;
    data: Data;
    ts: Timestamp;
    localWriteCntr: 0..MaxMsgCount;
    syncBit : boolean;
    rfBuf: 0..NetMax;
    --localSCWrite: enum { T, F };
    End;

  CCElemState:
    Record
    data: Data;
    ts: Timestamp;
    sharers: array[ShimId] of enum { Y, N };
    lastWriteShim: Node;
    End;

  BufEntry:
    Record
    status: 0..1;
    rf: boolean;
    msg: Message;
    End;

  ShimCache: array[Addr] of ShimElemState;		-- Cache for each shim
  CCCache: array[Addr] of CCElemState;
  MsgBuffer: array[0..NetMax-1] of BufEntry;

  SeenSet: array[SeenIdx] of WriteId;

  -- Litmus test specific----------
  PermissionType: 
    enum {
      load,
      store,
      fence,
      none
    };
  
  Instr: 
    Record
    access: PermissionType;        -- may not need this
    stren: OpStrength;
    addr: Addr;
    data: Data;      /* Value store for read operation performed */
    pend: boolean;
    End;

  FifoQueue: 
    Record
    Queue: array[0..InstrCount] of Instr;
    QueueInd: QueueInd;
    QueueCnt: QueueInd;
    End;
  ---------------------------------

  Shim:
    Record
    state: ShimCache;
    active: boolean;	-- active = still needs to execute litmus tests instructions
    pending: boolean;   -- pending = unsure, this doesn't seem necessary
    pendingWSC: boolean;   
    fencePending: boolean;
    queue: FifoQueue;   -- queue of litmus test instructions to be performed
    buf: MsgBuffer;
    bufCnt: 0..NetMax;
    icnt: MsgCount;
    ocnt: MsgCount;
    fenceCnt: FenceCnt;
    --waitBuf: MsgBuffer;
    waitCnt: 0..NetMax;
    seenId: WriteId;
    seenSet: SeenSet;
    seenSetBuf: SeenSet;
    seenSize: SeenIdx;
    seenSizeBuf: SeenIdx;

    stall: boolean;
    End;

  IOCnt: 
    Record
    icnt: MsgCount;
    ocnt: MsgCount;
    End;

  CCCounters: array[ShimId] of IOCnt;

  SeenIds: array[Node] of SeenIdsElement;

  FenceCnts: array[ShimId] of FenceCnt;

  CCMachine:
    Record
    cache: CCCache;
    buf: MsgBuffer;
    bufCnt: 0..NetMax;
    cntrs: CCCounters;
    fenceCnts: FenceCnts;
    --waitBuf: MsgBuffer;
    waitCnt: 0..NetMax;
    seenIds: SeenIds;
    End;

  ShimType: array[ShimId] of Shim;


----------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------
var
  CC: CCMachine;
  Shims: ShimType;
  NetU: NETUnordered;
  wIdCounter: WriteId;

  deliverMsgHack: Message;


----------------------------------------------------------------------
-- Procedures
----------------------------------------------------------------------

-- Generic ------------------------------------------------------------------

  -- Return whether writeId v is in the seenSet of shim s
  Function InSeenSet(s: ShimId; v: WriteId): boolean;
  Begin
    if v <= Shims[s].seenSet[0] then
      return true;
    endif;

    for i := 1 to Shims[s].seenSize-1 do
      if v = Shims[s].seenSet[i] then 
        return true;
      endif;
    endfor;

    return false;
  End;

  -- Return whether writeId v is in the seenSet of shim s
  Function InSeenSetShimBuf(s: ShimId; v: WriteId): boolean;
  Begin

    for i := 0 to Shims[s].seenSizeBuf-1 do
      if v = Shims[s].seenSetBuf[i] then 
        return true;
      endif;
    endfor;

    return false;
  End;

  -- Adds v to the seenSet of shim s
  Procedure AddSeenId(s: ShimId; v: WriteId);
  Begin
    if !(InSeenSet(s,v)) then
      Assert (Shims[s].seenSize < MaxSeenSet) "Seen set is full";
      Shims[s].seenSet[Shims[s].seenSize] := v;
      Shims[s].seenSize := Shims[s].seenSize + 1;
    endif;
  End;

  -- Adds v to the shim buffer seenSet of shim s
  Procedure AddSeenIdShimBuf(s: ShimId; v: WriteId);
  Begin
    if !(InSeenSetShimBuf(s,v)) then
      Assert (Shims[s].seenSizeBuf < MaxSeenSet) "Seen set is full";
      Shims[s].seenSetBuf[Shims[s].seenSizeBuf] := v;
      Shims[s].seenSizeBuf := Shims[s].seenSizeBuf + 1;
    endif;
  End;

  Procedure RemoveSeenIdShimBuf(s: ShimId; v: WriteId);
  var found: boolean;
  Begin
    found := false;

    for i := 0 to Shims[s].seenSizeBuf-1 do
      if !(found) then
        if Shims[s].seenSetBuf[i] = v then
          if i < Shims[s].seenSizeBuf-1 then 
            Shims[s].seenSetBuf[i] := Shims[s].seenSetBuf[i+1];
          else 
            undefine Shims[s].seenSetBuf[i];
          endif;
          found := true;
        endif;
      else 
        if i < Shims[s].seenSizeBuf-1 then 
          Shims[s].seenSetBuf[i] := Shims[s].seenSetBuf[i+1];
        else 
          undefine Shims[s].seenSetBuf[i];
        endif;
      endif;
    endfor;

    if found then
      Shims[s].seenSizeBuf := Shims[s].seenSizeBuf-1;
    endif;
  End;

  -- Return highest seen writeId from the seen set of shim s
  Function MaxSeenId(s: ShimId): WriteId;
  var maxVal: WriteId;
  Begin
    maxVal := 0;
    for i := 0 to Shims[s].seenSize-1 do 
      if Shims[s].seenSet[i] > maxVal then
        maxVal := Shims[s].seenSet[i];
      endif;
    endfor;
    return maxVal;
  End;

  Function MaxSeenIdBoth(s: ShimId): WriteId;
  var maxVal: WriteId;
  Begin
    maxVal := MaxSeenId(s);
    for i := 0 to Shims[s].seenSizeBuf-1 do 
      if Shims[s].seenSetBuf[i] > maxVal then
        maxVal := Shims[s].seenSetBuf[i];
      endif;
    endfor;
    return maxVal;
  End;   

  -- Remove all but the highest seen writeId from the seen set of shim s
  Procedure CullSeenSet(s: ShimId);
  var maxVal: WriteId;
  Begin
    maxVal := MaxSeenIdBoth(s);

    Shims[s].seenSet[0] := maxVal;

    for i := 1 to Shims[s].seenSize-1 do
      undefine Shims[s].seenSet[i];
    endfor;

    Shims[s].seenSize := 1;

    undefine Shims[s].seenSetBuf;
    Shims[s].seenSizeBuf := 0;

  End;


  Procedure Send(mtype:MessageType;
	               src:Node;
                 dst:Node;
         	       data:Data;
 	 	             addr:Addr;
		             ts:Timestamp;
		             stren:OpStrength;
		             count:MsgCount;
                 fenceCnt:FenceCnt;
                 wid:WriteId;
                 sid:WriteId;
                 qInd:QueueInd;
                 wCntr:WriteId;
                 );
  var msg:Message;
  Begin
    Assert (MultiSetCount(i:NetU[dst],true) < NetMax) "Too many messages";
    msg.mtype := mtype;
    msg.stren := stren;
    msg.src   := src;
    msg.dst   := dst;
    msg.data  := data;
    msg.addr  := addr;
    msg.ts    := ts;
    msg.cnt   := count;
    msg.fenceCnt := fenceCnt;
    msg.qInd  := qInd;
    msg.wCntr := wCntr;

    msg.writeId := wid;
    msg.seenId := sid;

    MultiSetAdd(msg, NetU[dst]);

  End;


  Procedure SendFence(mtype:MessageType;
	               src:Node;
                 dst:Node;
		             stren:OpStrength;
		             count:MsgCount;
                 );
  var msg:Message;
  Begin
    Assert (MultiSetCount(i:NetU[dst],true) < NetMax) "Too many messages";
    msg.mtype := mtype;
    msg.stren := stren;
    msg.src   := src;
    msg.dst   := dst;
    msg.cnt   := count;

    MultiSetAdd(msg, NetU[dst]);

  End;


  Procedure ShimPushBuf(dst:Node; msg:Message; status:0..1);
  var bufEntry: BufEntry;
  Begin
    Assert(Shims[dst].bufCnt < NetMax) "Too many messages in shim buffer";
    bufEntry.msg := msg;
    bufEntry.status := status;
    bufEntry.rf := false;
    Shims[dst].buf[Shims[dst].bufCnt] := bufEntry;
    Shims[dst].bufCnt := Shims[dst].bufCnt + 1;
  End;


  Procedure CCPushBuf(msg:Message; status:0..1);
  var bufEntry: BufEntry;
  Begin
    Assert(CC.bufCnt < NetMax) "Too many messages in shim buffer";
    bufEntry.msg := msg;
    bufEntry.status := status; -- ignore rf here
    CC.buf[CC.bufCnt] := bufEntry;
    CC.bufCnt := CC.bufCnt + 1;
  End;


  -- Remove idx th message
  Procedure ShimPopBuf(dst:Node; idx:0..NetMax);
  var bufEntry: BufEntry;
  Begin
    Assert(Shims[dst].bufCnt > idx) "No message to pop";
    bufEntry := Shims[dst].buf[idx];
    if (bufEntry.rf) then
      Assert (Shims[dst].state[bufEntry.msg.addr].rfBuf > 0) "Cannot pop rf message from buffer";
      Shims[dst].state[bufEntry.msg.addr].rfBuf := Shims[dst].state[bufEntry.msg.addr].rfBuf - 1;
    endif;
    for i := idx to Shims[dst].bufCnt-1 do
      if (i < Shims[dst].bufCnt-1)
      then
        Shims[dst].buf[i] := Shims[dst].buf[i+1];
      else
        undefine Shims[dst].buf[i];
      endif;
    endfor;
    Shims[dst].bufCnt := Shims[dst].bufCnt-1;
  End;


  -- Remove first message
  Procedure CCPopBuf(idx:0..NetMax);
  Begin
    Assert(CC.bufCnt > 0) "No ShimPopBufmessage to pop";
    for i := idx to CC.bufCnt-1 do
      if (i < CC.bufCnt-1)
      then
        CC.buf[i] := CC.buf[i+1];
      else
        undefine CC.buf[i];
      endif;
    endfor;
    CC.bufCnt := CC.bufCnt-1;
  End;


  Function NetworkOpen(): boolean;
  Begin
    for shim: ShimId do
      if MultiSetCount(i:NetU[shim],true) >= NetMax - 3
      then
         return false;
      endif;
    endfor;
    return true;
  End;


  Function CCOpen(): boolean;
  Begin
    if MultiSetCount(i:NetU[0],true) >= NetMax
    then
      return false;
    else
      return true;
    endif;
  End;


  -- Update output of litmus test load 
  Procedure UpdateVal(shim: ShimId; data: Data; qInd: QueueInd);
  Begin
    alias p: Shims[shim].queue do
    alias q: p.Queue do
    alias qcnt: p.QueueCnt do

    if qInd < qcnt & !isundefined(q[qInd].access) then
      q[qInd].data := data;
      q[qInd].pend := false;
    endif;

    endalias;
    endalias;
    endalias;
  End;


  -- Remove litmus test instruction 
  Procedure PopInstr(shim: ShimId);
  Begin
    alias sQ: Shims[shim].queue.Queue do
    alias QInd: Shims[shim].queue.QueueInd do
    alias QCnt: Shims[shim].queue.QueueCnt do

    QInd := QInd + 1;
    if QInd = QCnt then
      Shims[shim].active := false;
    else 
      if isundefined(sQ[QInd].access) then -- why is this here? Why would it be undefined?
	      Shims[shim].active := false;
      endif;
    endif;
    

    endalias;
    endalias;
    endalias;
  End;


-- Shim-specific ------------------------------------------------------------
  Procedure ShimWriteCache(shim: ShimId; 
			   state: CacheState; 
			   data: Data; 
			   ts: Timestamp; 
			   addr: Addr);
  Begin
  alias shimElem: Shims[shim].state[addr] do
    shimElem.state := state;
    shimElem.data := data;
    shimElem.ts := ts;
  endalias;
  End;

  Procedure ShimIncrTS(shim: ShimId; addr: Addr);
  Begin
  alias shimElem: Shims[shim].state[addr] do
    shimElem.ts := shimElem.ts + 1;
  endalias;
  End;

  -- SHIM: incoming messages
  Procedure ShimReceive(msg:Message; inOrder:boolean);
  var shimElem:ShimElemState;
  var addr:Addr;
  var data:Data;
  var ts:Timestamp;
  Begin

    switch msg.mtype
    case WRITE:
      addr := msg.addr;
      data := msg.data;
      ts := msg.ts;
      shimElem := Shims[msg.dst].state[msg.addr];
      Assert (!shimElem.syncBit) "syncBit set on write update";

      if ts > shimElem.ts
      then
        ShimWriteCache(msg.dst,Valid,data,ts,addr);
      else
        ShimIncrTS(msg.dst,addr); 
      endif;
      if (inOrder) then
        AddSeenId(msg.dst,msg.writeId); -- msg.seenId; --TODO check this
        --shimElem.syncBit := false;
      else 
        AddSeenIdShimBuf(msg.dst,msg.writeId);
      endif;

    case WRITE_ACK:
      addr := msg.addr;
      data := msg.data;
      ts := msg.ts;
      shimElem := Shims[msg.dst].state[msg.addr];

      -- If the write is a synchronizing write, handle differently
      if (Shims[msg.dst].state[msg.addr].syncBit) then
        if (Shims[msg.dst].state[msg.addr].localWriteCntr > 1) then
          data := Shims[msg.dst].state[msg.addr].data;
        endif;
        ShimWriteCache(msg.dst,Valid,data,ts+Shims[msg.dst].state[msg.addr].localWriteCntr-1,addr);
        Shims[msg.dst].state[msg.addr].syncBit := false;
      endif;

      if (Shims[msg.dst].pendingWSC) then
        Shims[msg.dst].pendingWSC := false;
      endif;

    case RRESP:
      addr := msg.addr;
      data := msg.data;
      ts := msg.ts;
      shimElem := Shims[msg.dst].state[msg.addr];

      -- If the read is synchronizing, handle differently
      if (Shims[msg.dst].state[msg.addr].syncBit) then
        if (Shims[msg.dst].state[msg.addr].localWriteCntr > 0) then
          data := Shims[msg.dst].state[msg.addr].data;
        endif;
        ShimWriteCache(msg.dst,Valid,data,ts+Shims[msg.dst].state[msg.addr].localWriteCntr,addr);
        Shims[msg.dst].state[msg.addr].syncBit := false;        
      else
        if (shimElem.ts <= msg.ts) then
          ShimWriteCache(msg.dst,Valid,data,ts,addr);
        endif;
      endif;
      if (inOrder) then
        AddSeenId(msg.dst,msg.writeId);
        --shimElem.syncBit := false;
      else
        AddSeenIdShimBuf(msg.dst,msg.writeId);
      endif;
      --UpdateVal(msg.dst, Shims[msg.dst].state[msg.addr].data, msg.qInd);
      UpdateVal(msg.dst, data, msg.qInd);

    case FREQ:
      Shims[msg.dst].fenceCnt := Shims[msg.dst].fenceCnt + 1;

    case FRESP:
      Assert(Shims[msg.dst].fencePending = true);
      Shims[msg.dst].fencePending := false;

    else
      error "Shim received invalid message type!";
    endswitch;

  End;

  -- SHIM: outgoing messages
  -- Write value, or send WRITE to CC
  Procedure ShimWrite(shim: ShimId; addr: Addr; data: Data; stren: OpStrength; qInd: QueueInd);
  var shimElem:ShimElemState;
  Begin
    shimElem := Shims[shim].state[addr];
    -- Make sure the syncBit is true
    if shimElem.state = Invalid then
      Assert (shimElem.syncBit) "SyncBit improperly set";
    endif;
    ShimWriteCache(shim,Valid,data,shimElem.ts+1,addr);
    Shims[shim].state[addr].localWriteCntr := Shims[shim].state[addr].localWriteCntr + 1;
    Assert (CCOpen()) "ShimWrite - too many messages";
    Send(WRITE,shim,0,data,addr,shimElem.ts+1,stren,Shims[shim].ocnt,0,0,MaxSeenIdBoth(shim),qInd,0);
    Shims[shim].ocnt := Shims[shim].ocnt + 1;
    if stren = SC then
      Shims[shim].pendingWSC := true;
    endif;
  End;


  Function CheckPendingRead(shim: ShimId; addr: Addr; qInd: QueueInd): boolean;
  Begin
  for i := 0 to qInd - 1 do
    if Shims[shim].queue.Queue[i].pend 
      & !(Shims[shim].queue.Queue[i].addr != addr & Shims[shim].queue.Queue[i].stren = RLX) 
    then
      return false;
    endif;
  endfor;
  return true;
  End;

  Function SameAddrReadsInQueue(shim: ShimId; qInd: QueueInd; addr: Addr): boolean;
  var instr: Instr;
  Begin
    for i := 0 to qInd - 1 do
      instr := Shims[shim].queue.Queue[i];
      if instr.pend & instr.addr = addr then
        return false;
      endif;
    endfor;
    return true;
  End;

  Function AcceptRRESPEarly(shim: ShimId; msg: Message): boolean;
  Begin
    Assert (msg.mtype = RRESP) "Wrong message at AcceptRRESP";
    Assert (msg.cnt > Shims[shim].icnt) "Wrong message at AcceptRRESP";

    --if (msg.ts < Shims[shim].state[msg.addr].ts) then
    --  error "Received stale RRESP";
    --endif;

    return !(SameAddrReadsInQueue(shim,msg.qInd,msg.addr))
          & msg.ts <= Shims[shim].state[msg.addr].ts;
  End;


  -- Read value, or send RREQ to CC
  Procedure ShimRead(shim: ShimId; addr: Addr; stren: OpStrength; qInd: QueueInd);
  var shimElem:ShimElemState;
  var found:boolean;
  var bufTS:Timestamp;
  var bufMsg: Message;
  var bufIdx: 0..NetMax;
  var bufWId: WriteId;
  var bufData: Data;
  Begin
  shimElem := Shims[shim].state[addr];
  if shimElem.state = Invalid then
    Assert (shimElem.syncBit) "SyncBit improperly set";
  endif;
  if stren = RLX then
    found := false;
    bufTS := Shims[shim].state[addr].ts;
    bufIdx := 0;
    for i := 0 to Shims[shim].bufCnt - 1 do -- attempt to read from buffer for data -- CHECK: does this need to be more fine-grained? Check ts?
      bufMsg := Shims[shim].buf[i].msg;
      if bufMsg.mtype = WRITE & bufMsg.addr = addr & bufMsg.ts > bufTS & bufMsg.wCntr = Shims[shim].state[addr].localWriteCntr then
        found := true;
        bufTS := bufMsg.ts;
        bufIdx := i;
        bufWId := bufMsg.writeId;
        bufData := bufMsg.data;
      endif;
    endfor;
    if found & CheckPendingRead(shim, addr, qInd) then -- FINISH
      if (!Shims[shim].buf[bufIdx].rf) then
        Shims[shim].buf[bufIdx].rf := true;
        Shims[shim].state[addr].rfBuf := Shims[shim].state[addr].rfBuf + 1;
      endif;
      UpdateVal(shim, bufData, qInd);
      AddSeenIdShimBuf(shim,bufWId);
    else
      if (shimElem.state = Valid & CheckPendingRead(shim, addr, qInd)) -- & Shims[shim].bufCnt = 0) -- TODO: make this more fine-grained! If buf only has messages of other addresses, we can read from the cache
      then
        UpdateVal(shim, shimElem.data, qInd);
      else
        Assert (CCOpen()) "ShimRead - too many messages";
        Send(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren,Shims[shim].ocnt,0,0,0,qInd,0);
        Shims[shim].ocnt := Shims[shim].ocnt + 1;
      endif;
      
    endif;
  else
  --if stren = ACQ then
    if (shimElem.state = Valid & CheckPendingRead(shim, addr, qInd)) -- TODO: make this more fine-grained! If buf only has messages of other addresses, we can read from the cache
    then
      UpdateVal(shim, shimElem.data,qInd);
    else
      Assert (CCOpen()) "ShimRead - too many messages";
      Send(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren,Shims[shim].ocnt,0,0,0,qInd,0);
      Shims[shim].ocnt := Shims[shim].ocnt + 1;
    endif;   
  --else
  --  Assert (CCOpen()) "ShimRead - too many messages";
  --  Send(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren,Shims[shim].ocnt,0,0,0,qInd,0);
  --  Shims[shim].ocnt := Shims[shim].ocnt + 1;
  --endif;          

  endif;

  End; 

  -- Stop local reads until FRESP received
  Procedure ShimFence(shim: ShimId);
  Begin
    Shims[shim].fencePending := true;
    SendFence(FREQ,shim,0,SC,Shims[shim].ocnt);
    Shims[shim].ocnt := Shims[shim].ocnt + 1;
  End;

-- CC: process messages -----------------------------------------------------
  Procedure CCReceive(msg:Message);
  Begin
    switch msg.mtype

    case WRITE:
      CC.cache[msg.addr].data := msg.data; -- always perform write
      if CC.cache[msg.addr].ts >= msg.ts
      then -- if data is stale, increment ts
	      CC.cache[msg.addr].ts := CC.cache[msg.addr].ts+1;
      else -- otherwise use msg ts
	      CC.cache[msg.addr].ts := msg.ts;
      endif;

      CC.seenIds[msg.src].seenIds[msg.addr].wCntr := CC.seenIds[msg.src].seenIds[msg.addr].wCntr + 1;

      ---
      CC.cache[msg.addr].lastWriteShim := msg.src;
      if msg.stren != RLX then 
        if CC.seenIds[msg.src].seenPerShim > msg.seenId then 
          CC.seenIds[msg.src].seenIds[msg.addr].seenId := CC.seenIds[msg.src].seenPerShim;
        else 
          CC.seenIds[msg.src].seenIds[msg.addr].seenId := msg.seenId;
        endif;
      endif;
      CC.seenIds[msg.src].seenIds[msg.addr].writeId := wIdCounter;
      CC.seenIds[msg.src].seenPerShim := wIdCounter;
      ---
      wIdCounter := wIdCounter + 1;

      -- send write to sharers (except source)
      Assert (NetworkOpen()) "CCReceive Write - too many messages";
      for sharer:ShimId do
        if (CC.cache[msg.addr].sharers[sharer] = Y & sharer != msg.src)
    	  then
          Send(WRITE,0,sharer,msg.data,msg.addr,CC.cache[msg.addr].ts,msg.stren,
               CC.cntrs[sharer].ocnt,CC.fenceCnts[sharer],
               CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId,
               CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].seenId,
               msg.qInd,CC.seenIds[sharer].seenIds[msg.addr].wCntr); -- Always send seen and write ids...
	        CC.cntrs[sharer].ocnt := CC.cntrs[sharer].ocnt + 1;
	      endif;
      endfor;

      -- if a shim is "checking in" or write is SC, send them a write update to sync timestamps
      -- NOTE: the only fields that will be used from this message are the 
      -- timestamp, data, and ocnt, the other fields are not considered. 
      if msg.stren = SC | CC.cache[msg.addr].sharers[msg.src] = N then
        Send(WRITE_ACK,0,msg.src,msg.data,msg.addr,CC.cache[msg.addr].ts,msg.stren,
             CC.cntrs[msg.src].ocnt,CC.fenceCnts[msg.src],
             CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId,
             CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].seenId,
             msg.qInd,CC.seenIds[msg.src].seenIds[msg.addr].wCntr);
	        CC.cntrs[msg.src].ocnt := CC.cntrs[msg.src].ocnt + 1;
      endif;
      -- add src to sharers
      CC.cache[msg.addr].sharers[msg.src] := Y;

    case RREQ:
      CC.cache[msg.addr].sharers[msg.src] := Y;    -- Add shim to sharers
      Assert (NetworkOpen()) "CCReceive RREQ - too many messages";
      -- Always send along write id and seen id
      if CC.cache[msg.addr].lastWriteShim = 0 then -- if reading from initial data, last write id is 0
        Send(RRESP,0,msg.src,CC.cache[msg.addr].data,msg.addr,CC.cache[msg.addr].ts,msg.stren,
             CC.cntrs[msg.src].ocnt,CC.fenceCnts[msg.src],0,0,msg.qInd,0); -- Do we need to send write id? No
      else
        Send(RRESP,
             0,
             msg.src,
             CC.cache[msg.addr].data,
             msg.addr,
             CC.cache[msg.addr].ts,
             msg.stren,
             CC.cntrs[msg.src].ocnt,
             CC.fenceCnts[msg.src],
             CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId,
             CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].seenId,
             msg.qInd,0);

        if CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId > CC.seenIds[msg.src].seenPerShim then -- new shim-wide sid = max(reading shim-wide sid, wid of write being read)
            CC.seenIds[msg.src].seenPerShim := CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId;
        endif;

      endif;
      CC.cntrs[msg.src].ocnt := CC.cntrs[msg.src].ocnt + 1;

    case FREQ:
      Assert (NetworkOpen()) "CCReceive FREQ - too many messages";

      -- For each shim that didn't send the fence, and for each address, if the 
      -- shim and the source both share the address, send a fence to that shim.
      -- Only send on fence.
      -- TESTING: send fences to every shim
      for shim:ShimId do
        if shim != msg.src then
          CC.fenceCnts[shim] := CC.fenceCnts[shim] + 1;
          SendFence(FREQ,0,shim,msg.stren,CC.cntrs[shim].ocnt);
          CC.cntrs[shim].ocnt := CC.cntrs[shim].ocnt + 1; 
        endif;       
      endfor;

      SendFence(FRESP,0,msg.src,msg.stren,CC.cntrs[msg.src].ocnt);
      CC.cntrs[msg.src].ocnt := CC.cntrs[msg.src].ocnt + 1;

    else
      error "CC received invalid message type!";
    endswitch
  End;


  Procedure TryCCReceive(msg: Message);
  var found: boolean; var bufData: Data; var bufTS: 0..NetMax;
  Begin
    switch msg.mtype
    case WRITE:
      if msg.cnt = CC.cntrs[msg.src].icnt  
      then
        CCReceive(msg);
        CC.cntrs[msg.src].icnt := CC.cntrs[msg.src].icnt + 1;
      else
        CCPushBuf(msg,0);
      endif;

    case RREQ:
      switch msg.stren
      case RLX: -- Case: Write relaxed
        if msg.cnt = CC.cntrs[msg.src].icnt then
            CCReceive(msg);
            CC.cntrs[msg.src].icnt := CC.cntrs[msg.src].icnt + 1;
        else
          CCPushBuf(msg,0);
        endif;

      else -- Case: Write release / sc
        Assert(msg.stren = SC | msg.stren = REL | msg.stren = ACQ) "Message has invalid strength type";
        if msg.cnt = CC.cntrs[msg.src].icnt then
            CCReceive(msg);
            CC.cntrs[msg.src].icnt := CC.cntrs[msg.src].icnt + 1;
        else
          CCPushBuf(msg,0); 
        endif;

      endswitch;

    case FREQ:
      if msg.cnt = CC.cntrs[msg.src].icnt then
          CCReceive(msg);
          CC.cntrs[msg.src].icnt := CC.cntrs[msg.src].icnt + 1;
        else
          CCPushBuf(msg,0); 
        endif;

    else
      error "CC received invalid message type!"
    endswitch;


    -- CCReceive(msg);
  End;

  Function ShimAcceptMessage(msg: Message) : boolean;
  Begin
    -- if a message is received out of order, should it be accepted?
    Assert (msg.cnt > Shims[msg.dst].icnt) "Error in ShimAcceptMessage";
    if Shims[msg.dst].fencePending 
     | (msg.mtype != FREQ & msg.mtype != FRESP & Shims[msg.dst].fenceCnt < msg.fenceCnt) then
        -- Do not accept messages early if the shim is waiting to receive more fences from the CC.
      return false;
    else 
    if msg.mtype != FREQ & msg.mtype != FRESP & (Shims[msg.dst].state[msg.addr].syncBit) then
      return false;
    else 
    
      if msg.mtype = WRITE_ACK then -- WRITE_ACK always accepted in order
        return false;
      endif;

      switch msg.mtype
      case WRITE:
        if !(msg.ts + Shims[msg.dst].state[msg.addr].localWriteCntr - msg.wCntr >= Shims[msg.dst].state[msg.addr].ts + 1) then
          deliverMsgHack := msg;
          error "Write message acceptance logic off";
        endif;

        if msg.ts + Shims[msg.dst].state[msg.addr].localWriteCntr - msg.wCntr != Shims[msg.dst].state[msg.addr].ts + 1 then
          return false;
        endif;

        switch msg.stren
        case RLX:
          return true;
        case REL:
          if InSeenSet(msg.dst,msg.seenId) then
            return true;
          else 
            return false;
          endif;
        else -- case: SC
          return false;
        endswitch;

      case RRESP:
        if !(AcceptRRESPEarly(msg.dst, msg)) then
          return false;
        endif;

        switch msg.stren
        case RLX:
          return true;
        case ACQ:
          if InSeenSet(msg.dst,msg.seenId) then
            return true;
          else 
            return false;
          endif;
        else -- Case: SC
          return false;
        endswitch;

      case FREQ:
        -- Fences always accepted in order
        return false;

      case FRESP:
        Assert (msg.stren = SC) "Wrong strength for fence (must be SC)";
        return false;

      else
        error "Shim received invalid message type!"
      endswitch;
    endif;
    endif;
  End;


  Procedure TryShimReceive(msg: Message);
  Begin 
    -- if message is received in order
    if msg.cnt = Shims[msg.dst].icnt then -- accept message
      Shims[msg.dst].icnt := Shims[msg.dst].icnt + 1;
      ShimReceive(msg,true);
    else
      Assert (msg.cnt > Shims[msg.dst].icnt) "Error in TryShimReceive";
      if ShimAcceptMessage(msg) then
        ShimReceive(msg,false);
        ShimPushBuf(msg.dst,msg,1);
      else
        ShimPushBuf(msg.dst,msg,0);
      endif;

    endif;
  End;


  -- Deliver most-recently popped message and try to pop a message
  -- from the wait buffers of the source nodes.
  Procedure DeliverMsg(msg: Message);
  Begin
    if msg.dst = 0 then 
      TryCCReceive(msg);
      --if msg.mtype != FREQ then
      --  TryPopWaitBufShim(msg.src,msg.dst,msg.addr); -- Messages to CC come from shims
      --endif;
    else
      TryShimReceive(msg);
      --if msg.mtype != FRESP & msg.mtype != FREQ then
      --  TryPopWaitBufCC(msg.dst,msg.addr); -- Message to shims come from CC
      --endif;
      
    endif;

  End;

  Procedure TryPopBufShim(n:Node);
  var popped: boolean; var i: 0..NetMax; var msg: Message;
  Begin
    popped := false;
    i := 0;
    while !popped & i < Shims[n].bufCnt do
      msg := Shims[n].buf[i].msg;
      if Shims[n].buf[i].msg.cnt = Shims[n].icnt then
        popped := true;
        if Shims[n].buf[i].status = 0 then
          ShimReceive(msg,true);
        else
          AddSeenId(msg.dst,msg.writeId);
          RemoveSeenIdShimBuf(msg.dst,msg.writeId);
        endif;
        ShimPopBuf(n,i);
        Shims[n].icnt := Shims[n].icnt + 1;
      else 
        if Shims[n].buf[i].status = 0 then
          if ShimAcceptMessage(msg) then
            -- Upgrade from status 0 to status 1
            ShimReceive(msg,false);
            Shims[n].buf[i].status := 1;
          endif;
        endif;
      endif;
      i := i + 1;

    endwhile;

    if popped != false then TryPopBufShim(n); endif;

    if Shims[n].bufCnt = 0 then
      CullSeenSet(n);
    endif;

  End;

  Procedure TryPopBufCC();
  var popped: boolean; var i: 0..NetMax;
  Begin
    popped := false;
    i := 0;
    while !popped & i < CC.bufCnt do
      if CC.buf[i].msg.cnt = CC.cntrs[CC.buf[i].msg.src].icnt then
        popped := true;
        if CC.buf[i].status = 0 then
          CCReceive(CC.buf[i].msg);
        endif;
        CC.cntrs[CC.buf[i].msg.src].icnt := CC.cntrs[CC.buf[i].msg.src].icnt + 1;
        CCPopBuf(i);
      endif;
      i := i + 1;
    endwhile;

    if popped != false then TryPopBufCC(); endif;
  End;

  Function CheckReset(): boolean;
  Begin
    for s: ShimId do
      if Shims[s].active = true then
        return false;
      endif;
      if MultiSetCount(i:NetU[s],true) > 0 then
	      return false;
      endif;
      for i := 0 to Shims[s].queue.QueueCnt-1 do
        if Shims[s].queue.Queue[i].pend = true then
          return false;
        endif;

      endfor;
    endfor;
    return true;
  End;
  
  Procedure AddInstr(shim: ShimId; instr: Instr);
  Begin
    alias sQ: Shims[shim].queue.Queue do
    alias QCnt: Shims[shim].queue.QueueCnt do
      sQ[QCnt] := instr;
      sQ[QCnt].pend := false;
      QCnt := QCnt + 1;
    endalias;
    endalias;
  End;


/* Litmus test */

---------------------------------------------------------------------
  Procedure InitLitmusTests();
  Begin
    /* InitLitmusTests(); */
  End;

  Procedure WriteInitialData();
  Begin
    /* WriteInitialData(); */
  End;

  Procedure SystemReset();
  Begin

    -- Reset shim caches and CC
    For a:Addr do
      CC.cache[a].ts := 0;
      CC.cache[a].data := 0;
      CC.cache[a].lastWriteShim := 0;

      For s:ShimId do
	      CC.cache[a].sharers[s] := N;
      	CC.cntrs[s].icnt := 0;
      	CC.cntrs[s].ocnt := 0;
        CC.fenceCnts[s] := 0;
        CC.seenIds[s].seenIds[a].writeId := 0;
        undefine CC.seenIds[s].seenIds[a].stren;
        CC.seenIds[s].seenIds[a].seenId := 0;
        undefine CC.seenIds[s].seenIds[a].shimId;
        CC.seenIds[s].seenIds[a].wCntr := 0;
        CC.seenIds[s].seenPerShim := 0;
        --CC.seenIds[s].writePerShim := 0;
        
	      Shims[s].state[a].state := Invalid;
	      undefine Shims[s].state[a].data;
	      Shims[s].state[a].ts := 0;
        Shims[s].state[a].localWriteCntr := 0;
        Shims[s].state[a].syncBit := true;
        Shims[s].state[a].rfBuf := 0;
        --Shims[s].state[a].localSCWrite := F;
	      Shims[s].queue.QueueCnt := 0;
	      Shims[s].queue.QueueInd := 0;
	      undefine Shims[s].queue.Queue;
	      Shims[s].active := true;
        Shims[s].pendingWSC := false;
	      Shims[s].fencePending := false;
        undefine Shims[s].buf;
	      Shims[s].icnt := 0;
	      Shims[s].ocnt := 0;
        Shims[s].fenceCnt := 0;
	      Shims[s].bufCnt := 0;
	      --undefine Shims[s].waitBuf;
	      Shims[s].waitCnt := 0;
      endfor;
    endfor;

    WriteInitialData();

    For s:ShimId do
      Shims[s].seenId := 0;
      Shims[s].seenSet[0] := 0;
      undefine Shims[s].seenSetBuf;
      Shims[s].seenSize := 1;
      Shims[s].seenSizeBuf := 0;

    endfor;

    undefine CC.buf;
    CC.bufCnt := 0;
    --undefine CC.waitBuf;
    CC.waitCnt := 0;

    wIdCounter := 1; -- First write id is 1

    -- Net reset
    -- undefine Net;
    undefine NetU;

    -- Litmus test initialization
    InitLitmusTests();

  End;

  -- Litmus test-specific -----------------------------------------------------
  -- Update value of load in litmus test
 
  -- Fetch shim's next litmus test instructions
  Function GetInstr(shim: ShimId): Instr;
  var instr: Instr;
  Begin
    alias sQ: Shims[shim].queue.Queue do
    alias QInd: Shims[shim].queue.QueueInd do
    alias QCnt: Shims[shim].queue.QueueCnt do    
    undefine instr;

    if QInd = QCnt
    then
      return instr;
    endif;

    if !isundefined(sQ[QInd].access) 
    then
      sQ[QInd].pend := true;
      return sQ[QInd];
    endif;

    endalias;
    endalias;
    endalias;
  End;

  -- Call the appropriate procedures given an instruction
  Procedure IssueInstr(shim: ShimId);
  var instr: Instr;      
  var qind: QueueInd;
  Begin
    instr := GetInstr(shim);
    qind := Shims[shim].queue.QueueInd;
    
    if instr.access = load & CCOpen() then -- ignore cpu.pending for now...
      ShimRead(shim, instr.addr, instr.stren, qind);
    endif;

    if instr.access = store & NetworkOpen() & CCOpen() then
      ShimWrite(shim, instr.addr, instr.data, instr.stren, qind);
      Shims[shim].queue.Queue[qind].pend := false;
    endif;

    if instr.access = fence & CCOpen() then
      ShimFence(shim);
      Shims[shim].queue.Queue[qind].pend := false;
    endif;

    PopInstr(shim);
    -- Shims[shim].queue.QueueInd := Shims[shim].queue.QueueInd + 1;

  End;

  Function Stall(shim: ShimId) : boolean;
  var instr : Instr;
  Begin
    if Shims[shim].fencePending = true then
      return true;
    endif;

    if Shims[shim].pendingWSC = true then
      return true;
    endif;
    
    instr := Shims[shim].queue.Queue[Shims[shim].queue.QueueInd];
    if instr.access = load & instr.stren != RLX then
      if Shims[shim].state[instr.addr].rfBuf > 0 then
        return true;

      endif;
    endif;

    return false;
  End;

-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------
  -- Establish order of message reception by loading messages from 
  -- unordered into ordered net
  ruleset n:Node do
    choose msg:NetU[n] do
      rule "deliver msg"
      	MultiSetCount(i:NetU[n],true) > 0
      ==>
        deliverMsgHack := NetU[n][msg];
        MultiSetRemove(msg,NetU[n]); -- Moved message removal into the DeliverMsg function to avoid issues with CheckSameSrcAddr...
	      DeliverMsg(deliverMsgHack); -- NetU[n][msg]); --Delivers message and adds net msg to network

        --if n > 0 then
        --  shimreceiveicntHack := Shims[deliverMsgHack.dst].icnt;
        --endif;

        -- Only one message should become available to be popped at a time
        -- So we should be able to just check after we deliver a message if
        -- there are any new ones to send?
        -- But it would have to be recursive: popping one message from the buffer may result in another becoming poppable

        -- Can also just leave it to be done in the search buffer rule... or can we? Does this need to be done immediately? Probably...

        if deliverMsgHack.dst = 0 then -- n doesn't work here! It's always 0 for some reason
          TryPopBufCC();
        else
          TryPopBufShim(deliverMsgHack.dst); --n
        endif;
        
      endrule;
    endchoose;
  endruleset;

  -- Execute litmus test
  -- NOTE: when fence in place, don't execute...
  ruleset shim:ShimId do
    rule "Execute litmus instruction" 
      Shims[shim].active = true
      & !Shims[shim].queue.Queue[Shims[shim].queue.QueueInd].pend
      & !Stall(shim)
    ==> 
      IssueInstr(shim);
    endrule;

    rule "Shim done"
      Shims[shim].active = false
    ==> 
      if CheckReset() 
      then
        /* Forbidden function */
        SystemReset();
      endif;
    endrule;
  endruleset;

-------------------------------------------------------------------------------
-- Startstate
-------------------------------------------------------------------------------
  startstate
    SystemReset();
  endstartstate;
