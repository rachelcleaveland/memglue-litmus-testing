
-- MemGlue Protocol

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
const
-- MemGlue constants
  ShimCount: 4;      -- number of clusters / shims
  DataCount: 2;			 -- number of data values
  NetMax: 10;        -- 2*ShimCount+1;		-- max messages in the network (change?)
  AddrCount: 2;
  MaxTimestamp: 100; -- bound on message timestamps
  MaxMsgCount: 100;
  MaxWrite: 100;
  MaxFence: 100;     -- max number of fences sent to a shim
  MaxSeenSet: 5;     -- Maximum seen ids in seen set of each shim

-- MSI constants
  VAL_COUNT: 2;

  O_NET_MAX: 12;
  U_NET_MAX: 12;

  NrCaches: 4;

  InstrCount: 4;

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------
type
  ShimId: 1..ShimCount;   --+1;		-- For indexing into list of shims
  Addr: 0..AddrCount-1;
  Data: 0..DataCount;
  Timestamp: 0..MaxTimestamp;
  Node: 0..ShimCount; --+1;		-- This represents the CC plus the shims: CC = 0, Shims = 1..ShimCount+1
  MsgCount: 0..MaxMsgCount;
  FenceCnt: 0..MaxFence;
  WriteId: 0..MaxWrite;
  SeenIdx: 0..MaxSeenSet-1;
  QueueInd: 0..InstrCount+1;

  -- MSI dir + shim + cores
  Machines: 0..NrCaches+1;


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
    wCntr: WriteId;
    qInd: QueueInd;
    End;

  MSIMessageType: enum { 
    Fwd_GetM,
    Fwd_GetS,
    GetM,
    GetM_Ack_AD,
    GetM_Ack_D,
    GetS,
    GetS_Ack,
    Inv,
    Inv_Ack,
    PutM,
    PutS,
    Put_Ack,
    Upgrade,
    WB
  };

  MSIMessage: record
    adr: Addr;
    mtype: MSIMessageType;
    src: Machines;
    dst: Machines;
    acksExpected: 0..NrCaches+1;
    cl: Data;
  end;

  Buffer: record
    Queue: array[0..2] of MSIMessage;
    QueueInd: 0..2+1;
  end;

  s_cache: enum { 
    cache_I,
    cache_I_load,
    cache_I_load__Inv_I,
    cache_I_store,
    cache_I_store_GetM_Ack_AD,
    cache_I_store_GetM_Ack_AD__Fwd_GetM_I,
    cache_I_store_GetM_Ack_AD__Fwd_GetS_S,
    cache_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I,
    cache_I_store__Fwd_GetM_I,
    cache_I_store__Fwd_GetS_S,
    cache_I_store__Fwd_GetS_S__Inv_I,
    cache_M,
    cache_M_evict,
    cache_M_evict_Fwd_GetM,
    cache_S,
    cache_S_evict,
    cache_S_store,
    cache_S_store_GetM_Ack_AD,
    cache_S_store_GetM_Ack_AD__Fwd_GetS_S,
    cache_S_store__Fwd_GetS_S
  };

  s_shim: enum { 
    shim_I,
    shim_I_load,
    shim_I_load__Inv_I,
    shim_I_store,
    shim_I_store_GetM_Ack_AD,
    shim_I_store_GetM_Ack_AD__Fwd_GetM_I,
    shim_I_store_GetM_Ack_AD__Fwd_GetS_S,
    shim_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I,
    shim_I_store__Fwd_GetM_I,
    shim_I_store__Fwd_GetS_S,
    shim_I_store__Fwd_GetS_S__Inv_I,
    shim_M,
    shim_M_evict,
    shim_M_evict_Fwd_GetM,
    shim_S,
    shim_S_evict,
    shim_S_store,
    shim_S_store_GetM_Ack_AD,
    shim_S_store_GetM_Ack_AD__Fwd_GetS_S,
    shim_S_store__Fwd_GetS_S
  };

  s_directory: enum { 
    directory_I,
    directory_M,
    directory_M_GetS,
    directory_S
  };

  -- NETOrdered: array[Node] of array[0..NetMax-1] of Message;
  -- NETOrderedCount: array[Node] of 0..NetMax;
  NETUnordered: array[Node] of multiset[NetMax] of Message; -- also used for partially ordered, with some extra checks in PopMessage

  CacheState: enum { Invalid, Valid };

  Sharers: enum { Y, N };

  CCElemLastWrite: 
    Record
    writeId: WriteId;     -- write id of the last write to the address
    stren: OpStrength;    -- strength of the last write
    seenId: WriteId;      -- what the last write to the address saw
    wCntr: WriteId;       -- number of writes to the address from the shim that have reached the CC
    End;

  CCElemLastWritePerAddr: array[Addr] of CCElemLastWrite;

  SeenIdsElement: 
    Record
      seenIds: CCElemLastWritePerAddr;
      seenPerShim: WriteId;
    End;


  ShimElemState:
    Record
    state: CacheState;
    data: Data;
    ts: Timestamp;
    localWriteCntr: 0..MaxMsgCount;
    syncBit: boolean;
    rfBuf: 0..NetMax;

    acksExpected: 0..NrCaches+1;  -- number of acks needed before we can commit MemGlue message
    acksReceived: 0..NrCaches+1;  -- number of acks we've received from cores. Resets on each new GetM to the dir.
    protoState: s_shim;           -- Shim state relative to the MSI protocol
    Defermsg: Buffer;             -- Messages waiting to be sent until enough acks are received

    End;

  CCElemState:
    Record
    data: Data;
    ts: Timestamp;
    sharers: array[ShimId] of Sharers;
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
  OBJSET_cache: 2..NrCaches+1;

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
    core: OBJSET_cache;
    End;

  FifoQueue: 
    Record
    Queue: array[0..InstrCount] of Instr;
    QueueInd: QueueInd;
    QueueCnt: QueueInd;
    End;

  MSIMemGlueMsg: -- unused, developed to be the datatype in the
  -- queue in ShimMsgQueue, but now I no longer want to buffer MSI messages
    Record
    mtype: enum { MSIMsg, MemGlueMsg };
    msiMsg: MSIMessage;
    memglueMsg: Message;
    End;

  ShimMsgQueue:
    Record
    Queue: array[0..NetMax] of Message;
    QueueCnt: 0..NetMax+1;
    End;

  ---------------------------------
  PendingStrens: array[OBJSET_cache] of OpStrength;

  Shim:
    Record
    state: ShimCache;
    fencePending: boolean;
    fencesPending: array[OBJSET_cache] of boolean;
    fences: array[0..NrCaches] of OBJSET_cache; 
    fencesPendingCnt: 0..NetMax;
    writeSCsPending: array[OBJSET_cache] of boolean;
    writeSCs: array[0..NrCaches] of OBJSET_cache;
    writeSCsPendingCnt: 0..NetMax;
    buf: MsgBuffer;
    bufCnt: 0..NetMax;
    icnt: MsgCount;
    ocnt: MsgCount;
    fenceCnt: FenceCnt;
    seenId: WriteId;
    seenSet: SeenSet;
    seenSetBuf: SeenSet;
    seenSize: SeenIdx;
    seenSizeBuf: SeenIdx;
    pendingStrens: PendingStrens;

    ToFromMemGlue: ShimMsgQueue;
    TFMGPending: boolean;
    queue: FifoQueue;   -- queue of instructions from the cluster to be performed

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
    seenIds: SeenIds;
    End;

  ShimType: array[ShimId] of Shim;

-- MSI types



  --OBJSET_cache: 2..NrCaches+1; -- declared before shims

  PossibleSharers: 1..NrCaches+1;

  --Machines: 0..NrCaches+1;
    -- 0 = directory
    -- 1 = shim 
    -- 2..NrCaches+1 are the cores

  v_NrCaches_OBJSET_cache: array[PossibleSharers] of Sharers; -- sharers, stored at directory
  cnt_v_NrCaches_OBJSET_cache: 0..NrCaches+1;



  FIFO: record
    Queue: array[0..1] of MSIMessage;
    QueueInd: 0..1+1;
  end;

  MSHR: record
    Valid: boolean;
    Issued: boolean;
    core: Machines;
  end;

  ENTRY_cache: record
    State: s_cache;
    Defermsg: Buffer;
    Perm: PermissionType;
    cl: Data;
    acksReceived: 0..NrCaches+1;
    acksExpected: 0..NrCaches+1;
  end;

  ENTRY_directory: record
    State: s_directory;
    Defermsg: Buffer;
    Perm: PermissionType;
    cl: Data;
    cache: v_NrCaches_OBJSET_cache; -- sharers
    owner: Machines;
    mshr: MSHR;
  end;

  MACH_cache: record
    CL: array[Addr] of ENTRY_cache;
    queue: FifoQueue;
    active: boolean;
  end;

  MACH_directory: record
    CL: array[Addr] of ENTRY_directory;
  end;

  OBJ_cache: array[OBJSET_cache] of MACH_cache;

  OBJ_directory: MACH_directory;

  OBJ_Ordered: array[Machines] of array[0..O_NET_MAX-1] of MSIMessage;
  OBJ_Orderedcnt: array[Machines] of 0..O_NET_MAX;
  OBJ_Unordered: array[Machines] of multiset[U_NET_MAX] of MSIMessage;

  OBJ_OrderedCl: array[ShimId] of array[Machines] of array[0..O_NET_MAX-1] of MSIMessage;
  OBJ_OrderedcntCl: array[ShimId] of array[Machines] of 0..O_NET_MAX;
  OBJ_UnorderedCl: array[ShimId] of array[Machines] of multiset[U_NET_MAX] of MSIMessage;

  ShimsToClusters: array[ShimId] of array[0..O_NET_MAX-1] of MSIMessage;
  ShimsToClustersLens: array[ShimId] of 0..O_NET_MAX-1;

  OBJ_FIFO: array[Machines] of FIFO;

  OBJ_cacheSet: array[ShimId] of OBJ_cache;
  OBJ_directorySet: array[ShimId] of OBJ_directory;

----------------------------------------------------------------------
-- Variables
----------------------------------------------------------------------
var
  CC: CCMachine;
  Shims: ShimType;
  NetU: NETUnordered;
  wIdCounter: WriteId;

  deliverMsgHack: Message;

  i_caches: OBJ_cacheSet;
  i_directories: OBJ_directorySet;

  fwd: OBJ_OrderedCl;
  cnt_fwd: OBJ_OrderedcntCl;
  resp: OBJ_UnorderedCl;
  req: OBJ_UnorderedCl;

  shimNet: ShimsToClusters;
  cnt_shimNet: ShimsToClustersLens;

  clToShimBuf: ShimsToClusters;
  cnt_clToShimBuf: ShimsToClustersLens;

----------------------------------------------------------------------
-- Procedures
----------------------------------------------------------------------

