unit utils;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$TYPEDADDRESS ON}
{$CODEALIGN LOCALMIN=16}

interface

uses
  Classes, SysUtils, Types, math, fgl, extern, usimplex;

const
  // tweakable constants

  cPSNRPrecision = 1e-6;
  cPSNREpsilon = 0.1;
  cYakmoMaxIterations = 1000;
  cTileDCTUndispersedCount = 9;

  cRedMul = 299;
  cGreenMul = 587;
  cBlueMul = 114;

  CRandomSeed = $42381337;

  // don't change these

  cLumaDiv = cRedMul + cGreenMul + cBlueMul;

  cBitsPerCompBits = 3;
  cBitsPerComp = 1 shl cBitsPerCompBits;
  cVecInvWidth = 16;
  cTileWidthBits = 3;
  cTileWidth = 1 shl cTileWidthBits;
  cColorCpns = 3;
  cTileDCTSize = cColorCpns * sqr(cTileWidth);
  cUnrolledDCTSize = cTileDCTSize * sqr(cTileWidth);
  cPhi = (1 + sqrt(5)) / 2;
  cInvPhi = 1 / cPhi;

  cDitheringNullColor = Integer($ffffff);
  cDitheringListLen = 256;
  cDitheringMap : array[0..8*8 - 1] of Byte = (
     0, 48, 12, 60,  3, 51, 15, 63,
    32, 16, 44, 28, 35, 19, 47, 31,
     8, 56,  4, 52, 11, 59,  7, 55,
    40, 24, 36, 20, 43, 27, 39, 23,
     2, 50, 14, 62,  1, 49, 13, 61,
    34, 18, 46, 30, 33, 17, 45, 29,
    10, 58,  6, 54,  9, 57,  5, 53,
    42, 26, 38, 22, 41, 25, 37, 21
  );
  cDitheringLen = length(cDitheringMap);

  cDCTSnake : array[0..sqr(cTileWidth) - 1] of Byte = (
     0,  1,  5,  6, 14, 15, 27, 28,
     2,  4,  7, 13, 16, 26, 29, 42,
     3,  8, 12, 17, 25, 30, 41, 43,
     9, 11, 18, 24, 31, 40, 44, 53,
    10, 19, 23, 32, 39, 45, 52, 54,
    20, 22, 33, 38, 46, 51, 55, 60,
    21, 34, 37, 47, 50, 56, 59, 61,
    35, 36, 48, 49, 57, 58, 62, 63
  );

  // Normalized inverse quantization matrix for 8x8 DCT at the point of transparency.
  // from: https://gitlab.xiph.org/xiph/daala/-/blob/gitlab-ci/tools/dump_psnrhvs.c?ref_type=heads
  cPSNRWeights: array[0..cColorCpns-1{YUV}, 0..7, 0..7] of Double = (
    ((1.6193873005, 2.2901594831, 2.08509755623, 1.48366094411, 1.00227514334, 0.678296995242, 0.466224900598, 0.3265091542),
     (2.2901594831, 1.94321815382, 2.04793073064, 1.68731108984, 1.2305666963, 0.868920337363, 0.61280991668, 0.436405793551),
     (2.08509755623, 2.04793073064, 1.34329019223, 1.09205635862, 0.875748795257, 0.670882927016, 0.501731932449, 0.372504254596),
     (1.48366094411, 1.68731108984, 1.09205635862, 0.772819797575, 0.605636379554, 0.48309405692, 0.380429446972, 0.295774038565),
     (1.00227514334, 1.2305666963, 0.875748795257, 0.605636379554, 0.448996256676, 0.352889268808, 0.283006984131, 0.226951348204),
     (0.678296995242, 0.868920337363, 0.670882927016, 0.48309405692, 0.352889268808, 0.27032073436, 0.215017739696, 0.17408067321),
     (0.466224900598, 0.61280991668, 0.501731932449, 0.380429446972, 0.283006984131, 0.215017739696, 0.168869545842, 0.136153931001),
     (0.3265091542, 0.436405793551, 0.372504254596, 0.295774038565, 0.226951348204, 0.17408067321, 0.136153931001, 0.109083846276)),
    ((1.91113096927, 2.46074210438, 1.18284184739, 1.14982565193, 1.05017074788, 0.898018824055, 0.74725392039, 0.615105596242),
     (2.46074210438, 1.58529308355, 1.21363250036, 1.38190029285, 1.33100189972, 1.17428548929, 0.996404342439, 0.830890433625),
     (1.18284184739, 1.21363250036, 0.978712413627, 1.02624506078, 1.03145147362, 0.960060382087, 0.849823426169, 0.731221236837),
     (1.14982565193, 1.38190029285, 1.02624506078, 0.861317501629, 0.801821139099, 0.751437590932, 0.685398513368, 0.608694761374),
     (1.05017074788, 1.33100189972, 1.03145147362, 0.801821139099, 0.676555426187, 0.605503172737, 0.55002013668, 0.495804539034),
     (0.898018824055, 1.17428548929, 0.960060382087, 0.751437590932, 0.605503172737, 0.514674450957, 0.454353482512, 0.407050308965),
     (0.74725392039, 0.996404342439, 0.849823426169, 0.685398513368, 0.55002013668, 0.454353482512, 0.389234902883, 0.342353999733),
     (0.615105596242, 0.830890433625, 0.731221236837, 0.608694761374, 0.495804539034, 0.407050308965, 0.342353999733, 0.295530605237)),
    ((2.03871978502, 2.62502345193, 1.26180942886, 1.11019789803, 1.01397751469, 0.867069376285, 0.721500455585, 0.593906509971),
     (2.62502345193, 1.69112867013, 1.17180569821, 1.3342742857, 1.28513006198, 1.13381474809, 0.962064122248, 0.802254508198),
     (1.26180942886, 1.17180569821, 0.944981930573, 0.990876405848, 0.995903384143, 0.926972725286, 0.820534991409, 0.706020324706),
     (1.11019789803, 1.3342742857, 0.990876405848, 0.831632933426, 0.77418706195, 0.725539939514, 0.661776842059, 0.587716619023),
     (1.01397751469, 1.28513006198, 0.995903384143, 0.77418706195, 0.653238524286, 0.584635025748, 0.531064164893, 0.478717061273),
     (0.867069376285, 1.13381474809, 0.926972725286, 0.725539939514, 0.584635025748, 0.496936637883, 0.438694579826, 0.393021669543),
     (0.721500455585, 0.962064122248, 0.820534991409, 0.661776842059, 0.531064164893, 0.438694579826, 0.375820256136, 0.330555063063),
     (0.593906509971, 0.802254508198, 0.706020324706, 0.587716619023, 0.478717061273, 0.393021669543, 0.330555063063, 0.285345396658))
  );


  cQ = 16;
  cJPEGWeights: array[0..cColorCpns-1{YUV}, 0..7, 0..7] of Double = (
    (
      // Luma
      (cQ / 16, cQ /  11, cQ /  10, cQ /  16, cQ /  24, cQ /  40, cQ /  51, cQ /  61),
      (cQ / 12, cQ /  12, cQ /  14, cQ /  19, cQ /  26, cQ /  58, cQ /  60, cQ /  55),
      (cQ / 14, cQ /  13, cQ /  16, cQ /  24, cQ /  40, cQ /  57, cQ /  69, cQ /  56),
      (cQ / 14, cQ /  17, cQ /  22, cQ /  29, cQ /  51, cQ /  87, cQ /  80, cQ /  62),
      (cQ / 18, cQ /  22, cQ /  37, cQ /  56, cQ /  68, cQ / 109, cQ / 103, cQ /  77),
      (cQ / 24, cQ /  35, cQ /  55, cQ /  64, cQ /  81, cQ / 104, cQ / 113, cQ /  92),
      (cQ / 49, cQ /  64, cQ /  78, cQ /  87, cQ / 103, cQ / 121, cQ / 120, cQ / 101),
      (cQ / 72, cQ /  92, cQ /  95, cQ /  98, cQ / 112, cQ / 100, cQ / 103, cQ /  99)
    ),
    (
      // U, weighted by luma importance
      (cQ / 17, cQ /  18, cQ /  24, cQ /  47, cQ /  99, cQ /  99, cQ /  99, cQ /  99),
      (cQ / 18, cQ /  21, cQ /  26, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112),
      (cQ / 24, cQ /  26, cQ /  56, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128),
      (cQ / 47, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144),
      (cQ / 99, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160),
      (cQ / 99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176),
      (cQ / 99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192),
      (cQ / 99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192, cQ / 208)
    ),
    (
      // V, weighted by luma importance
      (cQ / 17, cQ /  18, cQ /  24, cQ /  47, cQ /  99, cQ /  99, cQ /  99, cQ /  99),
      (cQ / 18, cQ /  21, cQ /  26, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112),
      (cQ / 24, cQ /  26, cQ /  56, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128),
      (cQ / 47, cQ /  66, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144),
      (cQ / 99, cQ /  99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160),
      (cQ / 99, cQ /  99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176),
      (cQ / 99, cQ /  99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192),
      (cQ / 99, cQ / 112, cQ / 128, cQ / 144, cQ / 160, cQ / 176, cQ / 192, cQ / 208)
    )
  );

  cDCTUVRatio: array[0..7,0..7] of TFloat = (
    (0.5, sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5), sqrt(0.5)),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1),
    (sqrt(0.5), 1, 1, 1, 1, 1, 1, 1)
  );

