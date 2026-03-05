unit orthogonal_kmeans;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}

// yakmo -- yet another k-means via orthogonalization
//  $Id: yakmo.h 1866 2015-01-21 10:25:43Z ynaga $
// Copyright (c) 2012-2015 Naoki Yoshinaga <ynaga@tkl.iis.u-tokyo.ac.jp>
//
// ported to freepascal by GliGli

interface

uses
  Classes, SysUtils, StrUtils, Math, Types, mtpool, utils, extern;

const
  cKMTMinBinSize = 8;

type
  TKFloat = Double;

{$CODEALIGN RECORDMIN=SizeOf(TKFloat)}

  PKFloat = ^TKFloat;
  PPKFloat = ^PKFloat;
  TKFloatArray = array of TKFloat;
  TKFloatArray2 = array of TKFloatArray;

  TKInit = (kiRandom, kiKMeansPP);

  { TKOptions }

  TKOptions  = record // option handler
    init: TKInit;
    k: Cardinal;
    m: Cardinal;
    iter: Integer;
    normalize: Boolean;
    verbosity: Cardinal;
    quiet: Boolean;
    threads: Cardinal;
  end;

// implementation of space-efficient k-means using triangle inequality:
//   G. Hamerly. Making k-means even faster (SDM 2010)

  { TKNode }

  TKNode = record
    idx: Cardinal;
    val: TKFloat;
    constructor Create(AIdx: Cardinal; AVal: TKFloat);
    class function CompareNodes(Item1,Item2,UserParameter:Pointer):Integer; static;
  end;

{$if SizeOf(TKNode) <> SizeOf(TKFloat) * 2}
  {$error misaligned SizeOf(TKNode) !}
{$endif}

  PKNode = ^TKNode;
  TKNodeArray = array of TKNode;

  TKPoint = class;
  TKCentroid = class;
  TKKMeans = class;
  TKCentroidArray = array of TKCentroid;
  TKPointArray = array of TKPoint;
  TKKMeansArray = array of TKKMeans;

  { TKMTData }

  TKMTData = record
    BinSize: Cardinal;
    NumThreads: Cardinal;
    LastThreadIndex: Cardinal;
    Buffer: TKFloatArray;
    constructor Create(ASize, ANumThreads: Cardinal);
  end;

  { TKPoint }

  TKPoint = class
  private
    FSize: Cardinal;
    FBody: PKNode;
    FNorm: TKFloat;
    FWeight: Cardinal;
    FMTPoolRef: TMTPool;
  public
    up_d: TKFloat;  // distance to the closest centroid
    lo_d: TKFloat;  // distance to the second closest centroid
    id: Cardinal;   // cluster id

    constructor Create(AN: PKNode; ASize: Cardinal; ANorm: TKFloat; AWeight: Cardinal);

    procedure CopyFrom(const AP: TKPoint);
    function calc_ip(const AC: TKCentroid): TKFloat;
    function calc_dist(const AC: TKCentroid): TKFloat;
    procedure set_closest(const ACS: TKCentroidArray);
    procedure shrink(ANF: Cardinal);
    procedure project(const AC: TKCentroid);

    function nbegin(): PKNode;
    function nend(): PKNode;
    function back(): PKNode;
    function empty(): Boolean;
    procedure clear();

    property Norm: TKFloat read FNorm;
    property Weight: Cardinal read FWeight;
    property Size: Cardinal read FSize;
    property Body: PKNode read FBody;
  end;

  { TKCentroid }

  TKCentroid = class
  private
    FNorm: TKFloat;  // norm
    FDV: PKFloat;
    FSum: PKFloat;
    FBody: PKNode;
    FNElm: Cardinal;  // # elements belonging to the cluster
    FNF: Cardinal;    // # features
    FSize: Cardinal;  // # nozero features
    FMTPoolRef: TMTPool;
  public
    delta: TKFloat;  // moved distance
    next_d: TKFloat; // distance to neighbouring centroind

    constructor Create(AP: TKPoint; ANF: Cardinal; ADelegate: Boolean = False);

    procedure pop(AP: TKPoint);
    procedure push(AP: TKPoint);
    function calc_dist(const AC: TKCentroid; ASkip: Boolean = True): TKFloat;
    procedure set_closest(const ACS: TKCentroidArray);
    procedure reset();
    procedure compress();
    procedure decompress();
    procedure get_values (AValues: PKFloat);
    procedure clear();

    property Norm: TKFloat read FNorm;
  end;

  { TKKmeans }

  TKKmeans = class
  private
    FOpt: TKOptions;
    FPoints: TKPointArray;
    FCentroids: TKCentroidArray;
    FBody: TKNodeArray;
    FNF: Cardinal;
    FObj: TKFloat;
    FMTPoolRef: TMTPool;
  public
    constructor Create(const AOpt: TKOptions; ARowCount, AColCount: Cardinal);
    destructor Destroy; override;

    procedure clear_point();
    procedure clear_centroid();
    class function read_point_fl(AEx, AExEnd: PKFloat; const ATmp: TKNodeArray; AWeight: Cardinal; ANormalize: Boolean = false): TKPoint;
    procedure set_point_fl(AEx, AExEnd: PKFloat; ARow, AWeight: Cardinal; ANormalize: Boolean);
    procedure delegate(AKM: TKKmeans);
    procedure compress();
    procedure decompress();
    procedure push_centroid(AP: TKPoint; AIdx: Cardinal; ADelegate: Boolean = False);
    // implementation of fast k-means:
    //   D. Arthur and S. Vassilvitskii. k-means++: the advantages of careful seeding. SODA (2007)
    procedure init();
    procedure update_bounds();
    function getObj(): TKFloat;
    procedure run();

    property point: TKPointArray read FPoints;
    property centroid: TKCentroidArray read FCentroids;
    property NF: Cardinal read FNF;
  end;

  // implementation of orthogonal k-means:
  //   Y. Cui et al. Non-redundant multi-view clustering via orthogonalization (ICDM 2007)

  { TOrthogonalKmeans }

  TOrthogonalKmeans = class
  private
    FOpt: TKOptions;
    FKMs: TKKMeansArray;
    FObjective: TKFloat;
    FMTPool: TMTPool;
  public
    constructor Create(const option: TKOptions); overload;
    constructor Create(k: Cardinal; maxIter: Integer; initType: TKInit; numThreads: Cardinal; isVerbose: Boolean = False); overload;
    destructor Destroy; override;

    procedure load_train_data(rowCount, colCount: Cardinal; trainDS: PPKFloat; trainWeights: PCardinal = nil);
    procedure train_on_data(pointToCluster: PInteger);
    procedure get_centroids(centroids: PPKFloat);

    function Process(const trainDS: TKFloatArray2; var pointToCluster: TIntegerDynArray; const centroids: TKFloatArray2; const trainWeights: TCardinalDynArray = nil): Double;

    property Objective: Double read FObjective;
  end;

