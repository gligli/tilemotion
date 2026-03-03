unit orthogonal_kmeans;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}

// yakmo -- yet another k-means via orthogonalization
//  $Id: yakmo.h 1866 2015-01-21 10:25:43Z ynaga $
// Copyright (c) 2012-2015 Naoki Yoshinaga <ynaga@tkl.iis.u-tokyo.ac.jp>

interface

uses
  Classes, SysUtils, StrUtils, math, fgl, Types, utils;

type
  TKFloat = Double;

  PKFloat = ^TKFloat;
  PPKFloat = ^PKFloat;
  TKFloatArray = array of TKFloat;

  TKInit = (kiRandom, kiKMeansPP);

  TKOption  = record // option handler
    init: TKInit;
    k: Cardinal;
    m: Cardinal;
    iter: Integer;
    normalize: Boolean;
    verbosity: Cardinal;
    weighting: Boolean;
    quiet: Boolean;
  end;

// implementation of space-efficient k-means using triangle inequality:
//   G. Hamerly. Making k-means even faster (SDM 2010)

  { TKNode }

  TKNode = packed record
    idx: Cardinal;
    val: TKFloat;
    constructor Create(AIdx: Cardinal; AVal: TKFloat);
    class function CompareNodes(Item1,Item2,UserParameter:Pointer):Integer; static;
  end;

  PKNode = ^TKNode;
  TKNodeArray = array of TKNode;

  TKPoint = class;
  TKCentroid = class;
  TKKMeans = class;
  TKCentroidArray = array of TKCentroid;
  TKPointArray = array of TKPoint;
  TKKMeansArray = array of TKKMeans;

  { TKPoint }

  TKPoint = class
  private
    _size: Cardinal;
    _body: PKNode;
    _norm: TKFloat;
    _weight: Cardinal;
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

    property norm: TKFloat read _norm;
    property weight: Cardinal read _weight;
    property size: Cardinal read _size;
    property body: PKNode read _body;
  end;

  { TKCentroid }

  TKCentroid = class
  private
    _norm: TKFloat;  // norm
    _dv: PKFloat;
    _sum: PKFloat;
    _body: PKNode;
    _nelm: Cardinal;  // # elements belonging to the cluster
    _nf: Cardinal;    // # features
    _size: Cardinal;  // # nozero features
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

    property norm: TKFloat read _norm;
  end;

  { TKKmeans }

  TKKmeans = class
  private
    _opt: TKOption;
    _point: TKPointArray;
    _centroid: TKCentroidArray;
    _body: TKNodeArray;
    _nf: Cardinal;
  public
    constructor Create(const AOpt: TKOption);
    destructor Destroy; override;

    procedure clear_point();
    procedure clear_centroid();
    class function read_point_fl(AEx, AExEnd: PKFloat; const ATmp: TKNodeArray; AWeight: Cardinal; ANormalize: Boolean = false): TKPoint;
    procedure set_point_fl(AEx, AExEnd: PKFloat; AWeight: Cardinal; ANormalize: Boolean);
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

    property point: TKPointArray read _point;
    property centroid: TKCentroidArray read _centroid;
    property nf: Cardinal read _nf;
  end;

  // implementation of orthogonal k-means:
  //   Y. Cui et al. Non-redundant multi-view clustering via orthogonalization (ICDM 2007)

  { TOrthogonalKmeans }

  TOrthogonalKmeans = class
  private
    _opt: TKOption;
    _kms: TKKMeansArray;
  public
    constructor Create(const option: TKOption);
    destructor Destroy; override;

    procedure load_train_data(rowCount, colCount: Cardinal; trainDS: PPKFloat; trainWeights: PCardinal);
    procedure train_on_data(pointToCluster: PInteger);
    procedure get_centroids(centroids: PPKFloat);
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
  _size := ASize;
  _norm := ANorm;
  _weight := AWeight;
  _body := AllocMem(_size * SizeOf(TKNode));
  Move(AN^, _body^, _size * SizeOf(TKNode));
end;

