unit utils;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$TYPEDADDRESS ON}
{$CODEALIGN LOCALMIN=16}

interface

uses
  Classes, SysUtils, Windows, math, fgl, extern, Types;

const
  // tweakable constants

  cPsyVEpsilon = 1e-6;
  cYakmoMaxIterations = 1000;

  {$if 0}
    cRedMul = 2126;
    cGreenMul = 7152;
    cBlueMul = 722;
  {$else}
    cRedMul = 299;
    cGreenMul = 587;
    cBlueMul = 114;
  {$endif}

  cRGBw = 13; // in 1 / 32th

  // don't change these

  cLumaDiv = cRedMul + cGreenMul + cBlueMul;

  cBitsPerComp = 8;
  cVecInvWidth = 16;
  cTileWidthBits = 3;
  cTileWidth = 1 shl cTileWidthBits;
  cColorCpns = 3;
  cTileDCTSize = cColorCpns * sqr(cTileWidth);
  cUnrolledDCTSize = sqr(sqr(cTileWidth));
  cPhi = (1 + sqrt(5)) / 2;
  cInvPhi = 1 / cPhi;

  cDitheringNullColor = Integer($ffff00ff);
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
  // from: https://gitlab-restore.xiph.org/xiph/daala/-/blob/gitlab-ci/tools/dump_psnrhvs.c?ref_type=heads
  cDCTWeights: array[0..cColorCpns-1{YUV}, 0..7, 0..7] of Double = (
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

  cPsnrMaxValue = 10 * Ln(255 * 255 / 0.5) / Ln(10);
type
  TSpinlock = LongInt;
  PSpinLock = ^TSpinlock;

  { TCountIndex }

  TCountIndex = record
    Index, Count: Integer;
    R, G, B: Byte;
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

  TEvalFunc = function(const arg: TDoubleDynArray; data: Pointer): Double of object;
  TGRSEvalFunc = function(x: Double; Data: Pointer): Double of object;

  TDCTScalar = SmallInt;
  PDCTScalar = ^TDCTScalar;
  TDCT = array[0 .. cTileDCTSize - 1] of TDCTScalar;
  TDCTDynArray = array of TDCT;

  { TZoomLevel }

  TZoomLevel = record
    Level, Delta, Offset, Dummy: Integer;
  end;

  PZoomLevel = ^TZoomLevel;

const
  cZoomShift = 12;
  cZoomPx = 1 shl cZoomShift;
  cZoomHPx = 1 shl (cZoomShift - 1);

  cZoomLevels: array[1 .. 32] of TZoomLevel = (
    (Level:  1; Delta:  1 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  1) div 2), // uniform tile (all pixels same color)
    (Level:  2; Delta:  2 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  2) div 2),
    (Level:  3; Delta:  3 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  3) div 2),
    (Level:  4; Delta:  4 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  4) div 2),
    (Level:  5; Delta:  5 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  5) div 2),
    (Level:  6; Delta:  6 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  6) div 2),
    (Level:  7; Delta:  7 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  7) div 2),
    (Level:  8; Delta:  8 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  8) div 2), // = cTileWidth (not a zoom level)
    (Level:  9; Delta:  9 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth -  9) div 2),
    (Level: 10; Delta: 10 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 10) div 2),
    (Level: 11; Delta: 11 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 11) div 2),
    (Level: 12; Delta: 12 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 12) div 2),
    (Level: 13; Delta: 13 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 13) div 2),
    (Level: 14; Delta: 14 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 14) div 2),
    (Level: 15; Delta: 15 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 15) div 2),
    (Level: 16; Delta: 16 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 16) div 2),
    (Level: 17; Delta: 17 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 17) div 2),
    (Level: 18; Delta: 18 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 18) div 2),
    (Level: 19; Delta: 19 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 19) div 2),
    (Level: 20; Delta: 20 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 20) div 2),
    (Level: 21; Delta: 21 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 21) div 2),
    (Level: 22; Delta: 22 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 22) div 2),
    (Level: 23; Delta: 23 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 23) div 2),
    (Level: 24; Delta: 24 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 24) div 2),
    (Level: 25; Delta: 25 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 25) div 2),
    (Level: 26; Delta: 26 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 26) div 2),
    (Level: 27; Delta: 27 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 27) div 2),
    (Level: 28; Delta: 28 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 28) div 2),
    (Level: 29; Delta: 29 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 29) div 2),
    (Level: 30; Delta: 30 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 30) div 2),
    (Level: 31; Delta: 31 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 31) div 2),
    (Level: 32; Delta: 32 shl (cZoomShift - cTileWidthBits); Offset: (cTileWidth - 32) div 2)  // 4x unzoom (32x32 -> 8x8)
  );