-- MSI Infrastructure Functions

  -- Queue functions
  function PushQueue(var f: OBJ_FIFO; n:Machines; msg:MSIMessage): boolean;
  begin
    alias p:f[n] do
    alias q: p.Queue do
    alias qind: p.QueueInd do

      if (qind<=1) then
        q[qind]:=msg;
        qind:=qind+1;
        return true;
      endif;

      return false;

    endalias;
    endalias;
    endalias;
  end;

  function GetQueue(var f: OBJ_FIFO; n:Machines): MSIMessage;
  var
    msg: MSIMessage;
  begin
    alias p:f[n] do
    alias q: p.Queue do
    undefine msg;

    if !isundefined(q[0].mtype) then
      return q[0];
    endif;

    return msg;
    endalias;
    endalias;
  end;

  procedure PopQueue(var f: OBJ_FIFO; n:Machines);
  begin
    alias p:f[n] do
    alias q: p.Queue do
    alias qind: p.QueueInd do


    for i := 0 to qind-1 do
        if i < qind-1 then
          q[i] := q[i+1];
        else
          undefine q[i];
        endif;
      endfor;
      qind := qind - 1;

    endalias;
    endalias;
    endalias;
  end;

  -- Litmus test handling functions
  -- Update output of litmus test load 
  Procedure UpdateVal(s: ShimId; m: OBJSET_cache; data: Data); --; qInd: QueueInd);
  Begin
    alias p: i_caches[s][m].queue do
    alias q: p.Queue do
    alias qcnt: p.QueueCnt do
    alias qInd: p.QueueInd do

    if (qInd) < qcnt & !isundefined(q[qInd].access) then
      q[qInd].data := data;
      q[qInd].pend := false;
    endif;

    endalias;
    endalias;
    endalias;
    endalias;
  End;


  -- Remove litmus test instruction 
  Procedure PopInstr(s: ShimId; m: OBJSET_cache);
  Begin
    alias sQ: i_caches[s][m].queue.Queue do
    alias QInd: i_caches[s][m].queue.QueueInd do
    alias QCnt: i_caches[s][m].queue.QueueCnt do

    QInd := QInd + 1;
    if QInd = QCnt then
      i_caches[s][m].active := false;
    else 
      if isundefined(sQ[QInd].access) then -- why is this here? Why would it be undefined?
        i_caches[s][m].active := false;
      endif;
    endif;
      

    endalias;
    endalias;
    endalias;
  End;

  
  -- Fetch shim's next litmus test instructions
  Function GetInstr(s: ShimId; m: OBJSET_cache): Instr;
  var instr: Instr;
  Begin
    alias sQ: i_caches[s][m].queue.Queue do
    alias QInd: i_caches[s][m].queue.QueueInd do
    alias QCnt: i_caches[s][m].queue.QueueCnt do    
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

  -- MSIMessage creation functions

  function Request(adr: Addr; mtype: MSIMessageType; src: Machines; dst: Machines) : MSIMessage;
  var msg: MSIMessage;
  begin
    msg.adr := adr;
    msg.mtype := mtype;
    msg.src := src;
    msg.dst := dst;
    msg.acksExpected := undefined;
    msg.cl := undefined;
    return msg;
  end;

  function Ack(adr: Addr; mtype: MSIMessageType; src: Machines; dst: Machines) : MSIMessage;
  var msg: MSIMessage;
  begin
    msg.adr := adr;
    msg.mtype := mtype;
    msg.src := src;
    msg.dst := dst;
    msg.acksExpected := undefined;
    msg.cl := undefined;
    return msg;
  end;

  function Resp(adr: Addr; mtype: MSIMessageType; src: Machines; dst: Machines; cl: Data) : MSIMessage;
  var msg: MSIMessage;
  begin
    msg.adr := adr;
    msg.mtype := mtype;
    msg.src := src;
    msg.dst := dst;
    msg.acksExpected := undefined;
    msg.cl := cl;
    return msg;
  end;

  function RespAck(adr: Addr; mtype: MSIMessageType; src: Machines; dst: Machines; cl: Data; acksExpected: 0..NrCaches) : MSIMessage;
  var msg: MSIMessage;
  begin
    msg.adr := adr;
    msg.mtype := mtype;
    msg.src := src;
    msg.dst := dst;
    msg.acksExpected := acksExpected;
    msg.cl := cl;
    return msg;
  end;


  -- Sending functions

  procedure Send_fwd(s: ShimId; msg:MSIMessage);
    Assert(cnt_fwd[s][msg.dst] < O_NET_MAX) "Too many messages";
    fwd[s][msg.dst][cnt_fwd[s][msg.dst]] := msg;
    cnt_fwd[s][msg.dst] := cnt_fwd[s][msg.dst] + 1;
  end;

  procedure Pop_fwd(s: ShimId; n:Machines);
  begin
    Assert (cnt_fwd[s][n] > 0) "Trying to advance empty Q";
    for i := 0 to cnt_fwd[s][n]-1 do
      if i < cnt_fwd[s][n]-1 then
        fwd[s][n][i] := fwd[s][n][i+1];
      else
        undefine fwd[s][n][i];
      endif;
    endfor;
    cnt_fwd[s][n] := cnt_fwd[s][n] - 1;
  end;


  procedure Send_resp(s: ShimId; msg:MSIMessage;);
    Assert (MultiSetCount(i:resp[s][msg.dst], true) < U_NET_MAX) "Too many messages";
    MultiSetAdd(msg, resp[s][msg.dst]);
  end;

  procedure Send_req(s: ShimId; msg:MSIMessage;);
    Assert (MultiSetCount(i:req[s][msg.dst], true) < U_NET_MAX) "Too many messages";
    MultiSetAdd(msg, req[s][msg.dst]);
  end;


  procedure Multicast_fwd_v_NrCaches_OBJSET_cache(s: ShimId; var msg: MSIMessage; dst:v_NrCaches_OBJSET_cache;);
  begin
      for sharer:PossibleSharers do 
        if sharer != msg.src & dst[sharer] = Y then
          msg.dst := sharer;
          Send_fwd(s,msg);
        endif;
      endfor;
  end;

  procedure Multicast_resp_v_NrCaches_OBJSET_cache(s: ShimId; var msg: MSIMessage; dst:v_NrCaches_OBJSET_cache;);
  begin
      for sharer:PossibleSharers do
        if sharer != msg.src & dst[sharer] = Y then
          msg.dst := sharer;
          Send_resp(s,msg);
        endif;
      endfor;
  end;

  procedure Multicast_req_v_NrCaches_OBJSET_cache(s: ShimId; var msg: MSIMessage; dst:v_NrCaches_OBJSET_cache;);
  begin
      for sharer:PossibleSharers do
        if sharer != msg.src & dst[sharer] = Y then
          msg.dst := sharer;
          Send_req(s,msg);
        endif;
      endfor;
  end;

  procedure SendShimNet(shim: ShimId; addr: Addr; mtype: MSIMessageType);
  var msg: MSIMessage;
  Begin
    assert(cnt_shimNet[shim] < O_NET_MAX) "Too many messages shim to cluster";

    msg := Request(addr,GetM,1,0); -- Inside cluster, shim always has id 1

    Shims[shim].state[addr].acksReceived := 0;

    shimNet[shim][cnt_shimNet[shim]] := msg;
    cnt_shimNet[shim] := cnt_shimNet[shim] + 1;
  End;

  procedure PopShimNet(s: ShimId);
  Begin
    Assert(cnt_shimNet[s] > 0) "No message to pop";
    for i := 0 to cnt_shimNet[s]-1 do
      if (i < cnt_shimNet[s]-1)
      then
        shimNet[s][i] := shimNet[s][i+1];
      else
        undefine shimNet[s][i];
      endif;
    endfor;
    cnt_shimNet[s] := cnt_shimNet[s]-1;
  End;

  -- .add()
  procedure AddElement_v_NrCaches_OBJSET_cache(var sv:v_NrCaches_OBJSET_cache; n:PossibleSharers);
  begin
    sv[n] := Y;
  end;

  -- .del()
  procedure RemoveElement_v_NrCaches_OBJSET_cache(var sv:v_NrCaches_OBJSET_cache; n:PossibleSharers);
  begin
    sv[n] := N;
  end;

  -- .clear()
  procedure ClearVector_v_NrCaches_OBJSET_cache(var sv:v_NrCaches_OBJSET_cache;);
  begin
    for sharer:PossibleSharers do
      sv[sharer] := N;
    endfor;
  end;

  -- .contains()
  function IsElement_v_NrCaches_OBJSET_cache(var sv:v_NrCaches_OBJSET_cache; n:PossibleSharers) : boolean;
  begin
    if sv[n] = Y then 
      return true;
    endif;
    return false;
  end;

  -- .empty()
  function HasElement_v_NrCaches_OBJSET_cache(var sv:v_NrCaches_OBJSET_cache; n:PossibleSharers) : boolean;
  begin
    if sv[n] = Y then
      return true;
    endif;
    return false;
  end;

  -- .count()
  function VectorCount_v_NrCaches_OBJSET_cache(var sv:v_NrCaches_OBJSET_cache) : cnt_v_NrCaches_OBJSET_cache;
  var cnt: cnt_v_NrCaches_OBJSET_cache;
  begin
      cnt := 0;
      for i:PossibleSharers do
        if sv[i] = Y then cnt := cnt + 1;
        endif;
      endfor;
      return cnt;
  end;



  procedure i_cache_Defermsg(s: ShimId; msg:MSIMessage; adr: Addr; m:PossibleSharers);
  begin
    alias cle: i_caches[s][m].CL[adr] do
    alias q: cle.Defermsg.Queue do
    alias qind: cle.Defermsg.QueueInd do

    if (qind<=2) then
        q[qind]:=msg;
        qind:=qind+1;
      endif;

    endalias;
    endalias;
    endalias;
  end;

  procedure i_cache_SendDefermsg(s: ShimId; adr: Addr; m:PossibleSharers);
  begin
    alias cle: i_caches[s][m].CL[adr] do
    alias q: cle.Defermsg.Queue do
    alias qind: cle.Defermsg.QueueInd do

    for i := 0 to qind-1 do
        --i_cache_Updatemsg(q[i], adr, m);
        Send_resp(s,q[i]);
          undefine q[i];
      endfor;

    qind := 0;

    endalias;
    endalias;
    endalias;
  end;

  procedure Shim_Defermsg(s: ShimId; msg:MSIMessage; adr: Addr);
  begin
    alias cle: Shims[s].state[adr] do
    alias q: cle.Defermsg.Queue do
    alias qind: cle.Defermsg.QueueInd do

    if (qind<=2) then
        q[qind]:=msg;
        qind:=qind+1;
      endif;

    endalias;
    endalias;
    endalias;
  end;

  procedure Shim_SendDefermsg(s: ShimId; adr: Addr);
  begin
    alias cle: Shims[s].state[adr] do
    alias q: cle.Defermsg.Queue do
    alias qind: cle.Defermsg.QueueInd do

    for i := 0 to qind-1 do
        --i_cache_Updatemsg(q[i], adr, m);
        Send_resp(s,q[i]);
          undefine q[i];
      endfor;

    qind := 0;

    endalias;
    endalias;
    endalias;
  end;

  -- Message handling between shims and directory
  -- ReadHandlerShimToCluster is part of the directory?
  procedure ReadHandlerShimToCluster(shim: ShimId; data: Data; addr: Addr);
  var newMsg: MSIMessage;
  Begin
    alias i_directory: i_directories[shim] do
    Assert (i_directory.CL[addr].mshr.Valid) "Bad read sent to cluster from shim";

    AddElement_v_NrCaches_OBJSET_cache(i_directory.CL[addr].cache,i_directory.CL[addr].mshr.core);
    newMsg := Resp(addr,GetS_Ack,0,i_directory.CL[addr].mshr.core,data);
    Send_resp(shim,newMsg);
    i_directory.CL[addr].State := directory_S;
    i_directory.CL[addr].cl := data;
    i_directory.CL[addr].Perm := none;
    --AddElement_v_NrCaches_OBJSET_cache(i_directory.CL[msg.addr].cache,1); -- 1 = shim

    i_directory.CL[addr].mshr.Valid := false;
    endalias;
  End;


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


  Procedure SendWrite(
                 mtype:MessageType;
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
    msg.wCntr := wCntr;

    msg.writeId := wid;
    msg.seenId := sid;

    MultiSetAdd(msg, NetU[dst]);

  End;

  Procedure SendRead(mtype:MessageType;
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
                 wCntr:WriteId;
                 qind:QueueInd;
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
    msg.wCntr := wCntr;

    msg.writeId := wid;
    msg.seenId := sid;

    msg.qInd := qind;

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

  Procedure ShimPushFifoMemGlue(s: ShimId; msg: Message);
  Begin
  alias qCnt: Shims[s].ToFromMemGlue.QueueCnt do
    --msgNew.mtype := MemGlueMsg;
    --msgNew.memglueMsg := msg;
    --undefine msgNew.msiMsg;

    Shims[s].ToFromMemGlue.Queue[qCnt] := msg;
    qCnt := qCnt + 1;
  endalias;
  End;

  /*
  Procedure ShimPushFifoMSI(s: ShimId; msg: MSIMessage);
  var msgNew: MSIMemGlueMsg;
  Begin
    msgNew.mtype := MSIMsg;
    msgNew.msiMsg := msg;
    undefine msgNew.memglueMsg;

    Shims[s].ToFromMemGlue.Queue[qCnt] := msgNew;
    qCnt := qCnt + 1;
  endalias;
  End;
  */ 

  Procedure ShimPushFifoFront(s: ShimId; msg: Message);
  Begin
  alias qCnt: Shims[s].ToFromMemGlue.QueueCnt do
  alias q: Shims[s].ToFromMemGlue.Queue do
    for i := 0 to qCnt-1 do
      q[qCnt-1-i+1] := q[qCnt-1-i];
    endfor;
    q[0] := msg;
    qCnt := qCnt + 1;

  endalias;
  endalias;
  End;

  Procedure ShimPopFifo(s: ShimId);
  Begin
  alias qCnt: Shims[s].ToFromMemGlue.QueueCnt do
  alias q: Shims[s].ToFromMemGlue.Queue do
    Assert(qCnt > 0) "Can't pop from empty buffer";
    for i := 0 to qCnt-1 do
      if (i < qCnt-1) then
        q[i] := q[i+1];
      else
        undefine q[i];
      endif;
    endfor;
    qCnt := qCnt - 1;

  endalias;
  endalias;
  End;

  Procedure CCPushBuf(msg:Message; status:0..1);
  var bufEntry: BufEntry;
  Begin
    Assert(CC.bufCnt < NetMax) "Too many messages in shim buffer";
    bufEntry.msg := msg;
    bufEntry.status := status;
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


  Procedure ShimPopFence(s:Node);
  Begin
    Assert(Shims[s].fencesPendingCnt > 0) "No fence to pop";

    for i := 0 to Shims[s].fencesPendingCnt-1 do
      if (i < Shims[s].fencesPendingCnt-1)
      then
        Shims[s].fences[i] := Shims[s].fences[i+1];
      else
        undefine Shims[s].fences[i];
      endif;
    endfor;
    Shims[s].fencesPendingCnt := Shims[s].fencesPendingCnt-1;
  End;

  Procedure ShimPopWriteSC(s:Node);
  Begin
    Assert(Shims[s].writeSCsPendingCnt > 0) "No write SC to pop";

    for i := 0 to Shims[s].writeSCsPendingCnt-1 do
      if (i < Shims[s].writeSCsPendingCnt-1)
      then
        Shims[s].writeSCs[i] := Shims[s].writeSCs[i+1];
      else
        undefine Shims[s].writeSCs[i];
      endif;
    endfor;
    Shims[s].writeSCsPendingCnt := Shims[s].writeSCsPendingCnt-1;
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

  -- Called after a write has accepted at the shim and needs to 
  -- be sent to the directory
  Procedure ShimUpdateOnWrite(s: ShimId; msg: Message);
  Begin
    if !(i_directories[s].CL[msg.addr].mshr.Valid) then 
      SendShimNet(s,msg.addr,GetM); 
    else 
      ReadHandlerShimToCluster(s,msg.data,msg.addr);
    endif;
  End;

  Function IsStable(state : s_shim) : boolean;
  Begin
    return state = shim_M | state = shim_S | state = shim_I 
  End;



  Procedure MsgHandlerMemGlueToShim(s: ShimId; msg: Message);
  Begin
    alias state: Shims[s].state[msg.addr].protoState do
    Assert(state = shim_M | state = shim_S | state = shim_I) "Cannot handle messages in transient state";
    switch msg.mtype
    case WRITE:
      switch state
      -- Stable states: process message immediately
      case shim_M:
        -- Do nothing: if queue is clear, the shim data should
        -- already be up to date!
        --ShimPopFifo(s);
      
      case shim_S:
        state := shim_S_store;
        ShimUpdateOnWrite(s,msg);
      case shim_I:
        state := shim_I_store;
        ShimUpdateOnWrite(s,msg);
      else -- otherwise, queue it up. Is this possible? I think the queue would be nonempty
        error "Dispatched instruction while another is executing"
      endswitch;

    case RRESP:
      ReadHandlerShimToCluster(s,msg.data,msg.addr);
      --ShimPopFifo(s);           

    else
      error "Invalid message type sent MemGlue to MSI";
    endswitch;
    endalias;
  End;


  -- SHIM: outgoing messages
  -- Write value, or send WRITE to CC
  Procedure ShimWrite(shim: ShimId; addr: Addr; data: Data; stren: OpStrength; core: OBJSET_cache);
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
    SendWrite(WRITE,shim,0,data,addr,shimElem.ts+1,stren,Shims[shim].ocnt,0,0,MaxSeenIdBoth(shim),0);
    Shims[shim].ocnt := Shims[shim].ocnt + 1;
    if stren = SC then
      --SendFence(FREQ,shim,0,SC,Shims[shim].ocnt);
      --Shims[shim].fencesPending[core] := true;
      --Shims[shim].fences[Shims[shim].fencesPendingCnt] := core;
      --Shims[shim].fencesPendingCnt := Shims[shim].fencesPendingCnt + 1;
      Shims[shim].writeSCsPending[core] := true;
      Shims[shim].writeSCs[Shims[shim].writeSCsPendingCnt] := core;
      Shims[shim].writeSCsPendingCnt := Shims[shim].writeSCsPendingCnt + 1;
    endif;
  End;

  -- Intuition: the LLC will wait to keep executing requests until after a read
  -- request has come back, so there will never be pending reads like this
  Function CheckPendingRead(shim: ShimId): boolean;
  Begin
    return true;
  End;

  Function AcceptRRESPEarly(shim: ShimId; msg: Message): boolean;
  Begin
    Assert (msg.mtype = RRESP) "Wrong message at AcceptRRESP";
    Assert (msg.cnt > Shims[shim].icnt) "Wrong message at AcceptRRESP";

    return msg.ts <= Shims[shim].state[msg.addr].ts;
  End;

  -- Read value, or send RREQ to CC
  Procedure ShimRead(shim: ShimId; addr: Addr; stren: OpStrength; qInd: QueueInd);
  var shimElem:ShimElemState;
  var found:boolean;
  var bufData:Data;
  var bufTS:Timestamp;
  var bufMsg: Message;
  var bufIdx: 0..NetMax;
  var bufWId: WriteId;
  var msg:Message;
  Begin
  shimElem := Shims[shim].state[addr];
  if shimElem.state = Invalid then
    Assert (shimElem.syncBit) "SyncBit improperly set";
  endif;

  if stren = RLX then
    found := false;
    bufTS := shimElem.ts;
    bufIdx := 0;
    for i := 0 to Shims[shim].bufCnt - 1 do -- attempt to read from buffer for data -- CHECK: does this need to be more fine-grained? Check ts?
      bufMsg := Shims[shim].buf[i].msg;
      if bufMsg.mtype = WRITE & bufMsg.addr = addr & bufMsg.ts > bufTS & bufMsg.wCntr = shimElem.localWriteCntr then
        found := true;
        bufData := bufMsg.data;
        bufTS := bufMsg.ts;
        bufIdx := i;
        bufWId := bufMsg.writeId;
      endif;
    endfor;
    if found then 
      if (!Shims[shim].buf[bufIdx].rf) then
        Shims[shim].buf[bufIdx].rf := true;
        Shims[shim].state[addr].rfBuf := Shims[shim].state[addr].rfBuf + 1;
      endif;
      AddSeenIdShimBuf(shim,bufWId);

      ReadHandlerShimToCluster(shim,bufData,addr);

    else
      if (shimElem.state = Valid & CheckPendingRead(shim)) -- & Shims[shim].bufCnt = 0) -- TODO: make this more fine-grained! If buf only has messages of other addresses, we can read from the cache
      then
        ReadHandlerShimToCluster(shim,bufData,addr);
      else
        Assert (CCOpen()) "ShimRead - too many messages";
        SendRead(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren,Shims[shim].ocnt,0,0,0,0,qInd);
        Shims[shim].ocnt := Shims[shim].ocnt + 1;
      endif; 
      
    endif;
  else -- Read SC and ACQ treated the same way
    if (shimElem.state = Valid & CheckPendingRead(shim)) -- TODO: make this more fine-grained! If buf only has messages of other addresses, we can read from the cache
    then
      ReadHandlerShimToCluster(shim,bufData,addr);
    else
      Assert (CCOpen()) "ShimRead - too many messages";
      SendRead(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren,Shims[shim].ocnt,0,0,0,0,qInd);
      Shims[shim].ocnt := Shims[shim].ocnt + 1;
    endif;   
  --else
    -- Always send read SC's through the CC (don't read from cache)
  --  Assert (CCOpen()) "ShimRead - too many messages";
  --  SendRead(RREQ,shim,0,shimElem.data,addr,shimElem.ts,stren,Shims[shim].ocnt,0,0,0,0);
  --  Shims[shim].ocnt := Shims[shim].ocnt + 1;
  --endif;          

  endif;

  End; 

  -- Stop local reads until FRESP received
  Procedure ShimFence(shim: ShimId; core: OBJSET_cache);
  Begin
    Shims[shim].fencesPending[core] := true;
    Shims[shim].fences[Shims[shim].fencesPendingCnt] := core;
    Shims[shim].fencesPendingCnt := Shims[shim].fencesPendingCnt + 1;
    SendFence(FREQ,shim,0,SC,Shims[shim].ocnt);
    Shims[shim].ocnt := Shims[shim].ocnt + 1;
  End;



  Procedure IssueShimInstr(shim: ShimId);
  var instr: Instr;      
  var qind: QueueInd;
  Begin
    qind := Shims[shim].queue.QueueInd;
    instr := Shims[shim].queue.Queue[qind];
    Shims[shim].queue.Queue[qind].pend := true;
    
    if instr.access = load & CCOpen() then -- ignore cpu.pending for now...
      ShimRead(shim, instr.addr, instr.stren, qind);
    endif;

    if instr.access = store & NetworkOpen() & CCOpen() then
      ShimWrite(shim, instr.addr, instr.data, instr.stren, instr.core);
      Shims[shim].queue.Queue[qind].pend := false;
    endif;

    if instr.access = fence & CCOpen() then
      ShimFence(shim,instr.core);
      Shims[shim].queue.Queue[qind].pend := false;
    endif;

    Shims[shim].queue.QueueInd := Shims[shim].queue.QueueInd + 1;

  End;

  Function Stall(shim: ShimId) : boolean;
  var instr : Instr;
  Begin
    if Shims[shim].fencePending = true then
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

  Procedure TryIssueShimInstr(shim: ShimId;);
  Begin
    if (Shims[shim].queue.QueueInd < Shims[shim].queue.QueueCnt) then
      if !Shims[shim].queue.Queue[Shims[shim].queue.QueueInd].pend  
        & !Stall(shim) then
        IssueShimInstr(shim);
      endif;
    endif;
  End;

  Procedure WriteToShim(shim: ShimId; stren: OpStrength; addr: Addr; data: Data; core: OBJSET_cache); 
  var instr: Instr;
  Begin
    instr.access := store;
    instr.stren := stren;
    instr.addr := addr;
    instr.data := data;
    instr.core := core;

    Shims[shim].queue.Queue[Shims[shim].queue.QueueCnt] := instr;
    Shims[shim].queue.Queue[Shims[shim].queue.QueueCnt].pend := false;
    Shims[shim].queue.QueueCnt := Shims[shim].queue.QueueCnt + 1;

    TryIssueShimInstr(shim);

  End;

  Procedure ReadToShim(shim: ShimId; stren: OpStrength; addr: Addr);
  var instr: Instr;
  Begin
    instr.access := load;
    instr.stren := stren;
    instr.addr := addr;
    instr.data := undefined;

    Shims[shim].queue.Queue[Shims[shim].queue.QueueCnt] := instr;
    Shims[shim].queue.Queue[Shims[shim].queue.QueueCnt].pend := false;
    Shims[shim].queue.QueueCnt := Shims[shim].queue.QueueCnt + 1;

    TryIssueShimInstr(shim);

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
        MsgHandlerMemGlueToShim(msg.dst,msg);
        Shims[msg.dst].TFMGPending := true;
      else
        ShimIncrTS(msg.dst,addr); 
      endif;
      if (inOrder) then
        AddSeenId(msg.dst,msg.writeId);
      else 
        AddSeenIdShimBuf(msg.dst,msg.writeId);
      endif;


    case WRITE_ACK:
      addr := msg.addr;
      data := msg.data;
      ts := msg.ts;
      shimElem := Shims[msg.dst].state[msg.addr];
      -- If the write is a synchronizing write, handle differently
      if (shimElem.syncBit) then
        if (shimElem.localWriteCntr > 1) then
          data := shimElem.data;
        endif;
        ShimWriteCache(msg.dst,Valid,data,ts+shimElem.localWriteCntr-1,addr);
        Shims[msg.dst].state[msg.addr].syncBit := false;
      endif;

      if (Shims[msg.dst].writeSCsPendingCnt > 0 
          & Shims[msg.dst].writeSCsPending[Shims[msg.dst].writeSCs[0]]) then
        Shims[msg.dst].writeSCsPending[Shims[msg.dst].writeSCs[0]] := false;
        for i := 0 to AddrCount - 1 do
          i_cache_SendDefermsg(msg.dst, i, Shims[msg.dst].writeSCs[0]);
        endfor;
        ShimPopWriteSC(msg.dst);
      endif;

    case RRESP:
      addr := msg.addr;
      data := msg.data;
      ts := msg.ts;
      shimElem := Shims[msg.dst].state[msg.addr];
      -- If the read is synchronizing, handle differently
      if (shimElem.syncBit) then
        if (shimElem.localWriteCntr > 0) then
          data := shimElem.data;
        endif;
        ShimWriteCache(msg.dst,Valid,data,ts+shimElem.localWriteCntr,addr);
        Shims[msg.dst].state[msg.addr].syncBit := false;        
      else
        if (shimElem.ts <= msg.ts) then
          ShimWriteCache(msg.dst,Valid,data,ts,addr);
        endif;
      endif;

      MsgHandlerMemGlueToShim(msg.dst,msg);

      if (inOrder) then
        AddSeenId(msg.dst,msg.writeId);
      else
        AddSeenIdShimBuf(msg.dst,msg.writeId);
      endif;

      Shims[msg.dst].queue.Queue[msg.qInd].pend := false;
      TryIssueShimInstr(msg.dst);
      
    case FREQ:
      Shims[msg.dst].fenceCnt := Shims[msg.dst].fenceCnt + 1;

    case FRESP:
      Assert(Shims[msg.dst].fencesPendingCnt > 0);
      Assert(Shims[msg.dst].fencesPending[Shims[msg.dst].fences[0]] = true);

      Shims[msg.dst].fencesPending[Shims[msg.dst].fences[0]] := false;
      ShimPopFence(msg.dst);

      TryIssueShimInstr(msg.dst);

    else
      error "Shim received invalid message type!";

    endswitch;

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
          SendWrite(WRITE,0,sharer,msg.data,msg.addr,CC.cache[msg.addr].ts,msg.stren,
               CC.cntrs[sharer].ocnt,CC.fenceCnts[sharer],
               CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId,
               CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].seenId,
               CC.seenIds[sharer].seenIds[msg.addr].wCntr); -- Always send seen and write ids...
	        CC.cntrs[sharer].ocnt := CC.cntrs[sharer].ocnt + 1;
	      endif;
      endfor;

      -- if a shim is "checking in" or write is SC, send them a write update to sync timestamps
      -- NOTE: the only fields that will be used from this message are the 
      -- timestamp, data, and ocnt, the other fields are not considered. 
      if msg.stren = SC | CC.cache[msg.addr].sharers[msg.src] = N then
        SendWrite(WRITE_ACK,0,msg.src,msg.data,msg.addr,CC.cache[msg.addr].ts,msg.stren,
             CC.cntrs[msg.src].ocnt,CC.fenceCnts[msg.src],
             CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].writeId,
             CC.seenIds[CC.cache[msg.addr].lastWriteShim].seenIds[msg.addr].seenId,
             CC.seenIds[msg.src].seenIds[msg.addr].wCntr);
	        CC.cntrs[msg.src].ocnt := CC.cntrs[msg.src].ocnt + 1;
      endif;
      -- add src to sharers
      CC.cache[msg.addr].sharers[msg.src] := Y;

    case RREQ:
      CC.cache[msg.addr].sharers[msg.src] := Y;    -- Add shim to sharers
      Assert (NetworkOpen()) "CCReceive RREQ - too many messages";
      -- Always send along write id and seen id
      if CC.cache[msg.addr].lastWriteShim = 0 then -- if reading from initial data, last write id is 0
        SendRead(RRESP,0,msg.src,CC.cache[msg.addr].data,msg.addr,CC.cache[msg.addr].ts,msg.stren,
             CC.cntrs[msg.src].ocnt,CC.fenceCnts[msg.src],0,0,0,msg.qInd); -- Do we need to send write id? No
      else
        SendRead(RRESP,
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
             0,msg.qInd);

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
          ShimPushFifoFront(n,msg);
          ShimReceive(msg,true);
          ShimPopBuf(n,i);
          Shims[n].icnt := Shims[n].icnt + 1;
          if !Shims[n].TFMGPending then ShimPopFifo(n); endif;
        else
          AddSeenId(msg.dst,msg.writeId);
          RemoveSeenIdShimBuf(msg.dst,msg.writeId);
          ShimPopBuf(n,i);
          Shims[n].icnt := Shims[n].icnt + 1;
        endif;
      else 
        if Shims[n].buf[i].status = 0 then
          if ShimAcceptMessage(msg) then
            -- Upgrade from status 0 to status 1
            popped := true;
            ShimPushFifoFront(n,msg);
            ShimReceive(msg,false);
            Shims[n].buf[i].status := 1;
            if !Shims[n].TFMGPending then ShimPopFifo(n); endif;
          endif;
        endif;
      endif;
      i := i + 1;

    endwhile;

    if !Shims[n].TFMGPending & popped then TryPopBufShim(n); endif;

    if Shims[n].bufCnt = 0 then
      CullSeenSet(n);
    endif;

  End;


  Procedure TryShimReceive(msg: Message);
  var pop: boolean;
  var shim: Node;
  Begin 
    shim := msg.dst;
    -- if message is received in order
    if msg.cnt = Shims[shim].icnt then -- accept message
      Shims[shim].icnt := Shims[shim].icnt + 1;
      ShimReceive(msg,true);
    else
      Assert (msg.cnt > Shims[shim].icnt) "Error in TryShimReceive";
      if ShimAcceptMessage(msg) then
        ShimReceive(msg,false);
        ShimPushBuf(shim,msg,1);
      else
        ShimPushBuf(shim,msg,0);
      endif;
    endif;

    if !Shims[shim].TFMGPending then ShimPopFifo(shim); endif;
    
    if !Shims[shim].TFMGPending then TryPopBufShim(shim); endif;

    if !Shims[shim].TFMGPending & Shims[shim].ToFromMemGlue.QueueCnt > 0 then 
      TryShimReceive(Shims[shim].ToFromMemGlue.Queue[0]); 
    endif;

  End;


  -- Deliver most-recently popped message and try to pop a message
  -- from the wait buffers of the source nodes.
  Procedure DeliverMsg(msg: Message);
  Begin
    if msg.dst = 0 then 
      TryCCReceive(msg);
    else
      ShimPushFifoMemGlue(msg.dst,msg);

      if Shims[msg.dst].ToFromMemGlue.QueueCnt = 1 then
        TryShimReceive(msg);
      endif;
      
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