type
  TSpinlock = LongInt;
  PSpinLock = ^TSpinlock;

  { TCountIndex }

  TCountIndex = record
    Index, Count: Integer;
    R, G, B: Byte;
    Luma: Integer;
    Hue, Sat, Val: Byte;
  end;

  PCountIndex = ^TCountIndex;
  TCountIndexList = specialize TFPGList<PCountIndex>;

  { TIndexWeight }

  TIndexWeight = record
    Index: Integer;
    Weight: Double;
  end;

  PIndexWeight = ^TIndexWeight;
  TIndexWeightList = specialize TFPGList<PIndexWeight>;

  { TKRng }

  TKRng = record
    x, y, z, w: UInt64;
    procedure init();
    function randInt(): UInt64; // Xorshift RNG; http://www.jstatsoft.org/v08/i14/paper
    function random(): Double;
  end;

  { TDCTCribbleState }

  TDCTCribbleState = packed record
    Error: Cardinal;
    X, Y: Integer;
    DX, DY: Integer;
    oxmn, oxmx: Integer;
    oymn, oymx: Integer;
    PenaltyLUT: PCardinal;
  end;

  PDCTCribbleState = ^TDCTCribbleState;

  TEvalFunc = function(const arg: TDoubleDynArray; data: Pointer): Double of object;
  TGRSEvalFunc = function(x: Double; Data: Pointer): Double of object;
  TCompareFunction = function(Item1,Item2,UserParameter:Pointer):Integer;

  TGRSResult = record
    X, Y: Double;
  end;

  TDCTScalar = SmallInt;
  PDCTScalar = ^TDCTScalar;
  TDCT = array[0 .. cTileDCTSize - 1] of TDCTScalar;
  TDCTDynArray = array of TDCT;
  TDCTDynArray2 = array of TDCTDynArray;

const
  cDCTScale = -Low(TDCTScalar) / ((1 shl cBitsPerComp) * Sqr(cTileWidth));
  cBestPSNR = 20.0 * Ln((1 shl cBitsPerComp) * cDCTScale - 1) / Ln(10.0);