procedure SpinEnter(Lock: PSpinLock); assembler;
procedure SpinLeave(Lock: PSpinLock); assembler;
procedure Exchange(var a, b: Integer);
function iDiv0(x, y: Integer): Integer;overload;inline;
function iDiv0(x, y: Int64): Int64;overload;inline;
function Div0(x, y: TFloat): TFloat;inline;
function NanDef(x, def: TFloat): TFloat; inline;
function SwapRB(c: Integer): Integer; inline;
function ToRGB(r, g, b: Byte): Integer; inline;
procedure FromRGB(col: Integer; out r, g, b: Integer); inline; overload;
procedure FromRGB(col: Integer; out r, g, b: Byte); inline; overload;
function ToLuma(r, g, b: Byte): Integer; inline;
function ToBW(col: Integer): Integer;
function HSVToRGB(h, s, v: Byte): Integer;
procedure RGBToHSV(col: Integer; out h, s, v: Byte); overload;
procedure RGBToHSV(col: Integer; out h, s, v: TFloat); overload;
procedure RGBToYUV(col: Integer; out y, u, v: TFloat);
procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat);
procedure RGBToLAB(r, g, b: TFloat; out ol, oa, ob: TFloat);
procedure RGBToLAB(ir, ig, ib: Integer; out ol, oa, ob: TFloat);
function LABToRGB(ll, aa, bb: TFloat): Integer;
function YUVToRGB(y, u, v: TFloat): Integer;
function lerp(x, y, alpha: Double): Double; inline;
function ilerp(x, y, alpha, maxAlpha: Integer): Integer; inline;
function zlerp(x, y: Integer; alpha: Integer): Integer;
function revlerp(x, r, alpha: Double): Double; inline;
function Posterize(v: Byte; cvt: Integer): Byte; inline;
function PosterizeBpc(v, bpc: Byte): Byte; inline;
function CompareEuclideanDCTPtr(pa, pb: PDCTScalar): Cardinal; overload;
function CompareEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar): Cardinal; register; assembler;
function CompareEuclidean(a, b: PDouble; size: Integer): Double; inline;
function CompareCountIndexVSH(const Item1,Item2:PCountIndex):Integer;
function CompareIntegers(Item1,Item2,UserParameter:Pointer):Integer;
function ComparePaletteUseCount(Item1,Item2,UserParameter:Pointer):Integer;
function QuickTestEuclideanDCTPtr(pa, pb: PDCTScalar; min_dist: Cardinal): Boolean;
function QuickTestEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar; min_dist_r8: Cardinal): Boolean; register; assembler;
function ApplyMotionPredictionPenalty(ox, oy, dx, dy: Integer): Cardinal;
generic function DCTInner<T>(pCpn, pLut: T; count: Integer): Double;
function DCTInner_asm(pCpn_rcx, pLut_rdx: PFloat): Double; register; assembler;
function EqualQualityTileCount(tileCount: TFloat): Integer;
function GoldenRatioSearch(Func: TGRSEvalFunc; MinX, MaxX: Double; ObjectiveY: Double;
  EpsilonX, EpsilonY: Double; Data: Pointer): Double;
function EuclideanToPSNR(AEuclidean: Cardinal): Single;

implementation

procedure SpinEnter(Lock: PSpinLock); assembler;
label spin_lock;
asm
spin_lock:
     mov     eax, 1          // Set the EAX register to 1.

     xchg    eax, [Lock]     // Atomically swap the EAX register with the lock variable.
                             // This will always store 1 to the lock, leaving the previous value in the EAX register.

     test    eax, eax        // Test EAX with itself. Among other things, this will set the processor's Zero Flag if EAX is 0.
                             // If EAX is 0, then the lock was unlocked and we just locked it.
                             // Otherwise, EAX is 1 and we didn't acquire the lock.

     jnz     spin_lock       // Jump back to the MOV instruction if the Zero Flag is not set;
                             // the lock was previously locked, and so we need to spin until it becomes unlocked.
end;

procedure SpinLeave(Lock: PSpinLock); assembler;
asm
    xor     eax, eax        // Set the EAX register to 0.

    xchg    eax, [Lock]     // Atomically swap the EAX register with the lock variable.