-- MSI Protocol
  function Func_cache(s: ShimId; inmsg:MSIMessage; m:OBJSET_cache) : boolean;
  var msg: MSIMessage;
  begin
    alias i_cache: i_caches[s] do 
    alias adr: inmsg.adr do
    alias cle: i_cache[m].CL[adr] do
    switch cle.State

      case cache_I:
        switch inmsg.mtype
          else return false;
        endswitch;

      case cache_I_load:
        switch inmsg.mtype
          case GetS_Ack:
            cle.cl := inmsg.cl;
            cle.State := cache_S;
            cle.Perm := load;
            UpdateVal(s,m,inmsg.cl);
            PopInstr(s,m);

          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_I_load__Inv_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_I_load__Inv_I:
        switch inmsg.mtype
          case GetS_Ack:
            cle.cl := inmsg.cl;
            cle.State := cache_I;
            cle.Perm := none;
            UpdateVal(s,m,inmsg.cl);
            PopInstr(s,m);

          else return false;
        endswitch;

      case cache_I_store:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_I_store__Fwd_GetM_I;
            cle.Perm := none;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            msg := Resp(adr,WB,m,0,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_I_store__Fwd_GetS_S;
            cle.Perm := none;

          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_M;
            cle.Perm := store;
            -- CompleteWriteInstr(adr,cle.cl,s,m); 
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            else
            cle.State := cache_I_store_GetM_Ack_AD;
            cle.Perm := none;
            endif;

          case GetM_Ack_D:
            cle.cl := inmsg.cl;
            cle.State := cache_M;
            cle.Perm := store;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.State := cache_I_store;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_I_store_GetM_Ack_AD:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetM_I;
            cle.Perm := none;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            msg := Resp(adr,WB,m,0,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S;
            cle.Perm := none;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_M;
            cle.Perm := store;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            else
            cle.State := cache_I_store_GetM_Ack_AD;
            cle.Perm := none;
            endif;

          else return false;
        endswitch;

      case cache_I_store_GetM_Ack_AD__Fwd_GetM_I:
        switch inmsg.mtype
          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_I;
            cle.Perm := none;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);
                        
            i_cache_SendDefermsg(s, adr, m);

            else
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetM_I;
            cle.Perm := none;
            endif;

          else return false;
        endswitch;

      case cache_I_store_GetM_Ack_AD__Fwd_GetS_S:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;
            cle.Perm := none;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_S;
            cle.Perm := load;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            else
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S;
            cle.Perm := none;
            endif;

          else return false;
        endswitch;

      case cache_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I:
        switch inmsg.mtype
          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_I;
            cle.Perm := none;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            else
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;
            cle.Perm := none;
            endif;

          else return false;
        endswitch;

      case cache_I_store__Fwd_GetM_I:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_I;
            cle.Perm := none;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            else
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetM_I;
            cle.Perm := none;
            endif;

          case GetM_Ack_D:
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            cle.cl := inmsg.cl;
            cle.State := cache_I;
            cle.Perm := none;

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.State := cache_I_store__Fwd_GetM_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_I_store__Fwd_GetS_S:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_S;
            cle.Perm := load;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            else
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S;
            cle.Perm := none;
            endif;

          case GetM_Ack_D:
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            cle.cl := inmsg.cl;
            cle.State := cache_S;
            cle.Perm := load;

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_I_store__Fwd_GetS_S__Inv_I;
            cle.Perm := none;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.State := cache_I_store__Fwd_GetS_S;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_I_store__Fwd_GetS_S__Inv_I:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_I;
            cle.Perm := none;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            else
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;
            cle.Perm := none;
            endif;

          case GetM_Ack_D:
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            cle.cl := inmsg.cl;
            cle.State := cache_I;
            cle.Perm := none;

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.State := cache_I_store__Fwd_GetS_S__Inv_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_M:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            
            if !Shims[s].writeSCsPending[m] then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            cle.State := cache_I;
            cle.Perm := none;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            msg := Resp(adr,WB,m,0,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            
            if !Shims[s].writeSCsPending[m] then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            cle.State := cache_S;
            cle.Perm := load;

          else return false;
        endswitch;

      case cache_M_evict:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            
            i_cache_SendDefermsg(s, adr, m);
            cle.State := cache_M_evict_Fwd_GetM;
            cle.Perm := none;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            msg := Resp(adr,WB,m,0,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            
            i_cache_SendDefermsg(s, adr, m);
            cle.State := cache_S_evict;
            cle.Perm := none;

          case Put_Ack:
            cle.State := cache_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_M_evict_Fwd_GetM:
        switch inmsg.mtype
          case Put_Ack:
            cle.State := cache_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_S:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            i_cache_Defermsg(s, msg, adr, m);
            if inmsg.src = 1 | !Shims[s].writeSCsPending[m] then
              i_cache_SendDefermsg(s, adr, m);
            endif;
            cle.State := cache_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_S_evict:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_M_evict_Fwd_GetM;
            cle.Perm := none;

          case Put_Ack:
            cle.State := cache_I;
            cle.Perm := none;

          else return false;
        endswitch;

      case cache_S_store:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_I_store__Fwd_GetM_I;
            cle.Perm := none;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            msg := Resp(adr,WB,m,0,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_S_store__Fwd_GetS_S;
            cle.Perm := load;

          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_M;
            cle.Perm := store;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            else
            cle.State := cache_S_store_GetM_Ack_AD;
            cle.Perm := load;
            endif;

          case GetM_Ack_D:
            cle.State := cache_M;
            cle.Perm := store;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_I_store;
            cle.Perm := none;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.State := cache_S_store;
            cle.Perm := load;

          else return false;
        endswitch;

      case cache_S_store_GetM_Ack_AD:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetM_I;
            cle.Perm := none;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,m,inmsg.src,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            msg := Resp(adr,WB,m,0,cle.cl);
            
            i_cache_Defermsg(s, msg, adr, m);
            cle.State := cache_S_store_GetM_Ack_AD__Fwd_GetS_S;
            cle.Perm := load;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_M;
            cle.Perm := store;
            -- CompleteWriteInstr(adr,cle.cl,s,m); 
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            else
            cle.State := cache_S_store_GetM_Ack_AD;
            cle.Perm := load;
            endif;

          else return false;
        endswitch;

      case cache_S_store_GetM_Ack_AD__Fwd_GetS_S:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;
            cle.Perm := none;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_S;
            cle.Perm := load;
            -- CompleteWriteInstr(adr,cle.cl,s,m); 
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            i_cache_SendDefermsg(s, adr, m);

            else
            cle.State := cache_S_store_GetM_Ack_AD__Fwd_GetS_S;
            cle.Perm := load;
            endif;

          else return false;
        endswitch;

      case cache_S_store__Fwd_GetS_S:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
            cle.State := cache_S;
            cle.Perm := load;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;

            else
            cle.State := cache_S_store_GetM_Ack_AD__Fwd_GetS_S;
            cle.Perm := load;
            endif;

          case GetM_Ack_D:
            cle.State := cache_S;
            cle.Perm := load;
            -- CompleteWriteInstr(adr,cle.cl,s,m);
            WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

            i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
            PopInstr(s,m);

            if (Shims[s].pendingStrens[m] != SC) then
              i_cache_SendDefermsg(s, adr, m);
            endif;
            
          case Inv:
            msg := Resp(adr,Inv_Ack,m,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := cache_I_store__Fwd_GetS_S__Inv_I;
            cle.Perm := none;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.State := cache_S_store__Fwd_GetS_S;
            cle.Perm := load;

          else return false;
        endswitch;

    endswitch;
    endalias;
    endalias;
    endalias;

  return true;
  end;


  procedure i_directory_Defermsg(s: ShimId; msg:MSIMessage; adr: Addr);
  begin
    alias cle: i_directories[s].CL[adr] do
    alias q: cle.Defermsg.Queue do
    alias qind: cle.Defermsg.QueueInd do

    if (qind<=2) then
        q[qind]:=msg;
        qind:=qind+1;
      endif;

    endalias;
    endalias;
    endalias;
  end;

  procedure i_directory_SendDefermsg(s: ShimId; adr: Addr);
  begin
    alias cle: i_directories[s].CL[adr] do
    alias q: cle.Defermsg.Queue do
    alias qind: cle.Defermsg.QueueInd do

    for i := 0 to qind-1 do
        --i_directory_Updatemsg(q[i], adr, m);
        Send_resp(s,q[i]);
          undefine q[i];
      endfor;

    qind := 0;

    endalias;
    endalias;
    endalias;
  end;


  function Func_shim(s: ShimId; inmsg:MSIMessage) : boolean;
  var msg: MSIMessage;
  begin
    alias shim: Shims[s] do 
    alias adr: inmsg.adr do
    alias cle: shim.state[adr] do
    switch cle.protoState

      case shim_I:
        switch inmsg.mtype
          else return false;
        endswitch;

      case shim_I_store:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_I_store__Fwd_GetM_I;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            msg := Resp(adr,WB,1,0,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_I_store__Fwd_GetS_S;

          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_M;
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;

            else
              cle.protoState := shim_I_store_GetM_Ack_AD;
            endif;

          case GetM_Ack_D:
            cle.data := inmsg.cl;
            cle.protoState := shim_M;

            -- Pop queue
            ShimPopFifo(s);
            Shims[s].TFMGPending := false;
            -- Cycle through popping from buffer, popping from fifo queue
            TryPopBufShim(s);
            if Shims[s].ToFromMemGlue.QueueCnt > 0 then
              TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
            endif;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.protoState := shim_I_store;

          else return false;
        endswitch;

      case shim_I_store_GetM_Ack_AD:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetM_I;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            msg := Resp(adr,WB,1,0,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_M;
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD;
            endif;

          else return false;
        endswitch;

      case shim_I_store_GetM_Ack_AD__Fwd_GetM_I:
        switch inmsg.mtype
          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_I;            
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetM_I;
            endif;

          else return false;
        endswitch;

      case shim_I_store_GetM_Ack_AD__Fwd_GetS_S:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,1,inmsg.src,cle.data);
            Send_resp(s,msg);
            cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_S;
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S;
            endif;

          else return false;
        endswitch;

      case shim_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I:
        switch inmsg.mtype
          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_I;            
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;
            endif;

          else return false;
        endswitch;

      case shim_I_store__Fwd_GetM_I:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_I;
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetM_I;
            endif;

          case GetM_Ack_D:
            cle.data := inmsg.cl;
            cle.protoState := shim_I;
            
            Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.protoState := shim_I_store__Fwd_GetM_I;

          else return false;
        endswitch;

      case shim_I_store__Fwd_GetS_S:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_S;            
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S;
            endif;

          case GetM_Ack_D:
            cle.data := inmsg.cl;
            cle.protoState := shim_S;

            Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
          case Inv:
            msg := Resp(adr,Inv_Ack,1,inmsg.src,cle.data);
            Send_resp(s,msg);
            cle.protoState := shim_I_store__Fwd_GetS_S__Inv_I;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.protoState := shim_I_store__Fwd_GetS_S;

          else return false;
        endswitch;

      case shim_I_store__Fwd_GetS_S__Inv_I:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_I;            
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;
            endif;

          case GetM_Ack_D:
            cle.data := inmsg.cl;
            cle.protoState := shim_I;
            
            Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.protoState := shim_I_store__Fwd_GetS_S__Inv_I;

          else return false;
        endswitch;

      case shim_M:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            
            Shim_SendDefermsg(s, adr);
            cle.protoState := shim_I;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            msg := Resp(adr,WB,1,0,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            
            Shim_SendDefermsg(s, adr);
            cle.protoState := shim_S;

          else return false;
        endswitch;

      case shim_S:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,1,inmsg.src,cle.data);
            Send_resp(s,msg);
            cle.protoState := shim_I;

          else return false;
        endswitch;

      case shim_S_store:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_I_store__Fwd_GetM_I;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            msg := Resp(adr,WB,1,0,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_S_store__Fwd_GetS_S;

          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_M;
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_S_store_GetM_Ack_AD;
            endif;

          case GetM_Ack_D:
            cle.protoState := shim_M;
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;

          case Inv:
            msg := Resp(adr,Inv_Ack,1,inmsg.src,cle.data);
            Send_resp(s,msg);
            cle.protoState := shim_I_store;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.protoState := shim_S_store;

          else return false;
        endswitch;

      case shim_S_store_GetM_Ack_AD:
        switch inmsg.mtype
          case Fwd_GetM:
            msg := Resp(adr,GetM_Ack_D,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetM_I;

          case Fwd_GetS:
            msg := Resp(adr,GetS_Ack,1,inmsg.src,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            msg := Resp(adr,WB,1,0,cle.data);
            
            Shim_Defermsg(s, msg, adr);
            cle.protoState := shim_S_store_GetM_Ack_AD__Fwd_GetS_S;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_M;
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_S_store_GetM_Ack_AD;
            endif;

          else return false;
        endswitch;

      case shim_S_store_GetM_Ack_AD__Fwd_GetS_S:
        switch inmsg.mtype
          case Inv:
            msg := Resp(adr,Inv_Ack,1,inmsg.src,cle.data);
            Send_resp(s,msg);
            cle.protoState := shim_I_store_GetM_Ack_AD__Fwd_GetS_S__Inv_I;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_S;
            
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_S_store_GetM_Ack_AD__Fwd_GetS_S;
            endif;

          else return false;
        endswitch;

      case shim_S_store__Fwd_GetS_S:
        switch inmsg.mtype
          case GetM_Ack_AD:
            cle.acksExpected := inmsg.acksExpected;
            if (cle.acksExpected=cle.acksReceived) then
              cle.protoState := shim_S;
            
              Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;
            else
              cle.protoState := shim_S_store_GetM_Ack_AD__Fwd_GetS_S;
            endif;

          case GetM_Ack_D:
            cle.protoState := shim_S;            
            Shim_SendDefermsg(s, adr);
              -- Pop queue
              ShimPopFifo(s);
              Shims[s].TFMGPending := false;
              -- Cycle through popping from buffer, popping from fifo queue
              TryPopBufShim(s);
              if !Shims[s].TFMGPending & Shims[s].ToFromMemGlue.QueueCnt > 0 then
                TryShimReceive(Shims[s].ToFromMemGlue.Queue[0]);
              endif;

          case Inv:
            msg := Resp(adr,Inv_Ack,1,inmsg.src,cle.data);
            Send_resp(s,msg);
            cle.protoState := shim_I_store__Fwd_GetS_S__Inv_I;

          case Inv_Ack:
            cle.acksReceived := cle.acksReceived+1;
            cle.protoState := shim_S_store__Fwd_GetS_S;

          else return false;
        endswitch;

    endswitch;
    endalias;
    endalias;
    endalias;

  return true;
  end;

  function Func_directory(s: ShimId; inmsg:MSIMessage) : boolean;
  var msg: MSIMessage;
  begin
    alias adr: inmsg.adr do
    alias i_directory: i_directories[s] do 
    alias cle: i_directory.CL[adr] do
    switch cle.State

      case directory_I:
        switch inmsg.mtype
          case GetM:
            msg := RespAck(adr,GetM_Ack_AD,0,inmsg.src,cle.cl,VectorCount_v_NrCaches_OBJSET_cache(cle.cache));
            Send_resp(s,msg);
            cle.owner := inmsg.src;
            cle.State := directory_M;
            cle.Perm := none;
            --CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --if inmsg.src != 1 then -- if writer is not the shim, record the instruction as complete
              -- CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --  WriteToShim(s, Shims[s].pendingStrens[inmsg.src], adr, i_caches[s][inmsg.src].CL[adr].cl, inmsg.src); 

            --endif;
          case GetS:
            -- Retrieve data from MemGlue
            i_directory.CL[adr].mshr.Valid := true;
            i_directory.CL[adr].mshr.Issued := true;
            i_directory.CL[adr].mshr.core := inmsg.src;
            --ShimRead(s,inmsg.adr,Shims[s].pendingStrens[inmsg.src]); 
            ReadToShim(s,Shims[s].pendingStrens[inmsg.src],inmsg.adr);

          case PutM:
            msg := Ack(adr,Put_Ack,0,inmsg.src);
            Send_fwd(s,msg);
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            if (cle.owner=inmsg.src) then
            cle.cl := inmsg.cl;
            cle.State := directory_I;
            cle.Perm := none;

            else
            cle.State := directory_I;
            cle.Perm := none;
            endif;

          case PutS:
            msg := Resp(adr,Put_Ack,0,inmsg.src,cle.cl);
            Send_fwd(s,msg);
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            if (VectorCount_v_NrCaches_OBJSET_cache(cle.cache)=0) then
            cle.State := directory_I;
            cle.Perm := none;

            else
            cle.State := directory_I;
            cle.Perm := none;
            endif;

          case Upgrade:
            msg := RespAck(adr,GetM_Ack_AD,0,inmsg.src,cle.cl,VectorCount_v_NrCaches_OBJSET_cache(cle.cache));
            Send_resp(s,msg);
            cle.owner := inmsg.src;
            cle.State := directory_M;
            cle.Perm := none;

          else return false;
        endswitch;

      case directory_M:
        switch inmsg.mtype
          case GetM:
            msg := Request(adr,Fwd_GetM,inmsg.src,cle.owner);
            Send_fwd(s,msg);
            cle.owner := inmsg.src;
            cle.State := directory_M;
            cle.Perm := none;
            --CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --if inmsg.src != 1 then -- if writer is not the shim, record the instruction as complete
              -- CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --  WriteToShim(s, Shims[s].pendingStrens[inmsg.src], adr, i_caches[s][inmsg.src].CL[adr].cl, inmsg.src); 

            --endif;
          case GetS:
            msg := Request(adr,Fwd_GetS,inmsg.src,cle.owner);
            Send_fwd(s,msg);
            AddElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            AddElement_v_NrCaches_OBJSET_cache(cle.cache,cle.owner);
            cle.State := directory_M_GetS;
            cle.Perm := none;

          case PutM:
            msg := Ack(adr,Put_Ack,0,inmsg.src);
            Send_fwd(s,msg);
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            if (cle.owner=inmsg.src) then
            cle.cl := inmsg.cl;
            cle.State := directory_I;
            cle.Perm := none;

            else
            cle.State := directory_M;
            cle.Perm := none;
            endif;

          case PutS:
            msg := Resp(adr,Put_Ack,0,inmsg.src,cle.cl);
            Send_fwd(s,msg);
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            if (VectorCount_v_NrCaches_OBJSET_cache(cle.cache)=0) then
            cle.State := directory_M;
            cle.Perm := none;

            else
            cle.State := directory_M;
            cle.Perm := none;
            endif;

          case Upgrade:
            msg := Request(adr,Fwd_GetM,inmsg.src,cle.owner);
            Send_fwd(s,msg);
            cle.owner := inmsg.src;
            cle.State := directory_M;
            cle.Perm := none;

          else return false;
        endswitch;

      case directory_M_GetS:
        switch inmsg.mtype
          case WB:
            if (inmsg.src=cle.owner) then
            cle.cl := inmsg.cl;
            cle.State := directory_S;
            cle.Perm := none;

            else
            cle.State := directory_M_GetS;
            cle.Perm := none;
            endif;

            --CompleteWriteInstr(adr,inmsg.cl,s,inmsg.src);
            --if inmsg.src != 1 then -- if writer is not the shim, record the instruction as complete
              -- CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --  WriteToShim(s, Shims[s].pendingStrens[inmsg.src], adr, i_caches[s][inmsg.src].CL[adr].cl, inmsg.src); 

            --endif;
          else return false;
        endswitch;

      case directory_S:
        switch inmsg.mtype
          case GetM:

            if (IsElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src)) then
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            msg := RespAck(adr,GetM_Ack_AD,0,inmsg.src,cle.cl,VectorCount_v_NrCaches_OBJSET_cache(cle.cache));
            Send_resp(s,msg);
            cle.State := directory_M;
            cle.Perm := none;
            msg := Ack(adr,Inv,inmsg.src,inmsg.src);
            Multicast_fwd_v_NrCaches_OBJSET_cache(s, msg,cle.cache);
            cle.owner := inmsg.src;
            ClearVector_v_NrCaches_OBJSET_cache(cle.cache);

            else
            msg := RespAck(adr,GetM_Ack_AD,0,inmsg.src,cle.cl,VectorCount_v_NrCaches_OBJSET_cache(cle.cache));
            Send_resp(s,msg);
            cle.State := directory_M;
            cle.Perm := none;
            msg := Ack(adr,Inv,inmsg.src,inmsg.src);
            Multicast_fwd_v_NrCaches_OBJSET_cache(s,msg,cle.cache);
            cle.owner := inmsg.src;
            ClearVector_v_NrCaches_OBJSET_cache(cle.cache);
            endif;

            --if inmsg.src != 1 then -- if writer is not the shim, record the instruction as complete
              -- CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --  WriteToShim(s, Shims[s].pendingStrens[inmsg.src], adr, i_caches[s][inmsg.src].CL[adr].cl, inmsg.src); 

            --endif;

          case GetS:
            AddElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            msg := Resp(adr,GetS_Ack,0,inmsg.src,cle.cl);
            Send_resp(s,msg);
            cle.State := directory_S;
            cle.Perm := none;

          case PutM:
            msg := Ack(adr,Put_Ack,0,inmsg.src);
            Send_fwd(s,msg);
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            if (cle.owner=inmsg.src) then
            cle.cl := inmsg.cl;
            cle.State := directory_S;
            cle.Perm := none;

            else
            cle.State := directory_S;
            cle.Perm := none;
            endif;

          case PutS:
            msg := Resp(adr,Put_Ack,0,inmsg.src,cle.cl);
            Send_fwd(s,msg);
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            if (VectorCount_v_NrCaches_OBJSET_cache(cle.cache)=0) then
            cle.State := directory_I;
            cle.Perm := none;

            else
            cle.State := directory_S;
            cle.Perm := none;
            endif;

          case Upgrade:
            if (IsElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src)) then
            RemoveElement_v_NrCaches_OBJSET_cache(cle.cache,inmsg.src);
            msg := RespAck(adr,GetM_Ack_AD,0,inmsg.src,cle.cl,VectorCount_v_NrCaches_OBJSET_cache(cle.cache));
            Send_resp(s,msg);
            cle.State := directory_M;
            cle.Perm := none;
            msg := Ack(adr,Inv,inmsg.src,inmsg.src);
            Multicast_fwd_v_NrCaches_OBJSET_cache(s,msg,cle.cache);
            cle.owner := inmsg.src;
            ClearVector_v_NrCaches_OBJSET_cache(cle.cache);

            else
            msg := RespAck(adr,GetM_Ack_AD,0,inmsg.src,cle.cl,VectorCount_v_NrCaches_OBJSET_cache(cle.cache));
            Send_resp(s,msg);
            cle.State := directory_M;
            cle.Perm := none;
            msg := Ack(adr,Inv,inmsg.src,inmsg.src);
            Multicast_fwd_v_NrCaches_OBJSET_cache(s,msg,cle.cache);
            cle.owner := inmsg.src;
            ClearVector_v_NrCaches_OBJSET_cache(cle.cache);
            endif;
            --CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --if inmsg.src != 1 then -- if writer is not the shim, record the instruction as complete
              -- CompleteWriteInstr(adr,i_caches[s][inmsg.src].CL[adr].cl,s,inmsg.src);
            --  WriteToShim(s, Shims[s].pendingStrens[inmsg.src], adr, i_caches[s][inmsg.src].CL[adr].cl, inmsg.src); 

            --endif;
          else return false;
        endswitch;

    endswitch;
    endalias;
    endalias;
    endalias;
  return true;
  end;


  procedure SEND_cache_I_load(s: ShimId; adr:Addr; m:OBJSET_cache);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      msg := Request(adr,GetS,m,0);
      Send_req(s,msg);
      cle.State := cache_I_load;
      cle.Perm := none;
  endalias;
  end;


  procedure SEND_cache_I_store(s: ShimId; adr:Addr; m:OBJSET_cache; data:Data);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      msg := Request(adr,GetM,m,0);
      Send_req(s,msg);
      cle.acksReceived := 0;
      cle.State := cache_I_store;
      cle.Perm := none;
      -- Immediately write data in cache -- will get overwritten later if necessary
      cle.cl := data;
  endalias;
  end;


  -- TODO: add eviction
  procedure SEND_cache_M_evict(s: ShimId; adr:Addr; m:OBJSET_cache);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      msg := Resp(adr,PutM,m,0,cle.cl);
      Send_req(s,msg);
      cle.State := cache_M_evict;
      cle.Perm := none;
  endalias;
  end;


  procedure SEND_cache_M_load(s: ShimId; adr:Addr; m:OBJSET_cache);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      cle.State := cache_M;
      cle.Perm := store;

      UpdateVal(s,m,cle.cl);
      PopInstr(s,m);
      --i_cache[m].queue.Queue[i_cache[m].queue.QueueInd].pend := false;
  endalias;
  end;


  procedure SEND_cache_M_store(s: ShimId; adr:Addr; m:OBJSET_cache; data:Data);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      cle.State := cache_M;
      cle.Perm := store;
      cle.cl := data;

      --CompleteWriteInstr(adr,cle.cl,s,m);
      WriteToShim(s, Shims[s].pendingStrens[m], adr, i_caches[s][m].CL[adr].cl, m); 

      i_caches[s][m].queue.Queue[i_caches[s][m].queue.QueueInd].pend := false;
      PopInstr(s,m);

  endalias;
  end;


  -- TODO: add eviction
  procedure SEND_cache_S_evict(s: ShimId; adr:Addr; m:OBJSET_cache);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      msg := Request(adr,PutS,m,0);
      Send_req(s,msg);
      cle.State := cache_S_evict;
      cle.Perm := none;
  endalias;
  end;


  procedure SEND_cache_S_load(s: ShimId; adr:Addr; m:OBJSET_cache);
  var msg: MSIMessage; var shimElem: ShimElemState; var found: boolean;
  var bufData:Data; var bufTS:Timestamp; var bufMsg: Message;
  var bufIdx: 0..NetMax; var bufWId: WriteId;
  begin
    alias cle: i_caches[s][m].CL[adr] do

    if Shims[s].pendingStrens[m] = RLX then
      shimElem := Shims[s].state[adr];
      found := false;
      bufTS := shimElem.ts;
      bufIdx := 0;
      for i := 0 to Shims[s].bufCnt - 1 do -- attempt to read from buffer for data -- CHECK: does this need to be more fine-grained? Check ts?
        bufMsg := Shims[s].buf[i].msg;
        if bufMsg.mtype = WRITE & bufMsg.addr = adr & bufMsg.ts > bufTS & bufMsg.wCntr = shimElem.localWriteCntr then
          found := true;
          bufData := bufMsg.data;
          bufTS := bufMsg.ts;
          bufIdx := i;
          bufWId := bufMsg.writeId;
        endif;
      endfor;
      if found then 
        if (!Shims[s].buf[bufIdx].rf) then
          Shims[s].buf[bufIdx].rf := true;
          Shims[s].state[adr].rfBuf := Shims[s].state[adr].rfBuf + 1;
        endif;
        AddSeenIdShimBuf(s,bufWId);

        cle.cl := bufData;
        i_directories[s].CL[adr].cl := bufData;
        
      endif;
    
    endif;

      cle.State := cache_S;
      cle.Perm := load;

      UpdateVal(s,m,cle.cl);
      PopInstr(s,m);
      --i_cache[m].queue.Queue[i_cache[m].queue.QueueInd].pend := false;
  endalias;
  end;


  procedure SEND_cache_S_store(s: ShimId; adr:Addr; m:OBJSET_cache; data:Data);
  var msg: MSIMessage;
  begin
    alias cle: i_caches[s][m].CL[adr] do
      msg := Request(adr,Upgrade,m,0);
      Send_req(s,msg);
      cle.acksReceived := 0;
      cle.State := cache_S_store;
      cle.Perm := load;

      -- Write data immediately
      cle.cl := data;
  endalias;
  end;


  function MsgHandlerShimToCluster(s: ShimId; msg : MSIMessage): boolean;
  Begin
    Assert (msg.mtype = GetM) "Invalid message sent to LLC from shim";
    Assert (!i_directories[s].CL[msg.adr].mshr.Valid);

    return Func_directory(s,msg);
  End;

-- Litmus test infrastructure

  Function CacheLoad(s: ShimId; m: OBJSET_cache; instr: Instr): boolean;
  Begin
    switch i_caches[s][m].CL[instr.addr].State
      case cache_I:
        SEND_cache_I_load(s,instr.addr,m);
        -- pending strength
        Shims[s].pendingStrens[m] := instr.stren;
        return true;

      case cache_M:
        SEND_cache_M_load(s,instr.addr,m);
        return true;

      case cache_S: 
        Shims[s].pendingStrens[m] := instr.stren;
        SEND_cache_S_load(s,instr.addr,m);
        return true;

      else return false;
    endswitch;
  End;

  Function CacheStore(s: ShimId; m: OBJSET_cache; instr: Instr): boolean;
  Begin
    switch i_caches[s][m].CL[instr.addr].State
      case cache_I:
        SEND_cache_I_store(s,instr.addr,m,instr.data);
        Shims[s].pendingStrens[m] := instr.stren;
        return true;

      case cache_M:
        SEND_cache_M_store(s,instr.addr,m,instr.data);
        return true;

      case cache_S: 
        SEND_cache_S_store(s,instr.addr,m,instr.data);
        Shims[s].pendingStrens[m] := instr.stren; 
        return true;

      else return false;
    endswitch;
  End;

  -- Call the appropriate procedures given an instruction
  Procedure IssueInstr(s: ShimId; m: OBJSET_cache);
  var instr: Instr;      
  var qind: QueueInd;
  var ret: boolean;
  Begin
    instr := GetInstr(s,m);
    qind := i_caches[s][m].queue.QueueInd;
      
    if instr.access = load then -- ignore cpu.pending for now...
      ret := CacheLoad(s,m,instr);
      if !ret then
        error "Issued load at invalid state!";
      endif;
      --ShimRead(m, instr.addr, instr.stren, qind);

    endif;

    if instr.access = store then
      ret := CacheStore(s,m,instr);
      if !ret then
        error "Issued store at invalid state!";
      endif;
      --ShimWrite(m, instr.addr, instr.data, instr.stren, qind);
      --i_cache[m].queue.Queue[qind].pend := false;
      --PopInstr(m);
    endif;

    if instr.access = fence then
      --ShimFence(m);
      i_caches[s][m].queue.Queue[qind].pend := false;
    endif;

    --PopInstr(m);
    -- i_cache[m].queue.QueueInd := i_cache[m].queue.QueueInd + 1;

  End;

  Procedure AddInstr(s: ShimId; m: OBJSET_cache; instr: Instr);
  Begin
    alias sQ: i_caches[s][m].queue.Queue do
    alias QCnt: i_caches[s][m].queue.QueueCnt do
      sQ[QCnt] := instr;
      sQ[QCnt].pend := false;
      QCnt := QCnt + 1;
    endalias;
    endalias;
  End;

  Procedure DeactivateEmptyCores(); 
  Begin
    for s:ShimId do
      for c:OBJSET_cache do
        if i_caches[s][c].queue.QueueCnt = 0 then
          i_caches[s][c].active := false;
        endif;
      endfor;
    endfor;
  End;

/* Litmus test */

---------------------------------------------------------------------
  Procedure InitLitmusTests();
  Begin
    /* InitLitmusTests(); */

    DeactivateEmptyCores();
  End;

  Function CheckReset(): boolean;
  var cnt_resp: 0..U_NET_MAX;
  var cnt_req: 0..U_NET_MAX;
  Begin
    for s: OBJSET_cache do
      for shim: ShimId do 
        if i_caches[shim][s].active = true then
          return false;
        endif;

        for i := 0 to i_caches[shim][s].queue.QueueCnt-1 do
          if i_caches[shim][s].queue.Queue[i].pend = true then
            return false;
          endif;
        endfor;

        if cnt_fwd[shim][s] > 0 then 
          return false;
        endif;

        if MultiSetCount(i:resp[shim][s],true) > 0 then
          return false;
        endif;

        if MultiSetCount(i:req[shim][s],true) > 0 then
          return false;
        endif;

      endfor;
    endfor;


    return true;
  End;

  Procedure WriteInitialData();
  Begin
    /* WriteInitialData(); */
  End;

  Procedure SystemReset();
  Begin

    -- Reset shim caches and CC
    For a:Addr do
      -- Reset CC
      CC.cache[a].ts := 0;
      CC.cache[a].data := 0;
      CC.cache[a].lastWriteShim := 0;

      -- Reset shims
      For s:ShimId do
	      CC.cache[a].sharers[s] := N;
      	CC.cntrs[s].icnt := 0;
      	CC.cntrs[s].ocnt := 0;
        CC.fenceCnts[s] := 0;
        CC.seenIds[s].seenIds[a].writeId := 0;
        undefine CC.seenIds[s].seenIds[a].stren;
        CC.seenIds[s].seenIds[a].seenId := 0;
        CC.seenIds[s].seenIds[a].wCntr := 0;
        CC.seenIds[s].seenPerShim := 0;
        
	      Shims[s].state[a].state := Invalid;
	      undefine Shims[s].state[a].data;
	      Shims[s].state[a].ts := 0;
        Shims[s].state[a].localWriteCntr := 0;
        Shims[s].state[a].syncBit := true;
        Shims[s].state[a].rfBuf := 0;        
	      Shims[s].fencePending := false;
        undefine Shims[s].buf;
	      Shims[s].icnt := 0;
	      Shims[s].ocnt := 0;
	      Shims[s].fenceCnt := 0;
	      Shims[s].bufCnt := 0;

        Shims[s].state[a].protoState := shim_I;
        Shims[s].state[a].acksReceived := 0;
        Shims[s].state[a].acksExpected := 0;
        Shims[s].state[a].Defermsg.QueueInd := 0;
        
	      Shims[s].queue.QueueCnt := 0;
	      Shims[s].queue.QueueInd := 0;
	      undefine Shims[s].queue.Queue;

        undefine Shims[s].pendingStrens;

        -- Reset directory
        i_directories[s].CL[a].State := directory_I;
        i_directories[s].CL[a].cl := 0;
        i_directories[s].CL[a].Defermsg.QueueInd := 0;
        i_directories[s].CL[a].Perm := none;
        for sharer:PossibleSharers do
          i_directories[s].CL[a].cache[sharer] := N;
        endfor;
        i_directories[s].CL[a].mshr.Valid := false;
        i_directories[s].CL[a].mshr.Issued := false;
        undefine i_directories[s].CL[a].mshr.core;

      endfor;
    endfor;

    For s:ShimId do
      Shims[s].seenId := 0;
      Shims[s].seenSet[0] := 0;
      undefine Shims[s].seenSetBuf;
      Shims[s].seenSize := 1;
      Shims[s].seenSizeBuf := 0;

      undefine shimNet[s];
      cnt_shimNet[s] := 0;

      undefine clToShimBuf[s];
      cnt_clToShimBuf[s] := 0;

      -- FIFO queue of write updates from MemGlue + RREQs to MemGlue
      undefine Shims[s].ToFromMemGlue.Queue;
      Shims[s].ToFromMemGlue.QueueCnt := 0;     
      Shims[s].TFMGPending := false; 

      for n:Machines do
        cnt_fwd[s][n] := 0;
      endfor;

      -- Reset cores
      for i:OBJSET_cache do
        for a:Addr do
          i_caches[s][i].CL[a].State := cache_I;
          i_caches[s][i].CL[a].acksExpected := 0;
          i_caches[s][i].CL[a].acksReceived := 0;
          undefine i_caches[s][i].CL[a].cl; -- := 0;
          i_caches[s][i].CL[a].Defermsg.QueueInd := 0;
          i_caches[s][i].CL[a].Perm := none;
          
        endfor;
        i_caches[s][i].active := true;
        i_caches[s][i].queue.QueueCnt := 0;
        i_caches[s][i].queue.QueueInd := 0;
        undefine i_caches[s][i].queue.Queue;

        Shims[s].fencesPending[i] := false;
        Shims[s].fencesPendingCnt := 0;
        undefine Shims[s].fences;

        Shims[s].writeSCsPending[i] := false;
        Shims[s].writeSCsPendingCnt := 0;
        undefine Shims[s].writeSCs;      
      endfor;

    endfor;

    undefine CC.buf;
    CC.bufCnt := 0;

    wIdCounter := 1; -- First write id is 1

    -- Net reset
    -- undefine Net;
    undefine NetU;
    
    undefine resp;
    
    undefine req;
    
    undefine fwd;

    WriteInitialData();

    InitLitmusTests();

  End;


Function StallFwd(n: Machines; s: ShimId; msg:MSIMessage) : boolean;
Begin
  -- Never stall shim or directory
  if (n = 0 | n = 1) then return false; endif;

  if Shims[s].fencesPending[n] then 
    return true;
  endif;

  -- Forwarded messages can still be accepted when a write SC is pending

  return false;


End;

Function StallCore(n: Machines; s: ShimId; msg:MSIMessage) : boolean;
Begin
  -- Never stall shim or directory
  if (n = 0 | n = 1) then return false; endif;

  if Shims[s].fencesPending[n] then 
    return true;
  endif;

  -- If a write SC is waiting for an acknowledgement and
  -- the incoming message is not an invalidation message from 
  -- the shim, then stall
  if Shims[s].writeSCsPending[n] 
    & !(msg.mtype = Inv & msg.src = 1) then
    return true;
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

        if deliverMsgHack.dst = 0 then -- n doesn't work here! It's always 0 for some reason
          TryPopBufCC();
        --else
        --  TryPopBufShim(deliverMsgHack.dst); --n
        endif;
        
      endrule;
    endchoose;
  endruleset;


ruleset shim:ShimId do
  ruleset n:Machines do

      choose midx:resp[shim][n] do
          alias mach:resp[shim][n] do
          alias msg:mach[midx] do
            rule "Receive resp"
              !isundefined(msg.mtype) &
              ((n = 0 & !isundefined(msg.adr) & !i_directories[shim].CL[msg.adr].mshr.Valid) | n != 0) & 
              ((n = 0 | n = 1) | ((n > 1) & !Shims[shim].fencesPending[n])) & 
              ((n = 0 | n = 1) | ((n > 1) & !Shims[shim].writeSCsPending[n]))
            ==>

                -- Without input queues
                if n = 0 then
                  if Func_directory(shim,msg) then
                    MultiSetRemove(midx, mach);
                  endif;
                else
                  -- Assert (n != 1) "Shim receiving message";
                  -- Shim should disregard resp messages from other clusters
                  if (n = 1) then
                    if Func_shim(shim,msg) then
                      MultiSetRemove(midx, mach);
                    endif;
                  else 
                    if Func_cache(shim,msg, n) then
                      MultiSetRemove(midx, mach);
                    endif;
                  endif;
                endif;
            endrule;
          endalias;
          endalias;
      endchoose;

  endruleset;

  ruleset n:Machines do

      choose midx:req[shim][n] do
          alias mach:req[shim][n] do
          alias msg:mach[midx] do
            rule "Receive req"
              !isundefined(msg.mtype) &
              ((n = 0 & !isundefined(msg.adr) & !i_directories[shim].CL[msg.adr].mshr.Valid) | n != 0) & 
              ((n = 0 | n = 1) | ((n > 1) & !Shims[shim].fencesPending[n])) & 
              ((n = 0 | n = 1) | ((n > 1) & !Shims[shim].writeSCsPending[n]))
            ==>
                -- Without input queues
                if n = 0 then
                  if Func_directory(shim,msg) then
                    MultiSetRemove(midx, mach);
                  endif;
                else
                  -- Assert (n != 1) "Shim receiving message";
                  if n = 1 then
                    if Func_shim(shim,msg) then
                      MultiSetRemove(midx, mach);
                    endif;
                  else
                    if Func_cache(shim,msg, n) then
                      MultiSetRemove(midx, mach);
                    endif;
                  endif;
                endif;
            endrule;
          endalias;
          endalias;
      endchoose;

  endruleset;

  ruleset n:Machines do
      alias msg:fwd[shim][n][0] do
        rule "Receive fwd"
          cnt_fwd[shim][n] > 0 &
          ((n = 0 & !isundefined(msg.adr) & !i_directories[shim].CL[msg.adr].mshr.Valid) | n != 0) & 
          !StallFwd(n,shim,msg)  
          --((n = 0 | n = 1) | (n > 1 & !Shims[shim].fencesPending[n])) & 
          --((n = 0 | n = 1) | (n > 1 & !Shims[shim].writeSCsPending[n])) & 
        ==>

          -- Without input queues
            if n = 0 then
              if Func_directory(shim,msg) then
                Pop_fwd(shim,n);
              endif;
            else
              -- Assert (n != 1) "Shim receiving message";
              if n = 1 then
                if Func_shim(shim,msg) then
                  Pop_fwd(shim,n);
                endif;
              else
                if Func_cache(shim,msg, n) then
                  Pop_fwd(shim,n);
                endif;  
              endif;
            endif;
        endrule;
      endalias;

  endruleset;
endruleset;

  ruleset s:ShimId do

    rule "Deliver message shim to cluster"
      cnt_shimNet[s] > 0
    ==> 
      if MsgHandlerShimToCluster(s,shimNet[s][0]) then
        PopShimNet(s);
      endif;

    endrule;

  endruleset;


  -- Execute litmus test
  -- NOTE: when fence in place, don't execute...
  ruleset s:ShimId do 
  ruleset core:OBJSET_cache do
    rule "Execute litmus instruction" 
      i_caches[s][core].active = true
      -- & i_cache[core].fencePending = false
      & (!i_caches[s][core].queue.Queue[i_caches[s][core].queue.QueueInd].pend)
      -- REQUIRE we're in stable cache state!
      & (  i_caches[s][core].CL[i_caches[s][core].queue.Queue[i_caches[s][core].queue.QueueInd].addr].State = cache_I
         | i_caches[s][core].CL[i_caches[s][core].queue.Queue[i_caches[s][core].queue.QueueInd].addr].State = cache_S
         | i_caches[s][core].CL[i_caches[s][core].queue.Queue[i_caches[s][core].queue.QueueInd].addr].State = cache_M )
      & !Shims[s].fencesPending[core]
      & !Shims[s].writeSCsPending[core]
    ==> 
      IssueInstr(s,core);
    endrule;

    rule "Shim done"
      i_caches[s][core].active = false
    ==> 
      if CheckReset() 
      then
        /* Forbidden function */
        SystemReset();
      endif;
    endrule;
  endruleset;
  endruleset;

-------------------------------------------------------------------------------
-- Startstate
-------------------------------------------------------------------------------
  startstate
    SystemReset();
  endstartstate;
