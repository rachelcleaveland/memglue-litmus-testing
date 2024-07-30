
-- MemGlue Protocol

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
const
  ShimCount: _;         	-- number of clusters / shims
  DataCount: 4;		-- number of data values
  NetMax: 10; -- 2*ShimCount+1;		-- max messages in the network (change?)
  AddrCount: 2;			-- number of memory addresses
  MaxTimestamp: 100;		-- bound on message timestamps

  InstrCount: 2;		-- Litmus test-dependent

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------
type
  ShimId: 1..ShimCount;       	-- For indexing into list of shims
  Addr: 0..AddrCount-1;		      -- For indexing into cache
  Data: 0..DataCount;
  Timestamp: 0..MaxTimestamp;
  Node: 0..ShimCount;         	-- This represents the CC plus the shims: CC = 0, Shims = 1..ShimCount+1 

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
    src: Node; ------------------
    dst: Node; ------------------
    data: Data;
    addr: Addr;
    ts: Timestamp;
    stren: OpStrength;
    End;

  NETOrdered: array[Node] of array[0..NetMax-1] of Message;
  NETOrderedCount: array[Node] of 0..NetMax;
  NETUnordered: array[Node] of multiset[NetMax] of Message;

  CacheState: enum { Invalid, Valid };

  ShimElemState:
    Record
    state: CacheState;
    data: Data;
    ts: Timestamp;
    syncBit: boolean;
    End;

  CCElemState:
    Record
    data: Data;
    ts: Timestamp;
    sharers: array[ShimId] of enum { Y, N };
    End;

  ShimCache: array[Addr] of ShimElemState;		-- Cache for each shim
  CCCache: array[Addr] of CCElemState;

  -- Litmus test specific---------
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
    Queue: array[0..2] of Instr;
    QueueInd: 0..2+1;
    QueueCnt: 0..2+1;
    End;
  ---------------------------------

  Shim:
    Record
    state: ShimCache;
    active: boolean;	-- active = still needs to execute litmus tests instructions
    pendingWSC: boolean;   
    fencePending: boolean;
    queue: FifoQueue;   -- queue of litmus test instructions to be performed
    End;

  CCMachine:
    Record
    cache: CCCache;
    queue: FifoQueue;
    End;

  ShimType: array[ShimId] of Shim;


----------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------
var
  CC: CCMachine;
  Shims: ShimType;
  Net: NETOrdered;
  NetCount: NETOrderedCount;