procedure TKPoint.CopyFrom(const AP: TKPoint);
begin
  up_d := AP.up_d;
  lo_d := AP.lo_d;
  id := AP.id;
  _size := AP._size;
  _body := AP._body;
  _norm := AP._norm;
  _weight := AP._weight;
end;

function TKPoint.calc_ip(const AC: TKCentroid): TKFloat;
var
  n: PKNode;
begin
  // return inner product between this point and the given centroid

  Result := 0.0;

  n := nbegin();
  repeat
    Result += n^.val * AC._dv[n^.idx];
    Inc(n);
  until n = nend();
end;

function TKPoint.calc_dist(const AC: TKCentroid): TKFloat;
var
  n: PKNode;
begin
  // return distance from this point to the given centroid

  Result := 0.0;
  Result += _norm + AC.norm;

  n := nbegin();
  repeat
    Result -= 2 * n^.val * AC._dv[n^.idx];
    Inc(n);
  until n = nend();

  Result *= _weight;
end;

procedure TKPoint.set_closest(const ACS: TKCentroidArray);
var
  i, id0: Cardinal;
  d0, d1, di: TKFloat;
  dissim_buf: TKFloatArray;
begin
  SetLength(dissim_buf, Length(ACS));

  //#pragma omp parallel for
  for i := 0 to High(ACS) do
    dissim_buf[i] := calc_dist(ACS[i]);

  i := IfThen(id = 0, 1, 0); // second closest (cand)
  id0 := id;
  d0 := dissim_buf[id0];
  d1 := dissim_buf[i];

  if (d1 < d0) then
  begin
    id := i;
    Exchange(d0, d1);
  end;

  for i := 0 to High(ACS) do
  begin
    if i = id0 then
      Continue;

    di := dissim_buf[i];

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
    Dec(_size);
end;

procedure TKPoint.project(const AC: TKCentroid);
var
  i: Cardinal;
  norm_ip, v: TKFloat;
begin
  norm_ip := calc_ip(AC) / AC.norm;

  up_d := 0.0; lo_d := 0.0; id := 0; _norm := 0.0; // reset

  for i := 0 to _size - 1 do
  begin
    v := AC._dv[_body[i].idx] * norm_ip;
    _norm += Sqr(v);
    _body[i].val := v;
  end;
end;

function TKPoint.nbegin(): PKNode;
begin
  Result := _body;
end;

function TKPoint.nend(): PKNode;
begin
  Result := _body + _size;
end;

function TKPoint.back(): PKNode;
begin
  Result := @_body[_size - 1];
end;

function TKPoint.empty(): Boolean;
begin
  Result := _size = 0;
end;

procedure TKPoint.clear();
begin
  if Assigned(_body) then FreeMemAndNil(_body);
end;

{ TKCentroid }

constructor TKCentroid.Create(AP: TKPoint; ANF: Cardinal; ADelegate: Boolean);
var
  sz: Cardinal;
  n: PKNode;
begin
  _norm := AP.norm;
  _nf := ANF;

  if ADelegate then
  begin
    _size := AP.size;
    _body := AP.body; // ADelegate
  end
  else
  begin
    // workaround for a bug in value initialization in gcc 4.0
    sz := (_nf + 1) * SizeOf(TKFloat);

    _dv := AllocMem(sz);
    _sum := AllocMem(sz);

    FillChar(_dv^, sz, 0);
    FillChar(_sum^, sz, 0);

    n := AP.nbegin();
    repeat
      _dv[n^.idx] := n^.val;
    until n = AP.nend();
  end;
end;

procedure TKCentroid.pop(AP: TKPoint);
var
  n: PKNode;
begin
  n := AP.nbegin();
  repeat
    _sum[n^.idx] -= n^.val * AP.weight;
  until n = AP.nend();

  _nelm -= AP.weight;
end;

procedure TKCentroid.push(AP: TKPoint);
var
  n: PKNode;