implementation

{ TKNode }

constructor TKNode.Create(AIdx: Cardinal; AVal: TKFloat);
begin
  idx := AIdx;
  val := AVal;
end;

class function TKNode.CompareNodes(Item1, Item2, UserParameter: Pointer): Integer;
var
  N1: PKNode absolute Item1;
  N2: PKNode absolute Item2;
begin
  Result := CompareValue(N1^.idx, N2^.idx);
end;

{ TKPoint }

constructor TKPoint.Create(AN: PKNode; ASize: Cardinal; ANorm: TKFloat; AWeight: Cardinal);
begin
  FSize := ASize;
  FNorm := ANorm;
  FWeight := AWeight;
  FBody := AllocMem(FSize * SizeOf(TKNode));
  Move(AN^, FBody^, FSize * SizeOf(TKNode));
end;

procedure TKPoint.CopyFrom(const AP: TKPoint);
begin
  up_d := AP.up_d;
  lo_d := AP.lo_d;
  id := AP.id;
  FSize := AP.FSize;
  FBody := AP.FBody;
  FNorm := AP.FNorm;
  FWeight := AP.FWeight;
end;

function TKPoint.calc_ip(const AC: TKCentroid): TKFloat;
var
  n: PKNode;
begin
  // return inner product between this point and the given centroid

  Result := 0.0;

  n := nbegin();
  while n <> nend() do
  begin
    Result += n^.val * AC.FDV[n^.idx];
    Inc(n);
  end;
end;

function TKPoint.calc_dist(const AC: TKCentroid): TKFloat;
var
  n: PKNode;
begin
  // return distance from this point to the given centroid

  Result := 0.0;
  Result += FNorm + AC.Norm;

  n := nbegin();
  while n <> nend() do
  begin
    Result -= 2 * n^.val * AC.FDV[n^.idx];
    Inc(n);
  end;

  Result := Max(0.0, Result * FWeight);