procedure SpinEnter(Lock: PSpinLock); register; assembler;
procedure SpinEnterSleep(Lock: PSpinLock); register; assembler;
procedure SpinLeave(Lock: PSpinLock); register; assembler;
procedure Exchange(var a, b: Integer); overload;
procedure Exchange(var a, b: Cardinal); overload;
procedure Exchange(var a, b: Double); overload;
procedure Exchange(var a, b: Single); overload;
function iDivDef(x, y, def: Integer): Integer;overload;inline;
function iDivDef(x, y, def: Int64): Int64;overload;inline;
function DivDef(x, y, def: TFloat): TFloat;inline;
function NanDef(x, def: TFloat): TFloat; inline;
function SwapRB(c: Integer): Integer; inline;
function ToRGB(r, g, b: Byte): Integer; inline;
procedure FromRGB(col: Integer; out r, g, b: Integer); inline; overload;
procedure FromRGB(col: Integer; out r, g, b: Byte); inline; overload;
function ToLuma(r, g, b: Integer): Integer; inline;
function ToBW(col: Integer): Integer;
function HSVToRGB(h, s, v: Byte): Integer;
procedure RGBToHSV(r, g, b: Byte; out h, s, v: Byte); overload;
procedure RGBToHSV(r, g, b: Byte; out h, s, v: TFloat); overload;
procedure RGBToYUV(col: Integer; out y, u, v: TFloat; scl: TFloat);
procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat; scl: TFloat);
procedure RGBToLAB(r, g, b: TFloat; out ol, oa, ob: TFloat);
procedure RGBToLAB(ir, ig, ib: Integer; out ol, oa, ob: TFloat);
function LABToRGB(ll, aa, bb: TFloat): Integer;
function YUVToRGB(y, u, v, scl: TFloat): Integer;
function lerp(x, y, alpha: Double): Double; inline;
function ilerp(x, y, alpha, maxAlpha: Integer): Integer; inline;
function revlerp(x, y, res: Double): Double; inline;
procedure BlendRGB(x, y, alpha, weight: Integer; alphaShift, weightShift: Byte; out r, g, b: Byte);
function BlendRGB(x, y, alpha, weight: Integer; alphaShift, weightShift: Byte): Integer;
function Posterize(v: Byte; cvt: Integer): Byte; inline;
function PosterizeBpc(v, bpc: Byte): Byte; inline;
function CompareEuclideanDCTPtr(pa, pb: PDCTScalar): Cardinal;
function CompareEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar): Cardinal; register; assembler;
function CompareEuclidean(a, b: PFloat; size: Integer): Double; inline;
function CompareCountIndexYSH(const Item1,Item2:PCountIndex):Integer;
function CompareIntegers(Item1,Item2,UserParameter:Pointer):Integer;
function CompareDoubles(Item1,Item2,UserParameter:Pointer):Integer;
function ComparePaletteUseCount(Item1,Item2,UserParameter:Pointer):Integer;
function QuickTestEuclideanDCTPtr(pa, pb: PDCTScalar; min_dist: Cardinal): Boolean;
function QuickTestEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar; min_dist_r8: Cardinal): Boolean; register; assembler;
function ApplyMotionPredictionPenalty(ox, oy, dx, dy, backBufOff: Integer): Cardinal;
function ApplyBlendPredictionPenalty(alpha, weight, backBufOff: Integer): Cardinal;
procedure CribbleEuclideanDCTPtr(cur: PDCTScalar; prev: PDCTScalar; state: PDCTCribbleState; oy: Integer);
procedure CribbleEuclideanDCTPtr_asm(cur_rcx: PDCTScalar; prev_rdx: PDCTScalar; state_r8: PDCTCribbleState; oy_r9: Integer); register; assembler;
generic function DCTInner<T>(pCpn, pLut: T; count: Integer): Double;
function DCTInner_asm(pCpn_rcx, pLut_rdx: PFloat): Double; register; assembler;
function EqualQualityTileCount(tileCount: Double): Integer;
function GoldenRatioSearch(Func: TGRSEvalFunc; MinX, MaxX: Double; ObjectiveY: Double; EpsilonX, EpsilonY: Double; Data: Pointer): TGRSResult;
function NelderMeadMinimize(Func: TEvalFunc; var X: TDoubleDynArray; SimplexExtents: array of Double; Epsilon: Double = 1e-9; Data: Pointer = nil): Double;
function GridReduceMinimize(Func: TEvalFunc; var X: TDoubleDynArray; GridSize: array of Integer; GridExtents: array of Double; EpsilonReduce: Double; VerboseTag: String = ''; Data: Pointer = nil): Double;
function EuclideanToPSNR(AEuclidean: Double): Double;
function PSNRToEuclidean(APSNR: Double): Cardinal;
procedure QuickSort(var AData;AFirstItem,ALastItem:Int64;AItemSize:Integer;ACompareFunction:TCompareFunction;AUserParameter:Pointer=nil);
function DichotomyFind(var AData,AKey;AFirstItem,ALastItem:Int64;AItemSize:Integer;ACompareFunction:TCompareFunction;AUserParameter:Pointer=nil): Integer;

implementation

// SpinLock code from https://wiki.osdev.org/Spinlock

procedure SpinEnter(Lock: PSpinLock); register; assembler;
label acquireLock, spin_with_pause, acquired;
asm
  acquireLock:
      lock bts [lock],0        // Attempt to acquire the lock (in case lock is uncontended)
      jnc acquired

  spin_with_pause:
      pause                    // Tell CPU we're spinning
      test dword [lock],1      // Is the lock free?
      jnz spin_with_pause      // no, wait
      jmp acquireLock          // retry

  acquired:
end;

procedure SpinSleep;
begin
  Sleep(1);
end;

procedure SpinEnterSleep(Lock: PSpinLock); register; assembler;
label acquireLock, spin_with_pause, sleep, acquired;
asm
  push  rax

  acquireLock:
      lock  bts [lock],0       // Attempt to acquire the lock (in case lock is uncontended)
      jnc   acquired

      xor   eax,eax

  spin_with_pause:
      inc   eax
      test  eax,$fffe0000
      jnz   sleep
      pause                    // Tell CPU we're spinning
      test  dword [lock],1     // Is the lock free?
      jnz   spin_with_pause    // no, wait
      jmp   acquireLock        // retry

  sleep:
      push  rcx
      call  SpinSleep
      pop   rcx
      jmp   acquireLock

  acquired:

  pop  rax
end;

procedure SpinLeave(Lock: PSpinLock); register; assembler;
asm
  mov dword [Lock],0
end;

procedure Exchange(var a, b: Integer);
var
  tmp: Integer;
begin
  tmp := b;
  b := a;
  a := tmp;
end;

procedure Exchange(var a, b: Cardinal);
var
  tmp: Cardinal;
begin
  tmp := b;
  b := a;
  a := tmp;
end;

procedure Exchange(var a, b: Double);
var
  tmp: Double;
begin
  tmp := b;
  b := a;
  a := tmp;
end;

procedure Exchange(var a, b: Single);
var
  tmp: Double;
begin
  tmp := b;
  b := a;
  a := tmp;
end;

function iDivDef(x, y, def: Integer): Integer;
begin
  Result := def;
  if y <> 0 then
    Result := x div y;
end;

function iDivDef(x, y, def: Int64): Int64;
begin
  Result := def;
  if y <> 0 then
    Result := x div y;
end;

function DivDef(x, y, def: TFloat): TFloat;
begin
  Result := def;
  if y <> 0 then
    Result := x / y;
end;

function NanDef(x, def: TFloat): TFloat; inline;
begin
  Result := x;
  if IsNan(Result) then
    Result := def;
end;

function SwapRB(c: Integer): Integer; inline;
begin
  Result := ((c and $ff) shl 16) or ((c shr 16) and $ff) or (c and $ff00);
end;

function ToRGB(r, g, b: Byte): Integer; inline;
begin
  Result := (b shl 16) or (g shl 8) or r;
end;

procedure FromRGB(col: Integer; out r, g, b: Integer); inline; overload;
begin
  r := col and $ff;
  g := (col shr 8) and $ff;
  b := (col shr 16) and $ff;