begin
  n := AP.nbegin();
  repeat
    _sum[n^.idx] += n^.val * AP.weight;
  until n = AP.nend();

  _nelm += AP.weight;
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
    for d := 0 to _nf do
    begin
      Result += Sqr(_dv[d] - AC._dv[d]);
      if Result > cand then
        Break;
    end;
  end
  else
  begin
    for d := 0 to _nf do
      Result += Sqr(_dv[d] - AC._dv[d]);
  end;
end;

procedure TKCentroid.set_closest(const ACS: TKCentroidArray);
var
  i: Cardinal;
  di: TKFloat;
  dissim_buf: TKFloatArray;
begin
  SetLength(dissim_buf, Length(ACS));

  //#pragma omp parallel for
  for i := 0 to High(ACS) do
    dissim_buf[i] := calc_dist(ACS[i]);

  i := IfThen(Self = ACS[0], 1, 0);
  next_d := dissim_buf[i];
  for i := i + 1 to High(ACS) do
  begin
    if Self = ACS[i] then
      Continue;
    di := dissim_buf[i];
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
  delta := 0.0; _norm := 0.0;

  for i := 0 to _nf do
  begin
    v := _sum[i] / _nelm;
    delta += Sqr(v - _dv[i]);
    _norm += Sqr(v);
    _dv[i] := v;
  end;

  delta := Sqrt(delta);
end;

procedure TKCentroid.compress();
var
  i, j: Cardinal;
begin
  _size := 0;
  for i := 0 to _nf do
    if _dv[i] <> 0.0 then
      Inc(_size);
  _body := AllocMem(_size * SizeOf(TKNode));

  j := 0;
  for i := 0 to _nf do
    if _dv[i] <> 0.0 then
    begin
      _body[j].idx := i;
      _body[j].val := _dv[i];
      Inc(j);
    end;

  FreeMemAndNil(_dv);
  FreeMemAndNil(_sum);
end;

procedure TKCentroid.decompress();
var
  i: Cardinal;
  sz: Integer;
begin
  sz := (_nf + 1) * SizeOf(TKFloat);
  _dv := AllocMem(sz);
  FillChar(_dv^, sz, 0);

  for i := 0 to _size do
    _dv[_body[i].idx] := _body[i].val;

  FreeMemAndNil(_body);
end;

procedure TKCentroid.get_values(AValues: PKFloat);
var
  i: Cardinal;
begin
  FillChar(AValues^, _nf * sizeof(TKFloat), 0);
  for i := 0 to _size do
    AValues[_body[i].idx] := _body[i].val;
end;

procedure TKCentroid.clear();
begin
  if Assigned(_dv) then FreeMemAndNil(_dv);
  if Assigned(_sum) then FreeMemAndNil(_sum);
  if Assigned(_body) then FreeMemAndNil(_body);
end;

{ TKKmeans }

constructor TKKmeans.Create(const AOpt: TKOption);
begin
  _opt := AOpt;
  SetLength(_centroid, _opt.k);
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
  for i := 0 to High(_point) do
    _point[i].clear();
  SetLength(_point, 0);
end;

procedure TKKmeans.clear_centroid();
var
  i: Cardinal;
begin
  for i := 0 to High(_centroid) do
    _centroid[i].clear();
  SetLength(_centroid, 0);
end;

class function TKKmeans.read_point_fl(AEx, AExEnd: PKFloat; const ATmp: TKNodeArray; AWeight: Cardinal; ANormalize: Boolean): TKPoint;
var
  i, fi: Cardinal;
  norm, v: TKFloat;
  p: PKFloat;
begin
  FillChar(ATmp[0], Length(ATmp) * SizeOf(TKNode), 0);
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

procedure TKKmeans.set_point_fl(AEx, AExEnd: PKFloat; AWeight: Cardinal; ANormalize: Boolean);
var
  p: TKPoint;
begin
  SetLength(_point, Length(_point) + 1);
  p := _point[High(_point)];
  p := read_point_fl(AEx, AExEnd, _body, AWeight, ANormalize);

  if not p.empty() then
    _nf := Max(p.back()^.idx, _nf);