end;

procedure TKPoint.set_closest(const ACS: TKCentroidArray);
var
  mt: TKMTData;

  procedure DoMT(AIndex: PtrInt; AData: Pointer);
  var
    i, s, e: PtrInt;
  begin
    TMTPool.CalcBlock(AIndex, mt.BinSize, Length(mt.Buffer), s, e);
    for i := s to e do
      mt.Buffer[i] := calc_dist(ACS[i]);
  end;

var
  i, id0: Cardinal;
  d0, d1, di: TKFloat;
begin
  mt := TKMTData.Create(Length(ACS), FMTPoolRef.MaxThreads);
  FMTPoolRef.DoLocalProc(@DoMT, 0, mt.LastThreadIndex, @mt);

  i := IfThen(id = 0, 1, 0); // second closest (cand)
  id0 := id;
  d0 := mt.Buffer[id0];
  d1 := mt.Buffer[i];

  if (d1 < d0) then
  begin
    id := i;
    Exchange(d0, d1);
  end;

  for i := 0 to High(ACS) do
  begin
    if i = id0 then
      Continue;

    di := mt.Buffer[i];

    if di < d0 then
    begin
      d1 := d0;
      d0 := di;
      id := i;
    end
    else if di < d1 then
    begin
      d1 := di;
    end;
  end;

  up_d := Sqrt(d0);
  lo_d := Sqrt(d1);
end;

procedure TKPoint.shrink(ANF: Cardinal);
begin
   while not empty() and (back()^.idx > ANF) do
    Dec(FSize);
end;

procedure TKPoint.project(const AC: TKCentroid);
var
  i: Integer;
  norm_ip, v: TKFloat;
begin
  norm_ip := DivDef(calc_ip(AC), AC.Norm, 0.0);

  up_d := 0.0; lo_d := 0.0; id := 0; FNorm := 0.0; // reset

  for i := 0 to FSize - 1 do
  begin
    v := AC.FDV[FBody[i].idx] * norm_ip;
    FNorm += Sqr(v);
    FBody[i].val := v;
  end;
end;

function TKPoint.nbegin(): PKNode;
begin
  Result := FBody;
end;

function TKPoint.nend(): PKNode;
begin
  Result := FBody + FSize;
end;

function TKPoint.back(): PKNode;
begin
  Result := @FBody[FSize - 1];
end;

function TKPoint.empty(): Boolean;
begin
  Result := FSize = 0;
end;

procedure TKPoint.clear();
begin
  if Assigned(FBody) then FreeMemAndNil(FBody);
end;

{ TKCentroid }

constructor TKCentroid.Create(AP: TKPoint; ANF: Cardinal; ADelegate: Boolean);
var
  sz: Cardinal;
  n: PKNode;
begin
  FNorm := AP.Norm;
  FNF := ANF;

  if ADelegate then
  begin
    FSize := AP.Size;
    FBody := AP.Body; // ADelegate
  end
  else
  begin
    // workaround for a bug in value initialization in gcc 4.0
    sz := (FNF + 1) * SizeOf(TKFloat);

    FDV := AllocMem(sz);
    FSum := AllocMem(sz);

    FillChar(FDV^, sz, 0);
    FillChar(FSum^, sz, 0);

    n := AP.nbegin();
    while n <> AP.nend() do
    begin
      FDV[n^.idx] := n^.val;
      Inc(n);
    end;
  end;
end;

procedure TKCentroid.pop(AP: TKPoint);
var
  n: PKNode;
begin
  n := AP.nbegin();
  while n <> AP.nend() do
  begin
    FSum[n^.idx] -= n^.val * AP.Weight;
    Inc(n);
  end;

  FNElm -= AP.Weight;
end;

procedure TKCentroid.push(AP: TKPoint);
var
  n: PKNode;
begin
  n := AP.nbegin();
  while n <> AP.nend() do
  begin
    FSum[n^.idx] += n^.val * AP.Weight;
    Inc(n);
  end;

  FNElm += AP.Weight;
end;

function TKCentroid.calc_dist(const AC: TKCentroid; ASkip: Boolean): TKFloat;
var
  d: Cardinal;
  cand: TKFloat;