end;

procedure FromRGB(col: Integer; out r, g, b: Byte); inline; overload;
begin
  r := col and $ff;
  g := (col shr 8) and $ff;
  b := (col shr 16) and $ff;
end;

function ToLuma(r, g, b: Integer): Integer; inline;
begin
  Result := r * cRedMul + g * cGreenMul + b * cBlueMul;
end;

function ToBW(col: Integer): Integer;
var
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  Result := ToLuma(r, g, b);
  Result := Result div cLumaDiv;
  Result := ToRGB(Result, Result, Result);
end;

// from https://www.delphipraxis.net/157099-fast-integer-rgb-hsl.html
procedure RGBToHSV(r, g, b: Byte; out h, s, v: Byte);

  function MulDiv(nNumber, nNumerator, nDenominator: Integer): Integer;
  begin
    if nDenominator = 0 then
      Result := -1
    else
      Result := Round((nNumber * nNumerator) / nDenominator);
  end;

  function RGBMaxValue: Integer;
  begin
    Result := r;
    if (Result < g) then Result := g;
    if (Result < b) then Result := b;
  end;

  function RGBMinValue : Integer;
  begin
    Result := r;
    if (Result > g) then Result := g;
    if (Result > b) then Result := b;
  end;

var
  Delta, mx, mn, hh, ss, ll: Integer;
begin
  mx := RGBMaxValue;
  mn := RGBMinValue;

  hh := 0;
  ss := 0;
  ll := mx;
  if ll <> mn then
  begin
    Delta := ll - mn;
    ss := MulDiv(Delta, 255, ll);

    if (r = ll) then
      hh := MulDiv(42, g - b, Delta)
    else if (g = ll) then
      hh := MulDiv(42, b - r, Delta) + 84
    else if (b = ll) then
      hh := MulDiv(42, r - g, Delta) + 168;

    hh := hh mod 252;
  end;

  h := hh and $ff;
  s := ss and $ff;
  v := ll and $ff;
end;

function HSVToRGB(h, s, v: Byte): Integer;
const
  MaxHue: Integer = 252;
  MaxSat: Integer = 255;
  MaxLum: Integer = 255;
  Divisor: Integer = 42;
var
 f, LS, p, q, r: integer;
begin
 if (s = 0) then
   Result := ToRGB(v, v, v)
 else
  begin
   h := h mod MaxHue;
   s := EnsureRange(s, 0, MaxSat);
   v := EnsureRange(v, 0, MaxLum);

   f := h mod Divisor;
   h := h div Divisor;
   LS := v*s;
   p := v - LS div MaxLum;
   q := v - (LS*f) div (255 * Divisor);
   r := v - (LS*(Divisor - f)) div (255 * Divisor);
   case h of
    0: Result := ToRGB(v, r, p);
    1: Result := ToRGB(q, v, p);
    2: Result := ToRGB(p, v, r);
    3: Result := ToRGB(p, q, v);
    4: Result := ToRGB(r, p, v);
    5: Result := ToRGB(v, p, q);
   else
    Result := ToRGB(0, 0, 0);
   end;
  end;
end;

procedure RGBToHSV(r, g, b: Byte; out h, s, v: TFloat);
var
  bh, bs, bv: Byte;
begin
  bh := 0; bs := 0; bv := 0;
  RGBToHSV(r, g, b, bh, bs, bv);
  h := bh / 255.0;
  s := bs / 255.0;
  v := bv / 255.0;
end;

procedure RGBToLAB(ir, ig, ib: Integer; out ol, oa, ob: TFloat); inline;
var
  r, g, b, x, y, z: TFloat;
begin
  r := ir / 255.0;
  g := ig / 255.0;
  b := ib / 255.0;

  if r > 0.04045 then r := power((r + 0.055) / 1.055, 2.4) else r := r / 12.92;
  if g > 0.04045 then g := power((g + 0.055) / 1.055, 2.4) else g := g / 12.92;
  if b > 0.04045 then b := power((b + 0.055) / 1.055, 2.4) else b := b / 12.92;

  // CIE XYZ color space from the Wright–Guild data
  x := (r * 0.49000 + g * 0.31000 + b * 0.20000) / 0.17697;
  y := (r * 0.17697 + g * 0.81240 + b * 0.01063) / 0.17697;
  z := (r * 0.00000 + g * 0.01000 + b * 0.99000) / 0.17697;

{$if True}
  // Illuminant D50
  x *= 1 / (96.6797 / 100);
  y *= 1 / (100.000 / 100);
  z *= 1 / (82.5188 / 100);
{$else}
  // Illuminant D65
  x *= 1 / (95.0470 / 100);
  y *= 1 / (100.000 / 100);
  z *= 1 / (108.883 / 100);
{$endif}

  if x > 0.008856 then x := power(x, 1/3) else x := (7.787 * x) + 16/116;
  if y > 0.008856 then y := power(y, 1/3) else y := (7.787 * y) + 16/116;
  if z > 0.008856 then z := power(z, 1/3) else z := (7.787 * z) + 16/116;

  ol := (116 * y) - 16;
  oa := 500 * (x - y);
  ob := 200 * (y - z);
end;

procedure RGBToLAB(r, g, b: TFloat; out ol, oa, ob: TFloat); inline;
var
  ll, aa, bb: TFloat;
begin
  RGBToLAB(Integer(round(r * 255.0)), round(g * 255.0), round(b * 255.0), ll, aa, bb);
  ol := ll;
  oa := aa;
  ob := bb;
end;

function LABToRGB(ll, aa, bb: TFloat): Integer;
var
  x, y, z, r, g, b: TFloat;
begin
  y := (ll + 16) / 116;
  x := aa / 500 + y;
  z := y - bb / 200;

  if IntPower(y, 3) > 0.008856 then
    y := IntPower(y, 3)
  else
    y := (y - 16 / 116) / 7.787;
  if IntPower(x, 3) > 0.008856 then
    x := IntPower(x, 3)
  else
    x := (x - 16 / 116) / 7.787;
  if IntPower(z, 3) > 0.008856 then
    z := IntPower(z, 3)
  else
    z := (z - 16 / 116) / 7.787;

  // Illuminant D50
  x := 96.6797 / 100 * x;
  y := 100.000 / 100 * y;
  z := 82.5188 / 100 * z;

  r := x * 0.41847 + y * (-0.15866) + z * (-0.082835);
  g := x * (-0.091169) + y * 0.25243 + z * 0.015708;
  b := x * 0.00092090 + y * (-0.0025498) + z * 0.17860;

  if r > 0.0031308 then
    r := 1.055 * Power(r, 1 / 2.4) - 0.055
  else
    r := 12.92 * r;
  if g > 0.0031308 then
    g := 1.055 * Power(g, 1 / 2.4) - 0.055
  else
    g := 12.92 * g;
  if b > 0.0031308 then
    b := 1.055 * Power(b, 1 / 2.4) - 0.055
  else
    b := 12.92 * b;

  Result := ToRGB(EnsureRange(Round(r * 255.0), 0, 255), EnsureRange(Round(g * 255.0), 0, 255), EnsureRange(Round(b * 255.0), 0, 255));