end;

procedure TKKmeans.delegate(AKM: TKKmeans);
var
  tmp: TKPointArray;
begin
  tmp := _point;
  _point := AKM._point;
  AKM._point := tmp;

  AKM._nf := _nf;
end;

procedure TKKmeans.compress();
var
  i: Cardinal;
begin
  for i := 0 to High(_centroid) do
      _centroid[i].compress();
end;

procedure TKKmeans.decompress();
var
  i: Cardinal;
begin
  for i := 0 to High(_centroid) do
      _centroid[i].decompress();
end;

procedure TKKmeans.push_centroid(AP: TKPoint; AIdx: Cardinal; ADelegate: Boolean);
begin
  _centroid[AIdx] := TKCentroid.Create(AP, _nf, ADelegate);
end;

procedure TKKmeans.init();
var
  i, j, k, c, seed: Cardinal;
  obj, key, di: TKFloat;
  p: TKPoint;
  chosen: TBooleanDynArray;
  r: TKFloatArray;
  dissim_buf: TKFloatArray;
begin
  seed := CRandomSeed;
  obj := 0;
  if _opt.init = kiKMeansPP then
  begin
    SetLength(r, Length(_point));
    SetLength(chosen, Length(_point));
  end;

  SetLength(dissim_buf, Length(_point));

  for i := 0 to _opt.k - 1 do
  begin
    c := 0;
    repeat
      case _opt.init of
        kiRandom:
          c := RandInt(Length(_point), seed);
        kiKMeansPP:
          if i = 0 then
          begin
            c := RandInt(Length(_point), seed)
          end
          else
          begin
            key := obj * RandInt(High(Cardinal), seed) / High(Cardinal);
            c := DichotomyFind(r[0], key, 0, High(r), SizeOf(r[0]), @CompareDoubles);
          end;
      end;
      // skip chosen centroids; fix a bug reported by Gleb
      while chosen[c] do
        c := Min(High(_point), c + 1);
    until chosen[c];
    obj := 0;
    chosen[c] := True;

    //#pragma omp parallel for
    for k := 0 to High(_point) do
      dissim_buf[k] := _point[k].calc_dist(_centroid[i]);

    for j := 0 to High(_point) do
    begin
      p := _point[j];
      di := dissim_buf[j];

      if (i = 0) or (di < p.up_d) then      // closest
      begin
        p.lo_d := p.up_d;
        p.up_d := di;
        p.id := i;
      end
      else if (i = 1) or (di < p.lo_d) then // second closest
      begin
        p.lo_d := di;
      end;

      if i < _opt.k - 1 then
      begin
        if _opt.init = kiKMeansPP then
        begin
          obj += p.up_d;
          r[j] := obj;
        end;
      end
      else // i == _k - 1
      begin
        p.up_d := Sqrt(p.up_d);
        p.lo_d := Sqrt(p.lo_d);
        _centroid[p.id].push(p);
      end;
    end;
  end;

  if (_opt.verbosity > 1) and not _opt.quiet then
    WriteLn;
end;

procedure TKKmeans.update_bounds();
var
  id0, id1, i, j: Cardinal;
  p: TKPoint;
begin
  id0 := 0;
  id1 := 1;
  if _centroid[id1].delta > _centroid[id0].delta then
    Exchange(id0, id1);

  for j := 2 to _opt.k - 1 do
    if _centroid[j].delta > _centroid[id1].delta then
    begin
      id1 := j;
      if _centroid[j].delta > _centroid[id0].delta then
        Exchange(id0, id1);
    end;

  for i := 0 to High(_point) do
  begin
    p := _point[i];
    p.up_d += _centroid[p.id].delta * p.weight;
    p.lo_d -= _centroid[IfThen(p.id = id0, id1, id0)].delta * p.weight;
  end;
end;

function TKKmeans.getObj(): TKFloat;
var
  i: Cardinal;
  dissim_buf: TKFloatArray;