begin
  // return distance from this centroid to the given centroid
  Result := 0.0;

  if ASkip then
  begin
    cand := Sqr(next_d);
    for d := 0 to FNF do
    begin
      Result += Sqr(FDV[d] - AC.FDV[d]);
      if Result > cand then
        Break;
    end;
  end
  else
  begin
    for d := 0 to FNF do
      Result += Sqr(FDV[d] - AC.FDV[d]);
  end;
end;

procedure TKCentroid.set_closest(const ACS: TKCentroidArray);
var
  mt: TKMTData;

  procedure DoMT(AIndex: PtrInt; AData: Pointer);
  var
    i, s, e: PtrInt;
  begin
    TMTPool.CalcBlock(AIndex, mt.BinSize, Length(mt.Buffer), s, e);
    for i := s to e do
      mt.Buffer[i] := calc_dist(ACS[i]);
  end;

var
  i: Cardinal;
  di: TKFloat;
begin
  mt := TKMTData.Create(Length(ACS), FMTPoolRef.MaxThreads);
  FMTPoolRef.DoLocalProc(@DoMT, 0, mt.LastThreadIndex, @mt);

  i := IfThen(Self = ACS[0], 1, 0);
  next_d := mt.Buffer[i];
  for i := i + 1 to High(ACS) do
  begin
    if Self = ACS[i] then
      Continue;
    di := mt.Buffer[i];
    if di < next_d then
      next_d := di;
  end;

  next_d := Sqrt(next_d);
end;

procedure TKCentroid.reset();
var
  i: Cardinal;
  v: TKFloat;
begin
  // move center
  delta := 0.0; FNorm := 0.0;

  for i := 0 to FNF do
  begin
    v := DivDef(FSum[i], FNElm, 0.0);
    delta += Sqr(v - FDV[i]);
    FNorm += Sqr(v);
    FDV[i] := v;
  end;

  delta := Sqrt(delta);
end;

procedure TKCentroid.compress();
var
  i, j: Cardinal;
begin
  FSize := 0;
  for i := 0 to FNF do
    if FDV[i] <> 0.0 then
      Inc(FSize);
  FBody := AllocMem(FSize * SizeOf(TKNode));

  j := 0;
  for i := 0 to FNF do
    if FDV[i] <> 0.0 then
    begin
      FBody[j].idx := i;
      FBody[j].val := FDV[i];
      Inc(j);
    end;

  FreeMemAndNil(FDV);
  FreeMemAndNil(FSum);
end;

procedure TKCentroid.decompress();
var
  i: Integer;
  sz: Integer;
begin
  sz := (FNF + 1) * SizeOf(TKFloat);
  FDV := AllocMem(sz);
  FillChar(FDV^, sz, 0);

  for i := 0 to FSize - 1 do
    FDV[FBody[i].idx] := FBody[i].val;

  FreeMemAndNil(FBody);
end;

procedure TKCentroid.get_values(AValues: PKFloat);
var
  i: Integer;
begin
  if FNF > 0 then FillChar(AValues^, FNF * sizeof(TKFloat), 0);

  for i := 0 to FSize - 1 do
    AValues[FBody[i].idx] := FBody[i].val;
end;

procedure TKCentroid.clear();
begin
  if Assigned(FDV) then FreeMemAndNil(FDV);
  if Assigned(FSum) then FreeMemAndNil(FSum);
  if Assigned(FBody) then FreeMemAndNil(FBody);
end;

{ TKKmeans }

constructor TKKmeans.Create(const AOpt: TKOptions; ARowCount, AColCount: Cardinal);
begin
  FObj := NaN;
  FOpt := AOpt;
  SetLength(FPoints, ARowCount);
  SetLength(FCentroids, FOpt.k);
  SetLength(FBody, AColCount);
end;

destructor TKKmeans.Destroy;
begin
  clear_point();
  clear_centroid();
end;

procedure TKKmeans.clear_point();
var
  i: Cardinal;
begin
  for i := 0 to High(FPoints) do
    FPoints[i].clear();
  SetLength(FPoints, 0);
end;

procedure TKKmeans.clear_centroid();
var
  i: Cardinal;
begin
  for i := 0 to High(FCentroids) do
    FCentroids[i].clear();
  SetLength(FCentroids, 0);
end;

class function TKKmeans.read_point_fl(AEx, AExEnd: PKFloat; const ATmp: TKNodeArray; AWeight: Cardinal; ANormalize: Boolean): TKPoint;
var
  i, fi: Cardinal;
  norm, v: TKFloat;
  p: PKFloat;