end;

procedure RGBToYUV(col: Integer; out y, u, v: TFloat; scl: TFloat); inline;
var
  yy, uu, vv: TFloat;
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  RGBToYUV(r, g, b, yy, uu, vv, scl);
  y := yy; u := uu; v := vv; // for safe "out" param
end;

// from https://en.wikipedia.org/wiki/YCbCr#JPEG_conversion (0..255 digital version)
procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat; scl: TFloat);
begin
  y := (        0.299    * r + 0.587    * g + 0.114    * b) * scl;
  u := (128.0 - 0.168736 * r - 0.331264 * g + 0.5      * b) * scl;
  v := (128.0 + 0.5      * r - 0.418688 * g - 0.081312 * b) * scl;
end;

function YUVToRGB(y, u, v, scl: TFloat): Integer;
var
  r, g, b: TFloat;
begin
  y *= 1.0 / scl;
  u *= 1.0 / scl;
  v *= 1.0 / scl;

  u -= 128.0;
  v -= 128.0;

  r := y                + 1.402    * v;
  g := y - 0.344136 * u - 0.714136 * v;
  b := y + 1.772    * u;

  Result := ToRGB(EnsureRange(Round(r), 0, 255), EnsureRange(Round(g), 0, 255), EnsureRange(Round(b), 0, 255));
end;

function lerp(x, y, alpha: Double): Double; inline;
begin
  Result := x + (y - x) * alpha;
end;

function ilerp(x, y, alpha, maxAlpha: Integer): Integer; inline;
begin
  Result := x + ((y - x) * alpha) div maxAlpha;
end;

function revlerp(x, y, res: Double): Double;
begin
  Result := DivDef(res - x, y - x, NaN);
end;

procedure BlendRGB(x, y, alpha, weight: Integer; alphaShift, weightShift: Byte; out r, g, b: Byte);
var
  r1, g1, b1: Integer;
  r2, g2, b2: Integer;
  shift: Byte;
  invAlpha, weightVal, rounding: Integer;
begin
  FromRGB(x, r1, g1, b1);
  FromRGB(y, r2, g2, b2);

  weightVal := (1 shl weightShift) + weight;
  invAlpha := ((1 shl alphaShift) - alpha) * weightVal;
  alpha *= weightVal;
  shift := alphaShift + weightShift;
  rounding := 1 shl (shift - 1);

  r1 := (r1 * invAlpha + r2 * alpha + rounding) shr shift;
  g1 := (g1 * invAlpha + g2 * alpha + rounding) shr shift;
  b1 := (b1 * invAlpha + b2 * alpha + rounding) shr shift;

  r := EnsureRange(r1, 0, High(Byte));
  g := EnsureRange(g1, 0, High(Byte));
  b := EnsureRange(b1, 0, High(Byte));
end;

function BlendRGB(x, y, alpha, weight: Integer; alphaShift, weightShift: Byte): Integer;
var
  r, g, b: Byte;
begin
  BlendRGB(x, y, alpha, weight, alphaShift, weightShift, r, g, b);
  Result := ToRGB(r, g, b);
end;

function Posterize(v: Byte; cvt: Integer): Byte; inline;
var
  p: Integer;
begin
  Assert(cvt <= 255);
  p := Round(Round((v * cvt) / 255.0) * 255.0 / cvt);
  Assert(p <= 255);
  Result := p;
end;

function PosterizeBpc(v, bpc: Byte): Byte; inline;
begin
  Result := Posterize(v, (1 shl bpc) - 1);
end;

function CompareEuclideanDCTPtr(pa, pb: PDCTScalar): Cardinal;
var
  i: Integer;
begin
  Result := 0;
  for i := cTileDCTSize div 8 - 1 downto 0 do
  begin
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
    Result += sqr(pa^ - pb^); Inc(pa); Inc(pb);
  end;
end;

function CompareEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar): Cardinal; register; assembler;
const
  cUnroll = 32;
label
  loop;
asm
  push rcx
  push rdx

  sub rsp, 16 * 5
  movdqu oword ptr [rsp],       xmm0
  movdqu oword ptr [rsp + $10], xmm1
  movdqu oword ptr [rsp + $20], xmm2
  movdqu oword ptr [rsp + $30], xmm3
  movdqu oword ptr [rsp + $40], xmm4

  // unrolled by 32 = (cTileDCTSize / cUnroll)

  pxor xmm0, xmm0
  mov al, (cTileDCTSize / cUnroll)

loop:

  movdqu xmm1, oword ptr [rcx]
  movdqu xmm2, oword ptr [rcx + $10]
  movdqu xmm3, oword ptr [rcx + $20]
  movdqu xmm4, oword ptr [rcx + $30]

  psubsw xmm1, oword ptr [rdx]
  psubsw xmm2, oword ptr [rdx + $10]
  psubsw xmm3, oword ptr [rdx + $20]
  psubsw xmm4, oword ptr [rdx + $30]

  pmaddwd xmm1, xmm1
  pmaddwd xmm2, xmm2
  pmaddwd xmm3, xmm3
  pmaddwd xmm4, xmm4

  paddd xmm1, xmm2
  paddd xmm3, xmm4

  paddd xmm1, xmm3

  paddd xmm0, xmm1

  lea rcx, [rcx + $40]
  lea rdx, [rdx + $40]

  dec al
  jnz loop

  // end

  phaddd xmm0, xmm0
  phaddd xmm0, xmm0

  movd eax, xmm0

  movdqu xmm0,  oword ptr [rsp]
  movdqu xmm1,  oword ptr [rsp + $10]
  movdqu xmm2,  oword ptr [rsp + $20]
  movdqu xmm3,  oword ptr [rsp + $30]
  movdqu xmm4,  oword ptr [rsp + $40]
  add rsp, 16 * 5

  pop rdx
  pop rcx
end;

function CompareEuclidean(a, b: PFloat; size: Integer): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to size - 1 do
    Result += sqr(a[i] - b[i]);
