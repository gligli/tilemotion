unit mtpool;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, utils, MTProcs;

type
  { TMTPool }

  TMTPool = class
  type

    TJobProcedure = procedure(Index: PtrInt; Data: Pointer);

    TJob = record
      Proc: TJobProcedure;
      StackFrame: Pointer;
      StartIndex, EndIndex, Index: PtrInt;
      Data: Pointer;
      WorkerCount: Integer;
      Lock: TSpinlock;
    end;

    TWorkerThread = class(TThread)
    private
      StateLock: TSpinlock;
      PendingTermination: Boolean;
      PoolRef: TMTPool;
    protected
      procedure Execute; override;
    public
      constructor Create;
    end;

  private
    FMaxThreads: Cardinal;
    FAliveWorkerCount: Integer;
    FAliveWorkerLock: TSpinlock;
    FWorkers: array of TWorkerThread;
    FJob: TJob;

    class procedure CallLocalProc(AProc, Frame: Pointer; Index: PtrInt; Data: Pointer); inline;

    function GetNextJobIdx: PtrInt; inline;

    procedure StartJob(AProc: TJobProcedure; StartIndex, EndIndex: PtrInt; Data, StackFrame: Pointer);
    procedure WorkJob;
    procedure WaitJob;
    procedure BuildWorkers;
    procedure TerminateWorkers;
  public
    constructor Create(AMaxThreads: Cardinal);
    destructor Destroy; override;

    procedure DoLocalProc(const LocalProc: Pointer; StartIndex, EndIndex: PtrInt; Data: Pointer = nil); // do not make this inline!
    class procedure DoStandaloneLocalProc(const LocalProc: Pointer; StartIndex, EndIndex: PtrInt; MaxThreads: Cardinal; Data: Pointer = nil); // do not make this inline!

    class procedure CalcBlock(Index, BlockSize, LoopLength: PtrInt; out BlockStart, BlockEnd: PtrInt); inline;

    property MaxThreads: Cardinal read FMaxThreads;
  end;

implementation

{ TMTPool }

class procedure TMTPool.CallLocalProc(AProc, Frame: Pointer; Index: PtrInt; Data: Pointer);
type
  PointerLocal = procedure(_EBP: Pointer; Param1: PtrInt; Param2: Pointer);
begin
  PointerLocal(AProc)(Frame, Index, Data);
end;

function TMTPool.GetNextJobIdx: PtrInt;
begin
  Result := InterlockedIncrement64(FJob.Index);
end;

procedure TMTPool.StartJob(AProc: TJobProcedure; StartIndex, EndIndex: PtrInt; Data, StackFrame: Pointer);
var
  iWorker, cnt: Integer;
  Worker: TWorkerThread;
begin
  Assert(EndIndex >= StartIndex);
  FJob.Proc := AProc;
  FJob.StackFrame := StackFrame;
  FJob.StartIndex := StartIndex;
  FJob.EndIndex := EndIndex;
  FJob.Index := StartIndex - 1;
  FJob.Data := Data;

  cnt := EndIndex - StartIndex + 1;
  cnt := Min(cnt - 1, Length(FWorkers)); // at least one job index runs in the main thread
  if cnt > 0 then
  begin
    SpinEnter(@FJob.Lock);
    InterlockedExchangeAdd(FJob.WorkerCount, cnt);

    for iWorker := 0 to cnt - 1 do
    begin
      Worker := FWorkers[iWorker];

      SpinLeave(@Worker.StateLock);
    end;
  end;

  WorkJob;
end;

procedure TMTPool.WorkJob;
var
  jobIdx: PtrInt;
begin
  jobIdx := GetNextJobIdx;
  while jobIdx <= FJob.EndIndex do
  begin
    TMTPool.CallLocalProc(FJob.Proc, FJob.StackFrame, jobIdx, FJob.Data);

    jobIdx := GetNextJobIdx;
  end;
end;

procedure TMTPool.BuildWorkers;
var
  iWorker: Integer;
  Worker: TWorkerThread;