----------------------------------------------------------------------
-- Procedures
----------------------------------------------------------------------

  -- Generic ------------------------------------------------------------------
  Procedure Send(mtype:MessageType;
	               src:Node;
                 dst:Node;
         	       data:Data;
 	 	             addr:Addr;
		             ts:Timestamp;
                 stren:OpStrength;
         	      );
  var msg:Message;
  Begin
    Assert (NetCount[dst] < NetMax) "Too many messages";
    msg.mtype := mtype;
    msg.src   := src;
    msg.dst   := dst;
    msg.data  := data;
    msg.addr  := addr;
    msg.ts    := ts;
    msg.stren := stren;
    --MultiSetAdd(msg, Net[dst]);

    Net[dst][NetCount[dst]] := msg;
    NetCount[dst] := NetCount[dst] + 1;

  End;

  Procedure SendFence(
                 mtype:MessageType;
	               src:Node;
                 dst:Node;
         	      );
  var msg:Message;
  Begin
    Assert (NetCount[dst] < NetMax) "Too many messages";
    msg.mtype := mtype;
    msg.src   := src;
    msg.dst   := dst;

    Net[dst][NetCount[dst]] := msg;
    NetCount[dst] := NetCount[dst] + 1;

  End;

  -- Remove first message
  Procedure PopMessage(dst:Node); 
  Begin
    Assert(NetCount[dst] > 0) "No message to pop";
    for i := 0 to NetCount[dst]-1 do
      if (i < NetCount[dst]-1) 
      then
	      Net[dst][i] := Net[dst][i+1];
      else
	      undefine Net[dst][i];
      endif;
    endfor;
    NetCount[dst] := NetCount[dst]-1;

  End;

  
  Function NetworkOpen(): boolean;
  Begin
    for shim: ShimId do
      if NetCount[shim] >= NetMax - 3
      then
         return false;
      endif;
    endfor;
    return true;
  End;

  Function CCOpen(): boolean;
  Begin
    if NetCount[0] >= NetMax
    then
      return false;
    else
      return true;
    endif;
  End;

  -- Update output of litmus test load 
  Procedure UpdateVal(shim: ShimId; data: Data);
  Begin
    alias p: Shims[shim].queue do
    alias q: p.Queue do
    alias qind: p.QueueInd do
    alias qcnt: p.QueueCnt do

    if qind < qcnt & !isundefined(q[qind].access) then
      q[qind].data := data;
    endif;

    endalias;
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

    sQ[QInd].pend := false;
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
  Procedure ShimReceive(msg:Message);
  var shimElem:ShimElemState;
  var addr:Addr;
  var data:Data;
  var ts:Timestamp;
  Begin
    --addr := msg.addr;
    --data := msg.data;
    --ts := msg.ts;

    switch msg.mtype
    case WRITE:
      shimElem := Shims[msg.dst].state[msg.addr];
      Assert (!shimElem.syncBit) "syncBit set on write update";

      if msg.ts > shimElem.ts
      then
        ShimWriteCache(msg.dst,Valid,msg.data,msg.ts,msg.addr);
      else
        ShimIncrTS(msg.dst,msg.addr); 
      endif;

    case WRITE_ACK:
      shimElem := Shims[msg.dst].state[msg.addr];

      if (shimElem.syncBit) then
        ShimWriteCache(msg.dst,Valid,shimElem.data,msg.ts+shimElem.ts-1,msg.addr);
        Shims[msg.dst].state[msg.addr].syncBit := false;
      endif;
      if Shims[msg.dst].pendingWSC then 
        Shims[msg.dst].pendingWSC := false;
      endif;


    case RRESP:
      -- if (shimElem.state = Invalid) -- CHECK: do we need invalid check? Probably not
      -- then
      shimElem := Shims[msg.dst].state[msg.addr];

      if (shimElem.syncBit) then
        Shims[msg.dst].state[msg.addr].syncBit := false;
      endif;
      ShimWriteCache(msg.dst,Valid,msg.data,msg.ts,msg.addr);
      -- endif;
      UpdateVal(msg.dst, msg.data);
      PopInstr(msg.dst);

    case FRESP:
      Assert(Shims[msg.dst].fencePending = true);
      Shims[msg.dst].fencePending := false;
      if (!Shims[msg.dst].pendingWSC) then
        PopInstr(msg.dst); -- CHECK
      else
        Shims[msg.dst].pendingWSC := false;
      endif;
    else
      error "Shim received invalid message type!";
    endswitch;

  End;

  -- SHIM: outgoing messages
  -- Write value, or send WRITE to CC
  Procedure ShimWrite(shim: ShimId; addr: Addr; data: Data; stren: OpStrength);
  var shimElem:ShimElemState;
  Begin
    shimElem := Shims[shim].state[addr];
    PopInstr(shim); -- CHECK Write perform immediately so no need to wait for CC to respond...
    ShimWriteCache(shim,Valid,data,shimElem.ts+1,addr);
    Assert (CCOpen()) "ShimWrite - too many messages";
    Send(WRITE,shim,0,data,addr,shimElem.ts+1,stren);
    if stren = SC then
      Shims[shim].pendingWSC := true;
    endif;
  End;

  -- Read value, or send RREQ to CC
  Procedure ShimRead(shim: ShimId; addr: Addr; stren: OpStrength);
  var shimElem:ShimElemState;
  Begin
    shimElem := Shims[shim].state[addr];

    if (shimElem.state != Valid) then
      Assert (CCOpen()) "ShimRead - too many messages";
      Send(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren);
    else
      UpdateVal(shim, shimElem.data);
      PopInstr(shim); -- CHECK
    endif;
  End; 

  -- Stop local reads until FRESP received
  Procedure ShimFence(shim: ShimId);
  Begin
    Shims[shim].fencePending := true;
    SendFence(FREQ,shim,0);
  End;

  -- CC: process messages -----------------------------------------------------
  Procedure CCReceive(msg:Message);
  Begin
    switch msg.mtype

    case WRITE:
      CC.cache[msg.addr].data := msg.data; -- always perform write
      CC.cache[msg.addr].ts := CC.cache[msg.addr].ts+1;

      -- send write to sharers
      Assert (NetworkOpen()) "CCReceive Write - too many messages";
      for sharer:ShimId do
        if (sharer != msg.src & CC.cache[msg.addr].sharers[sharer] = Y)
	      then
          Send(WRITE,0,sharer,msg.data,msg.addr,CC.cache[msg.addr].ts,msg.stren);
	      endif;
      endfor;
      
      -- If SC or first write, send write acknowledgement
      if msg.stren = SC | (CC.cache[msg.addr].sharers[msg.src] = N) then 
        Send(WRITE_ACK,0,msg.src,msg.data,msg.addr,CC.cache[msg.addr].ts,msg.stren);
      endif;

      -- add src to sharers
      CC.cache[msg.addr].sharers[msg.src] := Y;

    case RREQ:
      CC.cache[msg.addr].sharers[msg.src] := Y;    -- Add shim to sharers
      Assert (NetworkOpen()) "CCReceive RREQ - too many messages";
      Send(RRESP,0,msg.src,CC.cache[msg.addr].data,msg.addr,CC.cache[msg.addr].ts,msg.stren);

    case FREQ:
      Assert (NetworkOpen()) "CCReceive FREQ - too many messages";
      SendFence(FRESP,0,msg.src);

    else
      error "CC received invalid message type!";
    endswitch
  End;

  Function CheckReset(): boolean;
  Begin
    for s: ShimId do
      if Shims[s].active = true then
        return false;
      endif;
      if (NetCount[s] > 0) then
        return false;
      endif;
      for i := 0 to Shims[s].queue.QueueCnt-1 do
        if Shims[s].queue.Queue[i].pend = true then
          return false;
        endif;

      endfor;
      if Shims[s].queue.QueueInd < Shims[s].queue.QueueCnt then
        return false;
      endif;
    endfor;
    if NetCount[0] > 0 then
      return false;
    endif;
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

      For s:ShimId do
        CC.cache[a].sharers[s] := N;
        Shims[s].state[a].state := Invalid;
        undefine Shims[s].state[a].data;
        Shims[s].state[a].ts := 0;
        Shims[s].state[a].syncBit := true;
        Shims[s].queue.QueueCnt := 0;
        Shims[s].queue.QueueInd := 0;
        undefine Shims[s].queue.Queue;
        Shims[s].active := true;
        Shims[s].fencePending := false;
        Shims[s].pendingWSC := false;
      endfor;
    endfor;

    WriteInitialData();

    -- Net reset
    -- undefine Net;
    for dst: Node do
      undefine Net[dst];
      NetCount[dst] := 0;
    endfor;

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
  Begin
    instr := GetInstr(shim);
    
    if instr.access = load & CCOpen() then -- ignore cpu.pending for now...
      ShimRead(shim, instr.addr, instr.stren);
    endif;

    if instr.access = store & NetworkOpen() & CCOpen() then
      ShimWrite(shim, instr.addr, instr.data, instr.stren);
    endif;

    if instr.access = fence & CCOpen() then
      ShimFence(shim);
    endif;

  End;
-------------------------------------------------------------------------------
-- Rules
-------------------------------------------------------------------------------
  -- Message delivery
  ruleset n:Node do
    rule "deliver net msg"
      NetCount[n] > 0      
    ==> 
      if n = 0 
      then
        CCReceive(Net[n][0]);
      else
        ShimReceive(Net[n][0]);
      endif;
      PopMessage(n);
    endrule;
  endruleset;

  -- Execute litmus test
  -- NOTE: when fence in place, don't execute...
  ruleset shim:ShimId do
    rule "Execute litmus instruction" 
      Shims[shim].active = true
      & !Shims[shim].fencePending
      & !Shims[shim].pendingWSC
      & !Shims[shim].queue.Queue[Shims[shim].queue.QueueInd].pend
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