begin
  SetLength(dissim_buf, Length(_point));

  //#pragma omp parallel for
  for i := 0 to High(_point) do
    dissim_buf[i] := _point[i].calc_dist(_centroid[_point[i].id]);

  Result := Sum(dissim_buf);
end;

procedure TKKmeans.run();
var
  i, j, iter_lim, moved, id0: Cardinal;
  m: TKFloat;
  p: TKPoint;
begin
  init();
  moved := Length(_point);

  iter_lim := IfThen( _opt.iter < 0, High(Cardinal), _opt.iter);

  for i := 0 to iter_lim do // find neighbour center
  begin
    if moved <> 0 then
    begin
      for j := 0 to _opt.k - 1 do // move center
       _centroid[j].reset();
      update_bounds();
    end;

    if (i > 0) and not _opt.quiet then
    begin
      if _opt.verbosity > 1 then
        WriteLn(Format('  %3d: obj = %e; #moved = %6d\n', [i, getObj (), moved]))
      else
        Write('.');
    end;

    if moved = 0 then
      Break;

    for j := 0 to _opt.k - 1 do
      _centroid[j].set_closest(_centroid);

    moved := 0;
    for j := 0 to High(_point) do
    begin
      p := _point[j];
      id0 := p.id;
      m := Max(_centroid[id0].next_d / 2, p.lo_d);
      if p.up_d > m then
      begin
        p.up_d := Sqrt(p.calc_dist(_centroid[id0]));
        if p.up_d > m then
        begin
          p.set_closest(_centroid);
          if p.id <> id0 then
          begin
            Inc(moved);
            _centroid[id0].pop(p);
            _centroid[p.id].push(p);
          end;
        end;
      end;
    end;
  end;

  if not _opt.quiet then
  begin
    WriteLn(IfThen(moved <> 0, 'break', 'done'));
    if _opt.verbosity = 1 then
      WriteLn(Format('; obj = %g.\n', [getObj()]))
    else
      WriteLn('.');
  end;
end;

{ TOrthogonalKmeans }

constructor TOrthogonalKmeans.Create(const option: TKOption);
begin
  _opt := option;
end;

destructor TOrthogonalKmeans.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(_kms) do
    _kms[i].Free;
  SetLength(_kms, 0);

  inherited Destroy;
end;

procedure TOrthogonalKmeans.load_train_data(rowCount, colCount: Cardinal; trainDS: PPKFloat; trainWeights: PCardinal);
var
  rc, w: Cardinal;
  km: TKKmeans;
begin
  km := TKKmeans.Create(_opt);

  for rc := 0 to rowCount - 1 do
  begin
    w := 1;
    if Assigned(trainWeights) then
      w := trainWeights[rc];
    km.set_point_fl(@trainDS[rc, 0], @trainDS[rc, colCount], w, _opt.normalize);
  end;

  SetLength(_kms, Length(_kms) + 1);
  _kms[High(_kms)] := km;
end;

procedure TOrthogonalKmeans.train_on_data(pointToCluster: PInteger);
var
  i, j, k: Cardinal;
  op2c: PInteger;
  km, km_: TKKmeans;
  point, point_: TKPointArray;
begin
  km := _kms[High(_kms)];

  for i := 1 to _opt.m do
  begin
    if i >= 2 then
    begin
      km_ := _kms[High(_kms)]; // last of mohikans

      // project
      point_ := km_.point;
      for k := 0 to High(point_) do
        point_[k].project(km_.centroid[point_[k].id]);
      km_.clear_centroid();
    end;

    km.run();

    point := km_.point;
    op2c := pointToCluster;
    for j := 0 to High(point) do
    begin
      op2c^ := point[j].id;
      Inc(op2c);
    end;
  end;
end;

procedure TOrthogonalKmeans.get_centroids(centroids: PPKFloat);
var
  i: Cardinal;
  km: TKKmeans;
  centroid: TKCentroidArray;
begin
  km := _kms[High(_kms)];
  km.compress();
  centroid := km.centroid;
  for i := 0 to High(centroid) do
    centroid[i].get_values(centroids[i]);
end;

end.