begin
  SetLength(FWorkers, FMaxThreads - 1);

  if Assigned(FWorkers) then
  begin
    SpinEnter(@FAliveWorkerLock);

    for iWorker := 0 to High(FWorkers) do
    begin
      Worker := TWorkerThread.Create;
      FWorkers[iWorker] := Worker;

      Worker.FreeOnTerminate := True;
      Worker.PoolRef := Self;
      SpinEnter(@Worker.StateLock);

      Worker.Start;
    end;
  end;
end;

procedure TMTPool.TerminateWorkers;
var
  iWorker: Integer;
  Worker: TWorkerThread;
begin
  WaitJob;

  if Assigned(FWorkers) then
  begin
    for iWorker := 0 to High(FWorkers) do
    begin
      Worker := FWorkers[iWorker];

      Worker.PendingTermination := True;
      SpinLeave(@Worker.StateLock);
    end;

    SpinEnter(@FAliveWorkerLock);
    SpinLeave(@FAliveWorkerLock);
  end;
end;

constructor TMTPool.Create(AMaxThreads: Cardinal);
begin
  Assert(AMaxThreads > 0);
  FMaxThreads := AMaxThreads;
  SpinLeave(@FAliveWorkerLock);
  SpinLeave(@FJob.Lock);

  BuildWorkers;
end;

destructor TMTPool.Destroy;
begin
  TerminateWorkers;

  inherited Destroy;
end;

procedure TMTPool.WaitJob;
begin
  SpinEnter(@FJob.Lock);
  SpinLeave(@FJob.Lock);
  Assert(FJob.WorkerCount = 0);
end;

procedure TMTPool.DoLocalProc(const LocalProc: Pointer; StartIndex, EndIndex: PtrInt; Data: Pointer);
var
  StackFrame: Pointer;
begin
  if not Assigned(LocalProc) then
    Exit;

  StackFrame := get_caller_frame(get_frame);

  StartJob(TJobProcedure(LocalProc), StartIndex, EndIndex, Data, StackFrame);
  WaitJob;
end;

class procedure TMTPool.DoStandaloneLocalProc(const LocalProc: Pointer; StartIndex, EndIndex: PtrInt; MaxThreads: Cardinal;
  Data: Pointer);
var
  Pool: TMTPool;
begin
  if not Assigned(LocalProc) then
    Exit;

  Pool := TMTPool.Create(MaxThreads);
  try
    Pool.StartJob(TJobProcedure(LocalProc), StartIndex, EndIndex, Data, get_caller_frame(get_frame));
  finally
    Pool.Free;
  end;
end;

class procedure TMTPool.CalcBlock(Index, BlockSize, LoopLength: PtrInt; out BlockStart, BlockEnd: PtrInt);
begin
  BlockStart:=BlockSize*Index;
  BlockEnd:=BlockStart+BlockSize;
  if LoopLength<BlockEnd then BlockEnd:=LoopLength;
  Dec(BlockEnd);
end;

{ TMTPool.TWorkerThread }

constructor TMTPool.TWorkerThread.Create;
begin
  SpinLeave(@StateLock);
  inherited Create(True);
end;

procedure TMTPool.TWorkerThread.Execute;
var
  cnt: Integer;
begin
  InterlockedIncrement(PoolRef.FAliveWorkerCount);

  repeat
    SpinEnter(@StateLock);

    if not PendingTermination then
    begin
      PoolRef.WorkJob;

      cnt := InterlockedDecrement(PoolRef.FJob.WorkerCount);
      if cnt <= 0 then
      begin
        Assert(cnt = 0);
        SpinLeave(@PoolRef.FJob.Lock);
      end;
    end;

  until PendingTermination;

  cnt := InterlockedDecrement(PoolRef.FAliveWorkerCount);
  if cnt <= 0 then
  begin
    Assert(cnt = 0);
    SpinLeave(@PoolRef.FAliveWorkerLock);
  end;
end;


end.