begin
  if Assigned(ATmp) then FillChar(ATmp[0], Length(ATmp) * SizeOf(TKNode), 0);
  norm := 0;
  p := AEx;
  fi := 0;
  while p <> AExEnd do
  begin
    v := p^;
    ATmp[fi].idx := fi;
    ATmp[fi].val := v;
    norm += Sqr(v);
    Inc(fi);
    Inc(p);
  end;

  QuickSort(ATmp[0], 0, fi - 1, SizeOf(TKNode), @TKNode.CompareNodes);

  if ANormalize then // ANormalize
  begin
    norm := Sqrt(norm);
    for i := 0 to fi - 1 do
      ATmp[i].val := DivDef(ATmp[i].val, norm, 0.0);
    norm := 1.0;
  end;

  Result := TKPoint.Create(@ATmp[0], fi, norm, AWeight);
end;

procedure TKKmeans.set_point_fl(AEx, AExEnd: PKFloat; ARow, AWeight: Cardinal; ANormalize: Boolean);
var
  p: TKPoint;
begin
  p := read_point_fl(AEx, AExEnd, FBody, AWeight, ANormalize);
  p.FMTPoolRef := FMTPoolRef;
  FPoints[ARow] := p;

  if not p.empty() then
    FNF := Max(p.back()^.idx, FNF);
end;

procedure TKKmeans.delegate(AKM: TKKmeans);
var
  tmp: TKPointArray;
begin
  tmp := FPoints;
  FPoints := AKM.FPoints;
  AKM.FPoints := tmp;

  AKM.FNF := FNF;
end;

procedure TKKmeans.compress();
var
  i: Cardinal;
begin
  for i := 0 to High(FCentroids) do
      FCentroids[i].compress();
end;

procedure TKKmeans.decompress();
var
  i: Cardinal;
begin
  for i := 0 to High(FCentroids) do
      FCentroids[i].decompress();
end;

procedure TKKmeans.push_centroid(AP: TKPoint; AIdx: Cardinal; ADelegate: Boolean);
begin
  FCentroids[AIdx] := TKCentroid.Create(AP, FNF, ADelegate);
  FCentroids[AIdx].FMTPoolRef := FMTPoolRef;
end;

function CompareKFloats(Item1,Item2,UserParameter:Pointer):Integer;
var
  d1: PKFloat absolute Item1;
  d2: PKFloat absolute Item2;
begin
  Result := CompareValue(d1^, d2^);
end;

procedure TKKmeans.init();
var
  mt: TKMTData;
  centroidIdx: Cardinal;

  procedure DoMT(AIndex: PtrInt; AData: Pointer);
  var
    i, s, e: PtrInt;
  begin
    TMTPool.CalcBlock(AIndex, mt.BinSize, Length(mt.Buffer), s, e);
    for i := s to e do
      mt.Buffer[i] := FPoints[i].calc_dist(FCentroids[centroidIdx]);
  end;

var
  j, c, seed: Cardinal;
  obj, key, di: TKFloat;
  p: TKPoint;
  chosen: TBooleanDynArray;
  r: TKFloatArray;
begin
  seed := CRandomSeed;
  obj := 0;
  if FOpt.init = kiKMeansPP then
  begin
    SetLength(r, Length(FPoints));
    SetLength(chosen, Length(FPoints));
  end;

  mt := TKMTData.Create(Length(FPoints), FOpt.threads);

  for centroidIdx := 0 to FOpt.k - 1 do
  begin
    c := 0;
    repeat
      case FOpt.init of
        kiRandom:
          c := RandInt(Length(FPoints), seed);
        kiKMeansPP:
          if centroidIdx = 0 then
          begin
            c := RandInt(Length(FPoints), seed)
          end
          else
          begin
            key := obj * RandInt(High(Cardinal), seed) / High(Cardinal);
            c := DichotomyFind(r[0], key, 0, High(r), SizeOf(r[0]), @CompareKFloats);
          end;
      end;
      // skip chosen centroids; fix a bug reported by Gleb
      while chosen[c] do
        c := Min(High(FPoints), c + 1);
    until not chosen[c];
    push_centroid(FPoints[c], centroidIdx);
    obj := 0;
    chosen[c] := True;

    FMTPoolRef.DoLocalProc(@DoMT, 0, mt.LastThreadIndex, @mt);

    for j := 0 to High(FPoints) do
    begin
      p := FPoints[j];
      di := mt.Buffer[j];

      if (centroidIdx = 0) or (di < p.up_d) then      // closest
      begin
        p.lo_d := p.up_d;
        p.up_d := di;
        p.id := centroidIdx;
      end
      else if (centroidIdx = 1) or (di < p.lo_d) then // second closest
      begin
        p.lo_d := di;
      end;

      if centroidIdx < FOpt.k - 1 then
      begin
        if FOpt.init = kiKMeansPP then
        begin
          obj += p.up_d;
          r[j] := obj;
        end;
      end
      else // centroidIdx == _k - 1
      begin
        p.up_d := Sqrt(p.up_d);
        p.lo_d := Sqrt(p.lo_d);
        FCentroids[p.id].push(p);
      end;
    end;
  end;

  if (FOpt.verbosity >= 1) and not FOpt.quiet then
    Write('*');