end;

function CompareIntegers(Item1, Item2, UserParameter: Pointer): Integer;
begin
  Result := CompareValue(PInteger(Item1)^, PInteger(Item2)^);
end;

function CompareCountIndexYSH(const Item1,Item2:PCountIndex):Integer;
begin
  Result := CompareValue(Item1^.Luma, Item2^.Luma);
  if Result = 0 then
    Result := CompareValue(Item1^.Sat, Item2^.Sat);
  if Result = 0 then
    Result := CompareValue(Item1^.Hue, Item2^.Hue);
end;

function CompareDoubles(Item1, Item2, UserParameter: Pointer): Integer;
begin
  Result := CompareValue(PDouble(Item2)^, PDouble(Item1)^);
end;

function ComparePaletteUseCount(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

function QuickTestEuclideanDCTPtr(pa, pb: PDCTScalar; min_dist: Cardinal): Boolean;
begin
  Result := Sqr(pa[0] - pb[0]) + Sqr(pa[1] - pb[1]) + Sqr(pa[2] - pb[2]) + Sqr(pa[3] - pb[3]) +
            Sqr(pa[4] - pb[4]) + Sqr(pa[5] - pb[5]) + Sqr(pa[6] - pb[6]) + Sqr(pa[7] - pb[7]) < min_dist;
end;

function QuickTestEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar; min_dist_r8: Cardinal): Boolean; register; assembler;
asm
  sub rsp, 16 * 1
  movdqu oword ptr [rsp], xmm0

  movdqu xmm0, oword ptr [rcx]
  psubsw xmm0, oword ptr [rdx]

  pmaddwd xmm0, xmm0

  phaddd xmm0, xmm0
  phaddd xmm0, xmm0

  movd eax, xmm0
  cmp eax, r8
  setb al

  movdqu xmm0, oword ptr [rsp]
  add rsp, 16 * 1
end;

function ApplyMotionPredictionPenalty(ox, oy, dx, dy, backBufOff: Integer): Cardinal;
begin
  // apply a penalty of the euclidean distance to the center
  // rationale: slightly favoring the center in case of ties improves compressibility
  Result := (Sqr(ox - dx) + Sqr(oy - dy)) * backBufOff;
end;

function ApplyBlendPredictionPenalty(alpha, weight, backBufOff: Integer): Cardinal;
begin
  Result := (Sqr(alpha) + Sqr(weight)) * backBufOff;
end;

procedure CribbleEuclideanDCTPtr(cur: PDCTScalar; prev: PDCTScalar; state: PDCTCribbleState; oy: Integer);
var
  ox: Integer;
  err, best: Cardinal;
  pPenalty: PCardinal;
begin
  best := state^.Error;

  pPenalty := @state^.PenaltyLUT[state^.oxmn - state^.DX];

  for ox := state^.oxmn to state^.oxmx do
  begin
    if QuickTestEuclideanDCTPtr_asm(cur, prev, best) then
    begin
      err := CompareEuclideanDCTPtr_asm(cur, prev);
      err += pPenalty^;

      if err < best then
      begin
        best := err;
        state^.Error := err;
        state^.Y := oy;
        state^.X := ox;
      end;
    end;

    Inc(prev, cTileDCTSize);
    Inc(pPenalty);
  end;
end;

procedure CribbleEuclideanDCTPtr_asm(cur_rcx: PDCTScalar; prev_rdx: PDCTScalar; state_r8: PDCTCribbleState; oy_r9: Integer); register; assembler;
const
  cUnroll = 32;
label
  x_loop, quick_evicted, dct_bailout, dct_better, dct_loop;
asm
  push rax
  push rbx
  push rdx
  push rsi
  push rdi
  push r10
  push r11
  push r12

  sub rsp, 16 * 6
  movdqu oword ptr [rsp], xmm0
  movdqu oword ptr [rsp + $10], xmm1
  movdqu oword ptr [rsp + $20], xmm2
  movdqu oword ptr [rsp + $30], xmm3
  movdqu oword ptr [rsp + $40], xmm4
  movdqu oword ptr [rsp + $50], xmm5

  movdqu xmm5, oword ptr [rcx]

  mov ebx, dword ptr [r8]
  mov esi, dword ptr [r8 + 5 * 4]
  mov edi, dword ptr [r8 + 6 * 4]

  mov r10, qword ptr [r8 + 9 * 4]
  mov eax, esi
  sub eax, dword ptr [r8 + 3 * 4]
  lea r10, qword ptr [r10 + eax * 4]

  x_loop:
    movdqa xmm0, oword ptr [rdx]
    psubsw xmm0, xmm5

    pmaddwd xmm0, xmm0

    phaddd xmm0, xmm0
    phaddd xmm0, xmm0

    movd eax, xmm0
    add eax, dword ptr [r10]

    cmp eax, ebx
    jae quick_evicted

    push rcx
    push rdx
    mov eax, dword ptr [r10]

    // unrolled by 32 = (cTileDCTSize / cUnroll)

    mov r12b, (cTileDCTSize / cUnroll)

    dct_loop:

      movdqu xmm1, oword ptr [rcx]
      movdqu xmm2, oword ptr [rcx + $10]
      movdqu xmm3, oword ptr [rcx + $20]
      movdqu xmm4, oword ptr [rcx + $30]

      psubsw xmm1, oword ptr [rdx]
      psubsw xmm2, oword ptr [rdx + $10]
      psubsw xmm3, oword ptr [rdx + $20]
      psubsw xmm4, oword ptr [rdx + $30]

      pmaddwd xmm1, xmm1
      pmaddwd xmm2, xmm2
      pmaddwd xmm3, xmm3
      pmaddwd xmm4, xmm4

      paddd xmm1, xmm2
      paddd xmm3, xmm4

      paddd xmm1, xmm3

      phaddd xmm1, xmm1
      phaddd xmm1, xmm1

      lea rcx, [rcx + $40]
      lea rdx, [rdx + $40]

      movd r11d, xmm1
      add eax, r11d

      cmp eax, ebx
      jae dct_bailout

      dec r12b
      jnz dct_loop

      dct_better:

        mov ebx, eax
        mov dword ptr [r8 + 1 * 4], esi
        mov dword ptr [r8 + 2 * 4], r9d

      dct_bailout:

        pop rdx
        pop rcx

    quick_evicted:

    add rdx, cTileDCTSize * 2
    add r10, 4

    inc esi
    cmp esi, edi
    jbe x_loop

  mov dword ptr [r8], ebx

  movdqu xmm0, oword ptr [rsp]
  movdqu xmm1, oword ptr [rsp + $10]
  movdqu xmm2, oword ptr [rsp + $20]
  movdqu xmm3, oword ptr [rsp + $30]
  movdqu xmm4, oword ptr [rsp + $40]
  movdqu xmm5, oword ptr [rsp + $50]
  add rsp, 16 * 6

  pop r12
  pop r11
  pop r10
  pop rdi
  pop rsi
  pop rdx
  pop rbx
  pop rax