end;

procedure Exchange(var a, b: Integer);
var
  tmp: Integer;
begin
  tmp := b;
  b := a;
  a := tmp;
end;

function iDiv0(x, y: Integer): Integer;overload;inline;
begin
  Result := 0;
  if y <> 0 then
    Result := x div y;
end;

function iDiv0(x, y: Int64): Int64;overload;inline;
begin
  Result := 0;
  if y <> 0 then
    Result := x div y;
end;

function Div0(x, y: TFloat): TFloat;inline;
begin
  Result := 0;
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

function ToLuma(r, g, b: Byte): Integer; inline;
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
procedure RGBToHSV(col: Integer; out h, s, v: Byte);
var
  rr, gg, bb: Integer;

  function RGBMaxValue: Integer;
  begin
    Result := rr;
    if (Result < gg) then Result := gg;
    if (Result < bb) then Result := bb;
  end;

  function RGBMinValue : Integer;
  begin
    Result := rr;
    if (Result > gg) then Result := gg;
    if (Result > bb) then Result := bb;
  end;

var
  Delta, mx, mn, hh, ss, ll: Integer;
begin
  FromRGB(col, rr, gg, bb);

  mx := RGBMaxValue;
  mn := RGBMinValue;

  hh := 0;
  ss := 0;
  ll := mx;
  if ll <> mn then
  begin
    Delta := ll - mn;
    ss := MulDiv(Delta, 255, ll);

    if (rr = ll) then
      hh := MulDiv(42, gg - bb, Delta)
    else if (gg = ll) then
      hh := MulDiv(42, bb - rr, Delta) + 84
    else if (bb = ll) then
      hh := MulDiv(42, rr - gg, Delta) + 168;

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

procedure RGBToHSV(col: Integer; out h, s, v: TFloat);
var
  bh, bs, bv: Byte;
begin
  bh := 0; bs := 0; bv := 0;
  RGBToHSV(col, bh, bs, bv);
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

procedure RGBToYUV(col: Integer; out y, u, v: TFloat); inline;
var
  yy, uu, vv: TFloat;
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  RGBToYUV(r, g, b, yy, uu, vv);
  y := yy; u := uu; v := vv; // for safe "out" param
end;

procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat);
var
  yy, uu, vv: TFloat;
begin
  yy := r * (cRedMul / cLumaDiv) + g * (cGreenMul / cLumaDiv) + b * (cBlueMul / cLumaDiv);
  uu := (b - yy) * 0.492;
  vv := (r - yy) * 0.877;
{$if cRedMul <> 299}
  {$error RGBToYUV should be changed!}
{$endif}

  y := yy; u := uu; v := vv; // for safe "out" param
end;

function YUVToRGB(y, u, v: TFloat): Integer;
var
  r, g, b: TFloat;
begin
{$if cRedMul = 299}
  r := y + v * 1.13983;
  g := y - u * 0.39465 - v * 0.58060;
  b := y + u * 2.03211;
{$elseif cRedMul = 2126}
  r := y + v * 1.28033;
  g := y - u * 0.21482 - v * 0.38059;
  b := y + u * 2.12798;
{$else}
  {$error YUVToRGB not implemented!}
{$endif}

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

function zlerp(x, y: Integer; alpha: Integer): Integer;
var
  xr, xg, xb, yr, yg, yb, r, g, b: Integer;
begin
  alpha := alpha and (cZoomPx - 1);

  FromRGB(x, xr, xg, xb);
  FromRGB(y, yr, yg, yb);

  r := xr + SarLongint((yr - xr) * alpha, cZoomShift);
  g := xg + SarLongint((yg - xg) * alpha, cZoomShift);
  b := xb + SarLongint((yb - xb) * alpha, cZoomShift);

  Result := ToRGB(r, g, b);
end;

function revlerp(x, r, alpha: Double): Double; inline;
begin
  Result := x + (r - x) / alpha;
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

function CompareEuclideanDCTPtr(pa, pb: PDCTScalar): Cardinal; overload;
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

