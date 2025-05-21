// Adapted from https://github.com/nicodv/kmodes

unit kmodes;

//{$define GENERIC_DISSIM}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, LazLogger, MTProcs, windows, extern;

const
  cKModesFeatureCount = 64;
  cDissimSubMatchingSize = 11;
  cPhi = (1 + sqrt(5)) / 2;
  cInvPhi = 1 / cPhi;

type
  PInteger = ^Integer;
  TCompareFunction=function(Item1,Item2,UserParameter:Pointer):Integer;
  TIntegerDynArray2 = array of TIntegerDynArray;
  TIntegerDynArray3 = array of TIntegerDynArray2;
  TByteDynArray2 = array of TByteDynArray;
  TByteDynArray3 = array of TByteDynArray2;
  TUInt64DynArray = array of UInt64;
  TUInt64DynArray2 = array of TUInt64DynArray;

  TGMMD = record
    clust: PInteger;
    dis: PUInt64;
    X, centroids: PPByte;
  end;

  TKmodesRun = packed record
    Labels: TIntegerDynArray;
    Centroids: TByteDynArray2;
    Cost: UInt64;
    NIter: Integer;
    TotalMoves: Integer;
    StartingPoint: Integer;
  end;

  { TKModes }

  TKModes = class
  private
    membship: TIntegerDynArray;
    X: TByteDynArray2;
    centroids: TByteDynArray2;
    cl_attr_freq: TIntegerDynArray3;
    MaxIter, NumClusters, NumThreads, NumAttrs, NumPoints: Integer;
    Log: Boolean;
    LogLabel: String;
    Concurrency: PInteger;
    FGMMD: TGMMD;
    FPTP: TProcThreadPool;

    procedure DoGMMD(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
    procedure FinishGMMD;
    function GetConcurrentNumThreads: Integer;

    function CountClusterMembers(cluster: Integer): Integer;
    function GetMaxClusterMembers(out member_count: Integer): Integer;
    function KModesIter(var Seed: Cardinal; out Cost: UInt64): Integer;
    function InitFarthestFirst(InitPoint: Integer): TByteDynArray2;  // negative init_point means randomly chosen
    procedure MovePointCat(const point: TByteDynArray; ipoint, to_clust, from_clust: Integer);
  public
    constructor Create(aNumThreads: Integer = 0; aMaxIter: Integer = -1; aLog: Boolean = False; aLogLabel: String = ''; aConcurrency: PInteger = nil);
    destructor Destroy; override;
    function ComputeKModes(const ADataset: TByteDynArray2; ANumClusters, ANumInit, ANumModalities: Integer; out FinalLabels: TIntegerDynArray; out FinalCentroids: TByteDynArray2): Integer;
    // negative n_init means use -n_init as starting point
    // FinalLabels cluster indexes start at 1
  end;


function RandInt(Range: Cardinal; var Seed: Cardinal): Cardinal;
procedure QuickSort(var AData;AFirstItem,ALastItem,AItemSize:Integer;ACompareFunction:TCompareFunction;AUserParameter:Pointer=nil);
function MatchingDissim(const a: TByteDynArray; const b: TByteDynArray): UInt64; inline; overload;
function MatchingDissim(a: PBYTE; b: PByte; count: Integer): UInt64; inline; overload;
function GetMinMatchingDissim(const a: TByteDynArray2; const b: TByteDynArray; count: Integer; out bestDissim: UInt64): Integer; overload;

implementation

{$PUSH}
{$RANGECHECKS OFF}
function RandInt(Range: Cardinal; var Seed: Cardinal): Cardinal;
begin
  Seed := Integer(Seed * $08088405) + 1;
  Result := (Seed * Range) shr 32;
end;
{$POP}

procedure QuickSort(var AData;AFirstItem,ALastItem,AItemSize:Integer;ACompareFunction:TCompareFunction;AUserParameter:Pointer=nil);
var I, J, P: Integer;
    PData,P1,P2: PByte;
    Tmp: array[0..255] of Byte;
begin
  if ALastItem <= AFirstItem then
    Exit;

  Assert(AItemSize < SizeOf(Tmp),'AItemSize too big!');
  PData:=PByte(@AData);
  repeat
    I := AFirstItem;
    J := ALastItem;
    P := (AFirstItem + ALastItem) shr 1;
    repeat
      P1:=PData;Inc(P1,I*AItemSize);
      P2:=PData;Inc(P2,P*AItemSize);
      while ACompareFunction(P1, P2, AUserParameter) < 0 do
      begin
        Inc(I);
        Inc(P1,AItemSize);
      end;
      P1:=PData;Inc(P1,J*AItemSize);
      //P2:=PData;Inc(P2,P*AItemSize); already done
      while ACompareFunction(P1, P2, AUserParameter) > 0 do
      begin
        Dec(J);
        Dec(P1,AItemSize);
      end;
      if I <= J then
      begin
        P1:=PData;Inc(P1,I*AItemSize);
        P2:=PData;Inc(P2,J*AItemSize);
        Move(P2^, Tmp[0], AItemSize);
        Move(P1^, P2^, AItemSize);
        Move(Tmp[0], P1^, AItemSize);

        if P = I then
          P := J
        else if P = J then
          P := I;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if AFirstItem < J then QuickSort(AData,AFirstItem,J,AItemSize,ACompareFunction,AUserParameter);
    AFirstItem := I;
  until I >= ALastItem;
end;

function CompareLines(Item1,Item2,UserParameter:Pointer): Integer;
begin
  Result := CompareByte(PByteArray(Item1)^[0], PByteArray(Item2)^[0], SizeInt(UserParameter));
end;

function CompareDis(Item1,Item2,UserParameter:Pointer): Integer;
begin
  Result := CompareValue(PByte(UserParameter)[PInteger(Item1)^], PByte(UserParameter)[PInteger(Item2)^]);
end;

function GetMaxValueIndex(const arr: TIntegerDynArray): Integer; overload;
var
  best, ik: Integer;
begin
  Result := -1;
  best := Low(Integer);
  for ik := 0 to High(arr) do
    if arr[ik] > best then
    begin
      best := arr[ik];
      Result := ik;
    end;
end;

function GetMinValueIndex(const arr: TIntegerDynArray): Integer; overload;
var
  best, ik: Integer;
begin
  Result := -1;
  best := High(Integer);
  for ik := 0 to High(arr) do
    if arr[ik] < best then
    begin
      best := arr[ik];
      Result := ik;
    end;
end;

function GetMinValueIndex(const arr: TByteDynArray): Integer; overload;
var
  ik: Integer;
  best: Byte;
begin
  Result := -1;
  best := High(Byte);
  for ik := 0 to High(arr) do
    if arr[ik] < best then
    begin
      best := arr[ik];
      Result := ik;
    end;
end;

function GetUniqueRows(const X: TByteDynArray2): TByteDynArray2;
var
  i, j, Cnt: Integer;
begin
  Result := Copy(X);

  if Length(Result) <= 1 then
    Exit;

  QuickSort(Result[0], 0, High(Result), SizeOf(TByteDynArray), @CompareLines, Pointer(Length(Result[0])));

  Cnt := Length(Result);
  for i := High(Result) - 1 downto 0 do
    if CompareByte(Result[i, 0], Result[i + 1, 0], Length(Result[0])) = 0 then
    begin
      for j := i + 1 to Cnt - 2 do
        Result[j] := Result[j + 1];
      Dec(Cnt);
    end;
  SetLength(Result, Cnt);
end;

function CountUniqueRows(const X: TByteDynArray2): Integer;
var
  i, Cnt: Integer;
  NumAttrs: Integer;
  unique: TByteDynArray2;
begin
  Result := 0;

  if Length(X) < 1 then
    Exit;

  NumAttrs := Length(X[0]);

  unique := Copy(X);
  QuickSort(unique[0], 0, High(unique), SizeOf(TByteDynArray), @CompareLines, Pointer(NumAttrs));

  Cnt := Length(unique);
  for i := High(unique) - 1 downto 0 do
    if CompareByte(unique[i, 0], unique[i + 1, 0], NumAttrs) = 0 then
      Dec(Cnt);
  Result := Cnt;
end;

function MatchingDissim(const a: TByteDynArray; const b: TByteDynArray): UInt64; inline; overload;
begin
  Result := MatchingDissim(@a[0], @b[0], Length(a));
end;

function MatchingDissim(a: PByte; b: PByte; count: Integer): UInt64; inline; overload;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to count - 1 do
  begin
    if a[i] <> b[i] then
      Result += UInt64(1) shl cDissimSubMatchingSize;
    Result += abs(Int64(a[i]) - Int64(b[i]));
  end;
end;

{$if defined(GENERIC_DISSIM) or not defined(CPUX86_64)}

function GetMinMatchingDissim(const a: TByteDynArray2; const b: TByteDynArray; count: Integer; out bestDissim: UInt64): Integer; overload;
var
  i: Integer;
  dis, best: UInt64;
begin
  Result := -1;
  best := High(UInt64);
  for i := 0 to count - 1 do
  begin
    dis := MatchingDissim(a[i], b);
    if dis <= best then
    begin
      best := dis;
      Result := i;
    end;
  end;

  bestDissim := best;
end;

//function GetMatchingDissimSum(const a: TByteDynArray2; const b: TByteDynArray; count: Integer): UInt64;
//var
//  i: Integer;
//begin
//  Result := 0;
//  for i := 0 to count - 1 do
//    Result += MatchingDissim(a[i], b);
//end;

function GetMinMatchingDissim(a: PPByte; b: PByte; rowCount, colCount: Integer; out bestDissim: UInt64): Integer; overload;
var
  i: Integer;
  dis, best: UInt64;
begin
  Result := -1;
  best := High(UInt64);
  for i := 0 to rowCount - 1 do
  begin
    dis := MatchingDissim(a[i], b, colCount);
    if dis <= best then
    begin
      best := dis;
      Result := i;
    end;
  end;

  bestDissim := best;
end;

{$else}

function GetMinMatchingDissim_Asm(item_rcx: PByte; list_rdx: PPByte; count_r8: UInt64; pbest_r9: PUInt64): Int64; register; assembler; nostackframe;
label loop, worst;
asm
  push rbx
  push rcx
  push rsi
  push rdi
  push r8
  push r10
  push rdx

  sub rsp, 16 * 10
  movdqu oword ptr [rsp],       xmm0
  movdqu oword ptr [rsp + $10], xmm1
  movdqu oword ptr [rsp + $20], xmm2
  movdqu oword ptr [rsp + $30], xmm3
  movdqu oword ptr [rsp + $40], xmm5
  movdqu oword ptr [rsp + $50], xmm6
  movdqu oword ptr [rsp + $60], xmm7
  movdqu oword ptr [rsp + $70], xmm8
  movdqu oword ptr [rsp + $80], xmm9
  movdqu oword ptr [rsp + $90], xmm11

  movdqu xmm6, oword ptr [item_rcx]
  movdqu xmm7, oword ptr [item_rcx + $10]
  movdqu xmm8, oword ptr [item_rcx + $20]
  movdqu xmm9, oword ptr [item_rcx + $30]

  lea rbx, [list_rdx + 8 * r8]

  lea rax, [list_rdx - 8]

  xor r8, r8
  dec r8

  loop:
    mov rcx, qword ptr [list_rdx]

    movdqu xmm0, oword ptr [rcx]
    movdqu xmm1, oword ptr [rcx + $10]
    movdqu xmm2, oword ptr [rcx + $20]
    movdqu xmm3, oword ptr [rcx + $30]

    movdqa xmm11, xmm0
    psadbw xmm11, xmm6

    movdqa xmm5, xmm1
    psadbw xmm5, xmm7
    paddw xmm11, xmm5

    movdqa xmm5, xmm2
    psadbw xmm5, xmm8
    paddw xmm11, xmm5

    movdqa xmm5, xmm3
    psadbw xmm5, xmm9
    paddw xmm11, xmm5

    pcmpeqb xmm0, xmm6
    pcmpeqb xmm1, xmm7
    pcmpeqb xmm2, xmm8
    pcmpeqb xmm3, xmm9

    pmovmskb edi, xmm0
    mov rsi, rdi
    pmovmskb edi, xmm1
    rol rsi, 16
    or rsi, rdi
    pmovmskb edi, xmm2
    rol rsi, 16
    or rsi, rdi
    pmovmskb edi, xmm3
    rol rsi, 16
    or rsi, rdi

    not rsi
    popcnt rsi, rsi

    cmp rsi, r8
    ja worst

      mov r8, rsi
      mov rax, list_rdx

    worst:

    add list_rdx, 8
    cmp list_rdx, rbx
    jne loop

  movdqu xmm0, oword ptr [rsp]
  movdqu xmm1, oword ptr [rsp + $10]
  movdqu xmm2, oword ptr [rsp + $20]
  movdqu xmm3, oword ptr [rsp + $30]
  movdqu xmm5, oword ptr [rsp + $40]
  movdqu xmm6, oword ptr [rsp + $50]
  movdqu xmm7, oword ptr [rsp + $60]
  movdqu xmm8, oword ptr [rsp + $70]
  movdqu xmm9, oword ptr [rsp + $80]
  movdqu xmm11, oword ptr [rsp + $90]
  add rsp, 16 * 10

  mov qword ptr [pbest_r9], r8

  pop rdx

  sub rax, list_rdx
  sar rax, 3

  pop r10
  pop r8
  pop rdi
  pop rsi
  pop rcx
  pop rbx
end;

procedure UpdateMinDistance_Asm(item_rcx: PByte; list_rdx: PPByte; used_r8: PBoolean; mindist_r9: PUInt64; count: Integer); register; assembler;
label loop, used, start;
asm
  push rbx
  push rcx
  push rsi
  push rdi
  push rdx
  push r8
  push r9
  push r10

  sub rsp, 16 * 10
  movdqu oword ptr [rsp],       xmm0
  movdqu oword ptr [rsp + $10], xmm1
  movdqu oword ptr [rsp + $20], xmm2
  movdqu oword ptr [rsp + $30], xmm3
  movdqu oword ptr [rsp + $40], xmm5
  movdqu oword ptr [rsp + $50], xmm6
  movdqu oword ptr [rsp + $60], xmm7
  movdqu oword ptr [rsp + $70], xmm8
  movdqu oword ptr [rsp + $80], xmm9
  movdqu oword ptr [rsp + $90], xmm11

  movdqu xmm6, oword ptr [item_rcx]
  movdqu xmm7, oword ptr [item_rcx + $10]
  movdqu xmm8, oword ptr [item_rcx + $20]
  movdqu xmm9, oword ptr [item_rcx + $30]

  mov eax, count
  lea rbx, [list_rdx + 8 * rax]

  xor eax, eax

  jmp start

  loop:
    mov rcx, qword ptr [list_rdx]
    add list_rdx, 8

    movdqu xmm0, oword ptr [rcx]
    movdqu xmm1, oword ptr [rcx + $10]
    movdqu xmm2, oword ptr [rcx + $20]
    movdqu xmm3, oword ptr [rcx + $30]

    movdqa xmm11, xmm0
    psadbw xmm11, xmm6

    movdqa xmm5, xmm1
    psadbw xmm5, xmm7
    paddw xmm11, xmm5

    movdqa xmm5, xmm2
    psadbw xmm5, xmm8
    paddw xmm11, xmm5

    movdqa xmm5, xmm3
    psadbw xmm5, xmm9
    paddw xmm11, xmm5

    pcmpeqb xmm0, xmm6
    pcmpeqb xmm1, xmm7
    pcmpeqb xmm2, xmm8
    pcmpeqb xmm3, xmm9

    pmovmskb edi, xmm0
    mov rsi, rdi
    pmovmskb edi, xmm1
    rol rsi, 16
    or rsi, rdi
    pmovmskb edi, xmm2
    rol rsi, 16
    or rsi, rdi
    pmovmskb edi, xmm3
    rol rsi, 16
    or rsi, rdi

    not rsi
    popcnt rsi, rsi

    mov rax, qword ptr [mindist_r9]
    cmp rsi, rax
    cmovb rax, rsi
    mov qword ptr [mindist_r9], rax

    used:

    inc used_r8
    add mindist_r9, 8

    start:

    test byte ptr [used_r8], 0
    jne used

    cmp list_rdx, rbx
    jne loop

  movdqu xmm0, oword ptr [rsp]
  movdqu xmm1, oword ptr [rsp + $10]
  movdqu xmm2, oword ptr [rsp + $20]
  movdqu xmm3, oword ptr [rsp + $30]
  movdqu xmm5, oword ptr [rsp + $40]
  movdqu xmm6, oword ptr [rsp + $50]
  movdqu xmm7, oword ptr [rsp + $60]
  movdqu xmm8, oword ptr [rsp + $70]
  movdqu xmm9, oword ptr [rsp + $80]
  movdqu xmm11, oword ptr [rsp + $90]
  add rsp, 16 * 10

  pop r10
  pop r9
  pop r8
  pop rdx
  pop rdi
  pop rsi
  pop rcx
  pop rbx

end;

function GetMinMatchingDissim(const a: TByteDynArray2; const b: TByteDynArray; count: Integer; out bestDissim: UInt64): Integer; overload;
var
  bd: UInt64;
begin
  Result := GetMinMatchingDissim_Asm(@b[0], PPByte(@a[0]), count, @bd);
  bestDissim := bd;
end;

function GetMinMatchingDissim(a: PPByte; b: PByte; rowCount, colCount: Integer; out bestDissim: UInt64): Integer; overload;
var
  bd: UInt64;
begin
  Result := GetMinMatchingDissim_Asm(b, a, rowCount, @bd);
  bestDissim := bd;
end;

{$endif}

function TKModes.CountClusterMembers(cluster: Integer): Integer;
var
  i: Integer;
  pm: PInteger;
begin
  Result := 0;
  pm := @membship[0];

  for i := 0 to High(membship) do
  begin
    Inc(Result, Ord(pm^ = cluster));
    Inc(pm);
  end;
end;

function TKModes.GetMaxClusterMembers(out member_count: Integer): Integer;
var
  quantum, mc_loc, mc, cluster, i: Integer;
  pm0, pm1, pm2, pm3: PInteger;
begin
  Result := 0;
  mc := 0;
  quantum := Length(membship) shr 2;

  for cluster := 0 to NumClusters - 1 do
  begin
    mc_loc := 0;
    pm0 := @membship[quantum * 0];
    pm1 := @membship[quantum * 1];
    pm2 := @membship[quantum * 2];
    pm3 := @membship[quantum * 3];

    for i := 0 to quantum - 1 do
    begin
      Inc(mc_loc, Ord(pm0^ = cluster)); Inc(pm0);
      Inc(mc_loc, Ord(pm1^ = cluster)); Inc(pm1);
      Inc(mc_loc, Ord(pm2^ = cluster)); Inc(pm2);
      Inc(mc_loc, Ord(pm3^ = cluster)); Inc(pm3);
    end;

    for i := (quantum shl 2) to Length(membship) - 1 do
    begin
      Inc(mc_loc, Ord(pm3^ = cluster)); Inc(pm3);
    end;

    if mc_loc >= mc then
    begin
      mc := mc_loc;
      Result := cluster;
    end;
  end;

  member_count := mc;
end;


{$if not(defined(GENERIC_DISSIM) or not defined(CPUX86_64))}
type
  TUMD = record
    NumBins, NumPoints, BinSize, icenter: Integer;
    mindistance: TUInt64DynArray;
    used: TBooleanDynArray;
    X: TByteDynArray2;
  end;
  PUMD = ^TUMD;

procedure DoUMD(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
var
  UMD: PUMD;
  idx, cnt: Integer;
begin
  UMD := PUMD(AData);

  cnt := UMD^.BinSize;
  idx := AIndex * cnt;
  if idx >= UMD^.NumBins - 1 then
    cnt :=  UMD^.NumPoints - idx;

  UpdateMinDistance_Asm(@UMD^.X[UMD^.icenter, 0], PPByte(@UMD^.X[idx]), @UMD^.used[idx], @UMD^.mindistance[idx], cnt);
end;
{$endif}

function TKModes.InitFarthestFirst(InitPoint: Integer): TByteDynArray2;
var
  icentroid, ifarthest, i: Integer;
  max: UInt64;
  used: TBooleanDynArray;
  mindistance: TUInt64DynArray;

  procedure UpdateMinDistance(icenter: Integer); inline;
{$if defined(GENERIC_DISSIM) or not defined(CPUX86_64)}
  var
    i: Integer;
    dis: UInt64;
  begin
    for i := 0 to NumPoints - 1 do
      if not used[i] then
      begin
        dis := MatchingDissim(X[icenter], X[i]);
        if dis < mindistance[i] then
          mindistance[i] := dis;
      end;
  end;
{$else}

  const
    cBinSize = 524288;
  var
    UMD: TUMD;
  begin
    if (NumThreads <= 1) and not Assigned(Concurrency) then
    begin
      UpdateMinDistance_Asm(@X[icenter, 0], PPByte(@X[0]), @used[0], @mindistance[0], NumPoints);
    end
    else
    begin
      UMD.NumBins := (NumPoints - 1) div cBinSize + 1;
      UMD.NumPoints := NumPoints;
      UMD.BinSize := min(NumPoints, cBinSize);
      UMD.icenter := icenter;
      UMD.mindistance := mindistance;
      UMD.used := used;
      UMD.X := X;
      FPTP.DoParallel(@DoUMD, 0, UMD.NumBins - 1, @UMD, GetConcurrentNumThreads);
    end;
  end;

{$endif}

begin
  SetLength(Result, NumClusters, NumAttrs);
  SetLength(used, NumPoints);
  SetLength(mindistance, NumPoints);

  for icentroid := 0 to NumClusters - 1 do
    FillByte(Result[icentroid, 0], NumAttrs, High(Byte));
  FillChar(used[0], NumPoints, False);
  FillQWord(mindistance[0], NumPoints, High(UInt64));

  icentroid := 0;
  ifarthest := InitPoint;
  Move(X[ifarthest, 0], Result[icentroid, 0], NumAttrs);
  used[ifarthest] := True;
  UpdateMinDistance(ifarthest);

  for icentroid := 1 to NumClusters - 1 do
  begin
    max := 0;
    ifarthest := InitPoint;
    for i := 0 to NumPoints - 1 do
      if (MinDistance[i] >= max) and not Used[i] then
      begin
        max := MinDistance[i];
        ifarthest := i;
      end;

    Move(X[ifarthest, 0], Result[icentroid, 0], NumAttrs);
    used[ifarthest] := True;
    UpdateMinDistance(ifarthest);
  end;
end;

procedure TKModes.MovePointCat(const point: TByteDynArray; ipoint, to_clust, from_clust: Integer);
var
  iattr, curattr, current_attribute_value_freq, current_centroid_value, current_centroid_freq, old_centroid_value: Integer;
  to_attr_counts, from_attr_counts: TIntegerDynArray;
begin
  membship[ipoint] := to_clust;

  for iattr := 0 to High(point) do
  begin
    curattr := point[iattr];

    to_attr_counts := cl_attr_freq[to_clust, iattr];
    from_attr_counts := cl_attr_freq[from_clust, iattr];

    Inc(to_attr_counts[curattr]);

    current_attribute_value_freq := to_attr_counts[curattr];
    current_centroid_value := centroids[to_clust, iattr];
    current_centroid_freq := to_attr_counts[current_centroid_value];
    if current_centroid_freq < current_attribute_value_freq then
      centroids[to_clust, iattr] := curattr;

    Dec(from_attr_counts[curattr]);

    old_centroid_value := centroids[from_clust, iattr];
    if old_centroid_value = curattr then
      centroids[from_clust, iattr] := GetMaxValueIndex(from_attr_counts);
  end;
end;

constructor TKModes.Create(aNumThreads: Integer; aMaxIter: Integer; aLog: Boolean; aLogLabel: String;
  aConcurrency: PInteger);
begin
  inherited Create;

  FPTP := TProcThreadPool.Create;
  Self.MaxIter := aMaxIter;
  Self.NumThreads := aNumThreads;
  Self.Log := aLog;
  Self.LogLabel := aLogLabel;
  Self.Concurrency := aConcurrency;
end;

destructor TKModes.Destroy;
begin
  inherited Destroy;

  FPTP.Free;
end;

procedure TKModes.DoGMMD(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
var
  dis: UInt64;
begin
  if AIndex < NumPoints then
  begin
    FGMMD.clust[AIndex] := GetMinMatchingDissim(FGMMD.centroids, FGMMD.X[AIndex], NumClusters, NumAttrs, dis);
    if Assigned(FGMMD.dis) then
      FGMMD.dis[AIndex] := dis;
  end;
end;

procedure TKModes.FinishGMMD;
begin
  FGMMD.clust := nil;
  FGMMD.dis := nil;
  FGMMD.X := nil;
  FGMMD.centroids := nil;
end;

function TKModes.GetConcurrentNumThreads: Integer;
begin
  Result := NumThreads;
  if Assigned(Concurrency) then
    Result := max(Result, FPTP.MaxThreadCount - (Concurrency^ - 1) * NumThreads);
end;

function TKModes.KModesIter(var Seed: Cardinal; out Cost: UInt64): Integer;
const
  cBinSize = 960;
var
  ipoint, old_clust, from_clust, rindx, cnt, dummy, i, bin, last: Integer;
  cost_acc: UInt64;
  clust, choices: TIntegerDynArray;
  dis: TUInt64DynArray;
begin
  Result := 0;
  cost_acc := 0;

  SetLength(choices, NumPoints);
  SetLength(clust, NumPoints);
  SetLength(dis, NumPoints);

  FGMMD.clust := @clust[0];
  FGMMD.dis := @dis[0];
  FGMMD.X := PPByte(@X[0]);
  FGMMD.centroids := PPByte(@centroids[0]);

  for bin := 0 to ((NumPoints - 1) div cBinSize + 1) - 1 do
  begin
    last := min((bin + 1) * cBinSize, NumPoints) - 1;

    if (NumThreads <= 1) and not Assigned(Concurrency) then
    begin
      for ipoint := bin * cBinSize to last do
        clust[ipoint] := GetMinMatchingDissim(centroids, X[ipoint], Length(centroids), dis[ipoint]);
    end
    else
    begin
      FPTP.DoParallel(@DoGMMD, bin * cBinSize, last, nil, GetConcurrentNumThreads);
    end;

    for ipoint := bin * cBinSize to last do
    begin
      Inc(cost_acc, dis[ipoint]);

      if membship[ipoint] <> clust[ipoint] then
      begin
        Inc(Result);
        old_clust := membship[ipoint];

        MovePointCat(X[ipoint], ipoint, clust[ipoint], old_clust);

        if CountClusterMembers(old_clust) = 0 then
        begin
          from_clust := GetMaxClusterMembers(dummy);
          //writeln('zero', #9, from_clust, #9, dummy);

          cnt := 0;
          for i := 0 to High(membship) do
            if membship[i] = from_clust then
            begin
              choices[cnt] := i;
              Inc(cnt);
            end;

          rindx := choices[RandInt(cnt, Seed)];

          MovePointCat(X[rindx], rindx, old_clust, from_clust);
        end;
      end;
    end;
  end;

  FinishGMMD;

  Cost := cost_acc;
end;

function TKModes.ComputeKModes(const ADataset: TByteDynArray2; ANumClusters, ANumInit, ANumModalities: Integer;
  out FinalLabels: TIntegerDynArray; out FinalCentroids: TByteDynArray2): Integer;
const
  CMaxWorseGraces = 3;
var
  init: TByteDynArray2;
  all: array of TKmodesRun;
var
  i, j, init_no, iattr, ipoint, ik, summemb, itr, bestitr, moves, totalmoves, worsecounter: Integer;
  best, dis: UInt64;
  converged: Boolean;
  prevcost, cost, bestcost: UInt64;
  InvGoldenRatio, GRAcc: Single;
  Seed: Cardinal;
  bestmembship: TIntegerDynArray;
  bestcentroids: TByteDynArray2;
begin
  Seed := $42381337;

  X := ADataset;

  NumPoints := Length(X);
  NumClusters := ANumClusters;

  NumAttrs := 0;
  if NumPoints > 0 then
    NumAttrs := Length(X[0]);

  if NumThreads <= 0 then
    NumThreads := ProcThreadPool.MaxThreadCount;

  if MaxIter < 0 then
    MaxIter := MaxInt;

  init := nil;

  if ANumInit <= 0 then
  begin
    SetLength(all, 1);
    all[0].StartingPoint := -ANumInit;
  end
  else
  begin
    SetLength(all, ANumInit);
    InvGoldenRatio := power(NumPoints, 1 / ANumInit);
    GRAcc := 1;
    for i := 0 to ANumInit - 1 do
    begin
      all[i].StartingPoint := Round(GRAcc) - 1;
      if (i > 0) and (all[i].StartingPoint <= all[i - 1].StartingPoint) then
        all[i].StartingPoint := Min(NumPoints - 1, all[i - 1].StartingPoint + 1);
      GRAcc := GRAcc * InvGoldenRatio;
    end;
  end;

  for init_no := 0 to High(all) do
  begin
    SetLength(membship, NumPoints);
    SetLength(cl_attr_freq, NumClusters, NumAttrs, ANumModalities);

    if init = nil then
      centroids := InitFarthestFirst(all[init_no].StartingPoint)
    else
      centroids := init;

    FillDWord(membship[0], NumPoints, $ffffffff);
    for j := 0 to NumClusters - 1 do
      for i := 0 to NumAttrs - 1 do
        FillDWord(cl_attr_freq[j, i, 0], ANumModalities, 0);


    if (NumThreads <= 1) and not Assigned(Concurrency) then
    begin
      for ipoint := 0 to NumPoints - 1 do
        membship[ipoint] := GetMinMatchingDissim(centroids, X[ipoint], Length(centroids), dis);
    end
    else
    begin
      FGMMD.clust := @membship[0];
      FGMMD.dis := nil;
      FGMMD.X := PPByte(@X[0]);
      FGMMD.centroids := PPByte(@centroids[0]);
      FPTP.DoParallel(@DoGMMD, 0, NumPoints - 1, nil, GetConcurrentNumThreads);
      FinishGMMD;
    end;

    for ipoint := 0 to NumPoints - 1 do
      for iattr := 0 to NumAttrs - 1 do
        Inc(cl_attr_freq[membship[ipoint], iattr, X[ipoint, iattr]]);

    for ik := 0 to NumClusters - 1  do
    begin
      summemb := CountClusterMembers(ik);
      if summemb = 0 then
      begin
        for iattr := 0 to NumAttrs - 1 do
          centroids[ik, iattr] := X[RandInt(NumPoints, Seed), iattr]
      end
      else
      begin
         for iattr := 0 to NumAttrs - 1 do
           centroids[ik, iattr] := GetMaxValueIndex(cl_attr_freq[ik, iattr]);
      end;
    end;

    WriteLn(LogLabel, 'Init done');

    itr := 0;
    converged := False;
    prevcost := High(UInt64);
    worsecounter := 0;
    totalmoves := 0;
    bestitr := 0;
    bestcost := High(UInt64);
    bestmembship := nil;
    bestcentroids := nil;

    while (itr < MaxIter) and not converged do
    begin
      Inc(itr);

      moves := KModesIter(Seed, cost);

      converged := cost >= prevcost;
      if converged and SameValue(cost, prevcost, prevcost div 1000) then
      begin
        Inc(worsecounter);
        if worsecounter < CMaxWorseGraces then
          converged := False;
      end;
      converged := converged  or (moves = 0);

      if cost < bestcost then
      begin
        bestitr := itr;
        bestcost := cost;
        bestmembship := Copy(membship);
        bestcentroids := Copy(centroids);
      end;

      prevcost := cost;

      totalmoves += moves;

      if Log then
        WriteLn(LogLabel, 'Itr: ', itr:3, ' Moves: ', moves: 6, ' Cost: ', cost:16);
    end;

    WriteLn(LogLabel, 'Itr: ', itr:3, ' Finished!'#9'BestItr: ', bestitr:3, ' BestCost: ', bestcost:16);

    all[init_no].Labels := bestmembship;
    all[init_no].Centroids := bestcentroids;
    all[init_no].Cost := bestcost;
    all[init_no].NIter := bestitr;
    all[init_no].TotalMoves := totalmoves;
  end;

  j := 0;
  best := High(UInt64);
  for i := 0 to High(all) do
    if all[i].Cost < best then
    begin
      best := all[i].Cost;
      j := i;
    end;

  FinalLabels := all[j].Labels;
  FinalCentroids := all[j].Centroids;
  Result := Length(FinalCentroids);
end;

end.