end;

generic function DCTInner<T>(pCpn, pLut: T; count: Integer): Double;
var
  i: integer;
begin
  Result := 0;

  for i := 0 to count- 1 do
  begin
    // unroll y by cTileWidth

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);

    // unroll x by cTileWidth
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
    Result += pCpn^ * pLut^; Inc(pCpn); Inc(pLut);
  end;
end;

function DCTInner_asm(pCpn_rcx, pLut_rdx: PFloat): Double; register; assembler;
asm
  sub rsp, 16 * 8
  movdqu oword ptr [rsp],       xmm1
  movdqu oword ptr [rsp + $10], xmm2
  movdqu oword ptr [rsp + $20], xmm3
  movdqu oword ptr [rsp + $30], xmm4
  movdqu oword ptr [rsp + $40], xmm5
  movdqu oword ptr [rsp + $50], xmm6
  movdqu oword ptr [rsp + $60], xmm7
  movdqu oword ptr [rsp + $70], xmm8

  // unrolled for 64  = Sqr(cTileWidth)

  pxor xmm0, xmm0

  // step 1

  movups xmm2, oword ptr [rcx]
  movups xmm4, oword ptr [rcx + $10]
  movups xmm6, oword ptr [rcx + $20]
  movups xmm8, oword ptr [rcx + $30]

  movups xmm1, oword ptr [rdx]
  movups xmm3, oword ptr [rdx + $10]
  movups xmm5, oword ptr [rdx + $20]
  movups xmm7, oword ptr [rdx + $30]

  mulps xmm1, xmm2
  mulps xmm3, xmm4
  mulps xmm5, xmm6
  mulps xmm7, xmm8

  addps xmm1, xmm3
  addps xmm5, xmm7

  cvtps2pd xmm2, xmm1
  cvtps2pd xmm4, xmm5
  movhlps xmm3, xmm1
  movhlps xmm7, xmm5
  cvtps2pd xmm6, xmm3
  cvtps2pd xmm8, xmm7

  addpd xmm2, xmm4
  addpd xmm6, xmm8

  addpd xmm2, xmm6
  addpd xmm0, xmm2

  // step 2

  movups xmm2, oword ptr [rcx + $40]
  movups xmm4, oword ptr [rcx + $50]
  movups xmm6, oword ptr [rcx + $60]
  movups xmm8, oword ptr [rcx + $70]

  movups xmm1, oword ptr [rdx + $40]
  movups xmm3, oword ptr [rdx + $50]
  movups xmm5, oword ptr [rdx + $60]
  movups xmm7, oword ptr [rdx + $70]

  mulps xmm1, xmm2
  mulps xmm3, xmm4
  mulps xmm5, xmm6
  mulps xmm7, xmm8

  addps xmm1, xmm3
  addps xmm5, xmm7

  cvtps2pd xmm2, xmm1
  cvtps2pd xmm4, xmm5
  movhlps xmm3, xmm1
  movhlps xmm7, xmm5
  cvtps2pd xmm6, xmm3
  cvtps2pd xmm8, xmm7

  addpd xmm2, xmm4
  addpd xmm6, xmm8

  addpd xmm2, xmm6
  addpd xmm0, xmm2

  // step 3

  movups xmm2, oword ptr [rcx + $80]
  movups xmm4, oword ptr [rcx + $90]
  movups xmm6, oword ptr [rcx + $a0]
  movups xmm8, oword ptr [rcx + $b0]

  movups xmm1, oword ptr [rdx + $80]
  movups xmm3, oword ptr [rdx + $90]
  movups xmm5, oword ptr [rdx + $a0]
  movups xmm7, oword ptr [rdx + $b0]

  mulps xmm1, xmm2
  mulps xmm3, xmm4
  mulps xmm5, xmm6
  mulps xmm7, xmm8

  addps xmm1, xmm3
  addps xmm5, xmm7

  cvtps2pd xmm2, xmm1
  cvtps2pd xmm4, xmm5
  movhlps xmm3, xmm1
  movhlps xmm7, xmm5
  cvtps2pd xmm6, xmm3
  cvtps2pd xmm8, xmm7

  addpd xmm2, xmm4
  addpd xmm6, xmm8

  addpd xmm2, xmm6
  addpd xmm0, xmm2

  // step 4

  movups xmm2, oword ptr [rcx + $c0]
  movups xmm4, oword ptr [rcx + $d0]
  movups xmm6, oword ptr [rcx + $e0]
  movups xmm8, oword ptr [rcx + $f0]

  movups xmm1, oword ptr [rdx + $c0]
  movups xmm3, oword ptr [rdx + $d0]
  movups xmm5, oword ptr [rdx + $e0]
  movups xmm7, oword ptr [rdx + $f0]

  mulps xmm1, xmm2
  mulps xmm3, xmm4
  mulps xmm5, xmm6
  mulps xmm7, xmm8

  addps xmm1, xmm3
  addps xmm5, xmm7

  cvtps2pd xmm2, xmm1
  cvtps2pd xmm4, xmm5
  movhlps xmm3, xmm1
  movhlps xmm7, xmm5
  cvtps2pd xmm6, xmm3
  cvtps2pd xmm8, xmm7

  addpd xmm2, xmm4
  addpd xmm6, xmm8

  addpd xmm2, xmm6
  addpd xmm0, xmm2

  // end

  movdqu xmm1,  oword ptr [rsp]
  movdqu xmm2,  oword ptr [rsp + $10]
  movdqu xmm3,  oword ptr [rsp + $20]
  movdqu xmm4,  oword ptr [rsp + $30]
  movdqu xmm5,  oword ptr [rsp + $40]
  movdqu xmm6,  oword ptr [rsp + $50]
  movdqu xmm7,  oword ptr [rsp + $60]
  movdqu xmm8,  oword ptr [rsp + $70]
  add rsp, 16 * 8

  haddpd xmm0, xmm0
end;


function EqualQualityTileCount(tileCount: Double): Integer;
begin
  Result := round(sqrt(tileCount) * log2(1 + tileCount));
end;