function CompareEuclideanDCTPtr_asm(pa_rcx, pb_rdx: PDCTScalar): Cardinal; register;
asm
  push rcx
  push rdx

  sub rsp, 16 * 13
  movdqu oword ptr [rsp],       xmm0
  movdqu oword ptr [rsp + $10], xmm1
  movdqu oword ptr [rsp + $20], xmm2
  movdqu oword ptr [rsp + $30], xmm3
  movdqu oword ptr [rsp + $40], xmm4
  movdqu oword ptr [rsp + $50], xmm5
  movdqu oword ptr [rsp + $60], xmm6
  movdqu oword ptr [rsp + $70], xmm7
  movdqu oword ptr [rsp + $80], xmm8
  movdqu oword ptr [rsp + $90], xmm9
  movdqu oword ptr [rsp + $a0], xmm10
  movdqu oword ptr [rsp + $b0], xmm11
  movdqu oword ptr [rsp + $c0], xmm12

  // unrolled for 96 = (cTileDCTSize / 2)

  // step 1

  movdqu xmm1,  oword ptr [rcx]
  movdqu xmm2,  oword ptr [rcx + $10]
  movdqu xmm3,  oword ptr [rcx + $20]
  movdqu xmm4,  oword ptr [rcx + $30]
  movdqu xmm5,  oword ptr [rcx + $40]
  movdqu xmm6,  oword ptr [rcx + $50]
  movdqu xmm6,  oword ptr [rcx + $60]
  movdqu xmm8,  oword ptr [rcx + $70]
  movdqu xmm9,  oword ptr [rcx + $80]
  movdqu xmm10, oword ptr [rcx + $90]
  movdqu xmm11, oword ptr [rcx + $a0]
  movdqu xmm12, oword ptr [rcx + $b0]

  psubsw xmm1,  oword ptr [rdx]
  psubsw xmm2,  oword ptr [rdx + $10]
  psubsw xmm3,  oword ptr [rdx + $20]
  psubsw xmm4,  oword ptr [rdx + $30]
  psubsw xmm5,  oword ptr [rdx + $40]
  psubsw xmm6,  oword ptr [rdx + $50]
  psubsw xmm6,  oword ptr [rdx + $60]
  psubsw xmm8,  oword ptr [rdx + $70]
  psubsw xmm9,  oword ptr [rdx + $80]
  psubsw xmm10, oword ptr [rdx + $90]
  psubsw xmm11, oword ptr [rdx + $a0]
  psubsw xmm12, oword ptr [rdx + $b0]

  pmaddwd xmm1,  xmm1
  pmaddwd xmm2,  xmm2
  pmaddwd xmm3,  xmm3
  pmaddwd xmm4,  xmm4
  pmaddwd xmm5,  xmm5
  pmaddwd xmm6,  xmm6
  pmaddwd xmm7,  xmm7
  pmaddwd xmm8,  xmm8
  pmaddwd xmm9,  xmm9
  pmaddwd xmm10,  xmm10
  pmaddwd xmm11,  xmm11
  pmaddwd xmm12,  xmm12

  paddd xmm1, xmm2
  paddd xmm3, xmm4
  paddd xmm5, xmm6
  paddd xmm7, xmm8
  paddd xmm9, xmm10
  paddd xmm11, xmm12

  paddd xmm1, xmm3
  paddd xmm5, xmm7
  paddd xmm9, xmm11

  paddd xmm1, xmm5
  paddd xmm1, xmm9

  movdqa xmm0, xmm1

  // step 2

  lea rcx, [rcx + $c0]
  lea rdx, [rdx + $c0]

  movdqu xmm1,  oword ptr [rcx]
  movdqu xmm2,  oword ptr [rcx + $10]
  movdqu xmm3,  oword ptr [rcx + $20]
  movdqu xmm4,  oword ptr [rcx + $30]
  movdqu xmm5,  oword ptr [rcx + $40]
  movdqu xmm6,  oword ptr [rcx + $50]
  movdqu xmm6,  oword ptr [rcx + $60]
  movdqu xmm8,  oword ptr [rcx + $70]
  movdqu xmm9,  oword ptr [rcx + $80]
  movdqu xmm10, oword ptr [rcx + $90]
  movdqu xmm11, oword ptr [rcx + $a0]
  movdqu xmm12, oword ptr [rcx + $b0]

  psubsw xmm1,  oword ptr [rdx]
  psubsw xmm2,  oword ptr [rdx + $10]
  psubsw xmm3,  oword ptr [rdx + $20]
  psubsw xmm4,  oword ptr [rdx + $30]
  psubsw xmm5,  oword ptr [rdx + $40]
  psubsw xmm6,  oword ptr [rdx + $50]
  psubsw xmm6,  oword ptr [rdx + $60]
  psubsw xmm8,  oword ptr [rdx + $70]
  psubsw xmm9,  oword ptr [rdx + $80]
  psubsw xmm10, oword ptr [rdx + $90]
  psubsw xmm11, oword ptr [rdx + $a0]
  psubsw xmm12, oword ptr [rdx + $b0]

  pmaddwd xmm1,  xmm1
  pmaddwd xmm2,  xmm2
  pmaddwd xmm3,  xmm3
  pmaddwd xmm4,  xmm4
  pmaddwd xmm5,  xmm5
  pmaddwd xmm6,  xmm6
  pmaddwd xmm7,  xmm7
  pmaddwd xmm8,  xmm8
  pmaddwd xmm9,  xmm9
  pmaddwd xmm10,  xmm10
  pmaddwd xmm11,  xmm11
  pmaddwd xmm12,  xmm12

  paddd xmm1, xmm2
  paddd xmm3, xmm4
  paddd xmm5, xmm6
  paddd xmm7, xmm8
  paddd xmm9, xmm10
  paddd xmm11, xmm12

  paddd xmm1, xmm3
  paddd xmm5, xmm7
  paddd xmm9, xmm11

  paddd xmm1, xmm5
  paddd xmm1, xmm9

  paddd xmm0, xmm1

  // end

  phaddd xmm0, xmm0
  phaddd xmm0, xmm0

  movd eax, xmm0

  movdqu xmm0,  oword ptr [rsp]
  movdqu xmm1,  oword ptr [rsp + $10]
  movdqu xmm2,  oword ptr [rsp + $20]
  movdqu xmm3,  oword ptr [rsp + $30]
  movdqu xmm4,  oword ptr [rsp + $40]
  movdqu xmm5,  oword ptr [rsp + $50]
  movdqu xmm6,  oword ptr [rsp + $60]
  movdqu xmm7,  oword ptr [rsp + $70]
  movdqu xmm8,  oword ptr [rsp + $80]
  movdqu xmm9,  oword ptr [rsp + $90]
  movdqu xmm10, oword ptr [rsp + $a0]
  movdqu xmm11, oword ptr [rsp + $b0]
  movdqu xmm12, oword ptr [rsp + $c0]
  add rsp, 16 * 13

  pop rdx
  pop rcx