end;

procedure TKKmeans.update_bounds();
var
  id0, id1, i, j: Cardinal;
  p: TKPoint;
begin
  id0 := 0;
  id1 := 1;
  if FCentroids[id1].delta > FCentroids[id0].delta then
    Exchange(id0, id1);

  for j := 2 to FOpt.k - 1 do
    if FCentroids[j].delta > FCentroids[id1].delta then
    begin
      id1 := j;
      if FCentroids[j].delta > FCentroids[id0].delta then
        Exchange(id0, id1);
    end;

  for i := 0 to High(FPoints) do
  begin
    p := FPoints[i];
    p.up_d += FCentroids[p.id].delta * p.Weight;
    p.lo_d -= FCentroids[IfThen(p.id = id0, id1, id0)].delta * p.Weight;
  end;
end;

function TKKmeans.getObj(): TKFloat;
var
  mt: TKMTData;

  procedure DoMT(AIndex: PtrInt; AData: Pointer);
  var
    i, s, e: PtrInt;
  begin
    TMTPool.CalcBlock(AIndex, mt.BinSize, Length(mt.Buffer), s, e);
    for i := s to e do
      mt.Buffer[i] := FPoints[i].calc_dist(FCentroids[FPoints[i].id]);
  end;

begin
  mt := TKMTData.Create(Length(FPoints), FOpt.threads);
  FMTPoolRef.DoLocalProc(@DoMT, 0, mt.LastThreadIndex, @mt);

  Result := Sum(mt.Buffer);
end;

procedure TKKmeans.run();
var
  i, j, iter_lim, moved, id0: Cardinal;
  m: TKFloat;
  p: TKPoint;
begin
  init();
  moved := Length(FPoints);

  iter_lim := IfThen( FOpt.iter < 0, High(Cardinal), FOpt.iter);

  for i := 0 to iter_lim do // find neighbour center
  begin
    if moved <> 0 then
    begin
      for j := 0 to FOpt.k - 1 do // move center
       FCentroids[j].reset();
      update_bounds();
    end;

    if (i > 0) and not FOpt.quiet then
    begin
      if FOpt.verbosity > 1 then
        WriteLn(Format('  %3d: obj = %.6g; #moved = %6d\n', [i, getObj(), moved]))
      else
        Write('.');
    end;

    if moved = 0 then
      Break;

    for j := 0 to FOpt.k - 1 do
      FCentroids[j].set_closest(FCentroids);

    moved := 0;
    for j := 0 to High(FPoints) do
    begin
      p := FPoints[j];
      id0 := p.id;
      m := Max(FCentroids[id0].next_d * 0.5, p.lo_d);
      if p.up_d > m then
      begin
        p.up_d := Sqrt(p.calc_dist(FCentroids[id0]));
        if p.up_d > m then
        begin
          p.set_closest(FCentroids);
          if p.id <> id0 then
          begin
            Inc(moved);
            FCentroids[id0].pop(p);
            FCentroids[p.id].push(p);
          end;
        end;
      end;
    end;
  end;

  FObj := getObj();

  if not FOpt.quiet then
  begin
    Write(IfThen(moved <> 0, 'break', 'done'));
    if FOpt.verbosity = 1 then
      WriteLn(Format('; obj = %.6g.', [FObj]))
    else
      WriteLn('.');
  end;
end;

{ TKMTData }