function GoldenRatioSearch(Func: TGRSEvalFunc; MinX, MaxX: Double; ObjectiveY: Double; EpsilonX, EpsilonY: Double; Data: Pointer): TGRSResult;
var
  x, y: Double;
begin
  if SameValue(MinX, MaxX, EpsilonX) then
  begin
    Result.X := MinX;
    Result.Y := Func(MinX, Data);
    Exit;
  end;

  if MinX < MaxX then
    x := lerp(MinX, MaxX, 1.0 - cInvPhi)
  else
    x := lerp(MinX, MaxX, cInvPhi);

  y := Func(x, Data);

  //WriteLn('X: ', x:15:6, ' Y: ', y:15:6, ' Mini: ', MinX:15:6, ' Maxi: ', MaxX:15:6);

  case CompareValue(y, ObjectiveY, EpsilonY) of
    LessThanValue:
      Result := GoldenRatioSearch(Func, x, MaxX, ObjectiveY, EpsilonX, EpsilonY, Data);
    GreaterThanValue:
      Result := GoldenRatioSearch(Func, MinX, x, ObjectiveY, EpsilonX, EpsilonY, Data);
  else
      Result.X := x;
      Result.Y := y;
  end;
end;

threadvar
  GNMData: Pointer;
  GNMFunc: TEvalFunc;

  function NMX(X : TDoubleDynArray) : Float;
  begin
    Result := GNMFunc(X, GNMData);
  end;

function NelderMeadMinimize(Func: TEvalFunc; var X: TDoubleDynArray; SimplexExtents: array of Double; Epsilon: Double; Data: Pointer): Double;
var
  iX: Integer;
  InitSimplex: TDoubleDynArray;
begin
  Assert((Length(X) = Length(SimplexExtents)) or (Length(SimplexExtents) = 0));

  GNMData := Data;
  GNMFunc := Func;
  try
    SetLength(InitSimplex, Length(SimplexExtents));
    for iX := 0 to High(InitSimplex) do
      InitSimplex[iX] := X[iX] + SimplexExtents[iX];

    Simplex(@NMX, X, 0, High(X), Length(X) * 200, Epsilon, Result, InitSimplex);
  finally
    GNMData := nil;
    GNMFunc := nil;
  end;
end;

function GridReduceMinimize(Func: TEvalFunc; var X: TDoubleDynArray; GridSize: array of Integer;
 GridExtents: array of Double; EpsilonReduce: Double; VerboseTag: String; Data: Pointer): Double;
var
  XBestFunc, bestX: TDoubleDynArray;
  reduce: TDoubleDynArray;

  procedure DoX(AIndex: Integer);
  var
    iX: Integer;
    gs, iGrid: Integer;
    f: Double;
    lX: TDoubleDynArray;
  begin
    iX := AIndex;
    if IsZero(reduce[iX], EpsilonReduce) then
      Exit;

    lX := Copy(X);
    gs := GridSize[iX];

    for iGrid := -gs to gs - 1 do
    begin
      lX[iX] := X[iX] + lerp(-GridExtents[iX], GridExtents[iX], (iGrid + gs) / (2 * gs)) * reduce[iX];

      f := Func(lX, data);

      if f < XBestFunc[iX] then
      begin
        XBestFunc[iX] := f;
        bestX[iX] := lX[iX];
      end;
    end;
  end;

var
  iter, iX: Integer;
  bestFunc: Double;
begin
  Assert(Length(X) = Length(GridSize));
  Assert(Length(X) = Length(GridExtents));

  SetLength(XBestFunc, Length(X));
  SetLength(bestX, Length(X));

  SetLength(reduce, Length(X));
  for iX := 0 to High(X) do
    reduce[iX] := 1.0;

  iter := 0;
  repeat

    for iX := 0 to High(X) do
    begin
      bestX[iX] := X[iX];
      XBestFunc[iX] := Infinity;
    end;

    for iX := 0 to High(X) do
      DoX(iX);

    Inc(iter);
    bestFunc := MinValue(XBestFunc);

    for iX := 0 to High(X) do
      if XBestFunc[iX] = bestFunc then
      begin
        X[iX] := bestX[iX];
        reduce[iX] *= cInvPhi;

        if VerboseTag <> '' then
          WriteLn(VerboseTag, ', Iter:', iter:4, ', BestX:', iX:4, ', Reduce:', reduce[iX]:12:9, ', Func:', bestFunc:20:9);
      end;

  until IsZero(MaxValue(reduce), EpsilonReduce);

  Result := bestFunc;
end;

function EuclideanToPSNR(AEuclidean: Double): Double;
begin
  Result := AEuclidean * (1 / cTileDCTSize);
  Result := cBestPSNR - 10.0 * Log10(Max(1.0, Result));
end;

function PSNRToEuclidean(APSNR: Double): Cardinal;
begin
  Result := Round(Power(10.0, (cBestPSNR - APSNR) * 0.1) * cTileDCTSize);
end;

procedure QuickSort(var AData;AFirstItem,ALastItem:Int64;AItemSize:Integer;ACompareFunction:TCompareFunction;AUserParameter:Pointer=nil);
var I, J, P: Int64;
    PData,P1,P2: PByte;
    Tmp: array[0..4095] of Byte;
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

function DichotomyFind(var AData,AKey;AFirstItem,ALastItem:Int64;AItemSize:Integer;ACompareFunction:TCompareFunction;AUserParameter:Pointer=nil): Integer;
{ Searches for the first item <= Key, returns True if exact match,
  sets index to the index of the found string. }
var
  I,L,R,Dir: Integer;
  PData,PKey,P: PByte;
begin
  // Use binary search.
  L := AFirstItem;
  R := ALastItem;
  PData:=PByte(@AData);
  PKey:=PByte(@AKey);
  while L<=R do
  begin
    I := L + (R - L) div 2;
    P := PData; Inc(P, I * AItemSize);
    Dir := ACompareFunction(P, PKey, AUserParameter);
    if Dir < 0 then
      L := I+1
    else begin
      R := I-1;
      if Dir = 0 then
        L := I;
    end;
  end;
  Result := L;
  if not InRange(Result, AFirstItem, ALastItem) then
    Result := -1;
end;

{ TKRng }

procedure TKRng.init();
begin
  x := 123456789;
  y := 362436069;
  z := 521288629;
  w := 88675123;
end;

function TKRng.randInt(): UInt64;
var
  t: UInt64;
begin
  t := (x xor (x shl 11)); x := y; y := z; z := w;
  w := (w xor (w shr 19)) xor (t xor (t shr 8));
  Result := w;
end;

function TKRng.random: Double;
begin
  Result := randInt() / High(UInt64);
end;

end.