end;

function CompareEuclidean(a, b: PDouble; size: Integer): Double; inline;
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

function CompareCountIndexVSH(const Item1,Item2:PCountIndex):Integer;
begin
  Result := CompareValue(Item1^.Val, Item2^.Val);
  if Result = 0 then
    Result := CompareValue(Item1^.Sat, Item2^.Sat);
  if Result = 0 then
    Result := CompareValue(Item1^.Hue, Item2^.Hue);
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

function ApplyMotionPredictionPenalty(ox, oy, dx, dy: Integer): Cardinal; inline;
begin
  // apply a penalty of the euclidean distance to the center
  // rationale: slightly favoring the center in case of ties improves compressibility
  Result := Sqr(ox - dx) + Sqr(oy - dy);
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


function EqualQualityTileCount(tileCount: TFloat): Integer;
begin
  Result := round(sqrt(tileCount) * log2(1 + tileCount));
end;


function GoldenRatioSearch(Func: TGRSEvalFunc; MinX, MaxX: Double; ObjectiveY: Double;
  EpsilonX, EpsilonY: Double; Data: Pointer): Double;
var
  x, y: Double;
begin
  if SameValue(MinX, MaxX, EpsilonX) then
  begin
    Result := MinX;
    Exit;
  end;

  if MinX < MaxX then
    x := lerp(MinX, MaxX, 1.0 - cInvPhi)
  else
    x := lerp(MinX, MaxX, cInvPhi);

  y := Func(x, Data);

  WriteLn('X: ', x:15:6, ' Y: ', y:12:0, ' Mini: ', MinX:15:6, ' Maxi: ', MaxX:15:6);

  case CompareValue(y, ObjectiveY, EpsilonY) of
    LessThanValue:
      Result := GoldenRatioSearch(Func, x, MaxX, ObjectiveY, EpsilonX, EpsilonY, Data);
    GreaterThanValue:
      Result := GoldenRatioSearch(Func, MinX, x, ObjectiveY, EpsilonX, EpsilonY, Data);
  else
      Result := x;
  end;
end;

function EuclideanToPSNR(AEuclidean: Cardinal): Single;
begin
  Result := AEuclidean * (1 / cTileDCTSize);
  Result := 10 * Log10(255 * 255 / Max(0.5, Result));
end;

end.