constructor TKMTData.Create(ASize, ANumThreads: Cardinal);
begin
  NumThreads := ANumThreads;
  SetLength(Buffer, ASize);
  BinSize := ASize;
  if ANumThreads > 1 then
    BinSize := Max(cKMTMinBinSize, (BinSize - 1) div NumThreads + 1);
  NumThreads := (ASize - 1) div BinSize + 1;
  LastThreadIndex := NumThreads - 1;
end;

{ TOrthogonalKmeans }

constructor TOrthogonalKmeans.Create(const option: TKOptions);
begin
  FObjective := NaN;
  FOpt := option;

  FMTPool := TMTPool.Create(FOpt.threads);
end;

constructor TOrthogonalKmeans.Create(k: Cardinal; maxIter: Integer; initType: TKInit; numThreads: Cardinal; isVerbose: Boolean);
var
  opt: TKOptions;
begin
  Assert(k > 1, 'TOrthogonalKmeans.K should be > 1');

  opt.init := initType;
  opt.iter := maxIter;
  opt.k := k;
  opt.m := 1;
  opt.normalize := False;
  opt.quiet := False;
  opt.verbosity := 1;
  opt.quiet := not isVerbose;
  opt.threads := IfThen(numThreads = 0, HalfNumberOfProcessors, numThreads);

  Create(opt);
end;

destructor TOrthogonalKmeans.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FKMs) do
    FKMs[i].Free;
  SetLength(FKMs, 0);

  FMTPool.Free;

  inherited Destroy;
end;

procedure TOrthogonalKmeans.load_train_data(rowCount, colCount: Cardinal; trainDS: PPKFloat; trainWeights: PCardinal);
var
  rc, w: Cardinal;
  km: TKKmeans;
begin
  km := TKKmeans.Create(FOpt, rowCount, colCount);
  km.FMTPoolRef := FMTPool;

  for rc := 0 to rowCount - 1 do
  begin
    w := 1;
    if Assigned(trainWeights) then
      w := trainWeights[rc];
    km.set_point_fl(@trainDS[rc, 0], @trainDS[rc, colCount], rc, w, FOpt.normalize);
  end;

  SetLength(FKMs, Length(FKMs) + 1);
  FKMs[High(FKMs)] := km;
end;

procedure TOrthogonalKmeans.train_on_data(pointToCluster: PInteger);
var
  i, j, k: Cardinal;
  op2c: PInteger;
  km, km_: TKKmeans;
  point, point_: TKPointArray;
begin
  km := FKMs[High(FKMs)];

  for i := 1 to FOpt.m do
  begin
    if i >= 2 then
    begin
      km_ := FKMs[High(FKMs)]; // last of mohikans

      // project
      point_ := km_.point;
      for k := 0 to High(point_) do
        point_[k].project(km_.centroid[point_[k].id]);
      km_.clear_centroid();
    end;

    km.run();

    point := km.point;
    op2c := pointToCluster;
    for j := 0 to High(point) do
    begin
      op2c^ := point[j].id;
      Inc(op2c);
    end;
  end;

  FObjective := km.FObj;
end;

procedure TOrthogonalKmeans.get_centroids(centroids: PPKFloat);
var
  i: Cardinal;
  km: TKKmeans;
  centroid: TKCentroidArray;
begin
  km := FKMs[High(FKMs)];
  km.compress();
  centroid := km.centroid;
  for i := 0 to High(centroid) do
    centroid[i].get_values(centroids[i]);
end;

function TOrthogonalKmeans.Process(const trainDS: TKFloatArray2; var pointToCluster: TIntegerDynArray;
  const centroids: TKFloatArray2; const trainWeights: TCardinalDynArray): Double;
var
  rc, cc: Cardinal;
  tw: PCardinal;
begin
  rc := Length(trainDS);
  cc := Length(trainDS[0]);
  Assert(not Assigned(trainWeights) or (Length(trainWeights) = rc));
  Assert(not Assigned(pointToCluster) or (Length(pointToCluster) = rc));
  Assert(not Assigned(centroids) or (Length(centroids) = FOpt.k) and (Length(centroids[0]) = cc));

  SetLength(pointToCluster, rc);

  tw := nil;
  if Assigned(trainWeights) then
    tw := @trainWeights[0];

  load_train_data(rc, cc, PPKFloat(@trainDS[0]), tw);
  train_on_data(@pointToCluster[0]);

  if Assigned(centroids) then
    get_centroids(PPKFloat(@centroids[0]));
end;

end.
