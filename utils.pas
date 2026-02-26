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

  cRedMul = 299;
  cGreenMul = 587;
  cBlueMul = 114;

  cRGBw = 16; // in 1 / 32th
  cChromaWeight = 1.0;

  // don't change these

  cLumaDiv = cRedMul + cGreenMul + cBlueMul;

  cBitsPerCompBits = 3;
  cBitsPerComp = 1 shl cBitsPerCompBits;
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
  // from: https://gitlab.xiph.org/xiph/daala/-/blob/gitlab-ci/tools/dump_psnrhvs.c?ref_type=heads

  cDCTWeights: array[0..7, 0..7] of Double = (
    (1.6193873005, 2.2901594831, 2.08509755623, 1.48366094411, 1.00227514334, 0.678296995242, 0.466224900598, 0.3265091542),
    (2.2901594831, 1.94321815382, 2.04793073064, 1.68731108984, 1.2305666963, 0.868920337363, 0.61280991668, 0.436405793551),
    (2.08509755623, 2.04793073064, 1.34329019223, 1.09205635862, 0.875748795257, 0.670882927016, 0.501731932449, 0.372504254596),
    (1.48366094411, 1.68731108984, 1.09205635862, 0.772819797575, 0.605636379554, 0.48309405692, 0.380429446972, 0.295774038565),
    (1.00227514334, 1.2305666963, 0.875748795257, 0.605636379554, 0.448996256676, 0.352889268808, 0.283006984131, 0.226951348204),
    (0.678296995242, 0.868920337363, 0.670882927016, 0.48309405692, 0.352889268808, 0.27032073436, 0.215017739696, 0.17408067321),
    (0.466224900598, 0.61280991668, 0.501731932449, 0.380429446972, 0.283006984131, 0.215017739696, 0.168869545842, 0.136153931001),
    (0.3265091542, 0.436405793551, 0.372504254596, 0.295774038565, 0.226951348204, 0.17408067321, 0.136153931001, 0.109083846276)
  );

  cRGBWeights: array[Boolean, 0 .. cColorCpns - 1] of Double = (
    (1.0, 1.0, 1.0),
    (cRedMul / (cLumaDiv / 3), cGreenMul / (cLumaDiv / 3), cBlueMul / (cLumaDiv / 3))
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

  { TDCTCribbleState }

  TDCTCribbleState = packed record
    Error: Integer;
    X, Y: Integer;
    DX, DY: Integer;
    oxmn, oxmx: Integer;
    oymn, oymx: Integer;
    PenaltyWeight: Integer;
  end;

  PDCTCribbleState = ^TDCTCribbleState;

  TEvalFunc = function(const arg: TDoubleDynArray; data: Pointer): Double of object;
  TGRSEvalFunc = function(x: Double; Data: Pointer): Double of object;

  TGRSResult = record
    X, Y: Double;
  end;

  TDCTScalar = SmallInt;
  PDCTScalar = ^TDCTScalar;
  TDCT = array[0 .. cTileDCTSize - 1] of TDCTScalar;
  TDCTDynArray = array of TDCT;
  TDCTDynArray2 = array of TDCTDynArray;

const
  cBestPSNR = 20.0 * Ln((1 shl cBitsPerComp) - 1) / Ln(10.0);

procedure SpinEnter(Lock: PSpinLock); assembler;
procedure SpinLeave(Lock: PSpinLock); assembler;
procedure Exchange(var a, b: Integer);
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
procedure RGBToHSV(col: Integer; out h, s, v: Byte); overload;
procedure RGBToHSV(col: Integer; out h, s, v: TFloat); overload;
procedure RGBToYUV(col: Integer; out y, u, v: TFloat; scl: TFloat);
procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat; scl: TFloat);
procedure RGBToLAB(r, g, b: TFloat; out ol, oa, ob: TFloat);
procedure RGBToLAB(ir, ig, ib: Integer; out ol, oa, ob: TFloat);
function LABToRGB(ll, aa, bb: TFloat): Integer;
function YUVToRGB(y, u, v, scl: TFloat): Integer;
function lerp(x, y, alpha: Double): Double; inline;
function ilerp(x, y, alpha, maxAlpha: Integer): Integer; inline;
function revlerp(x, r, alpha: Double): Double; inline;
function BlendRGB(x, y, alphax, alphay: Integer; shift: Byte): Integer;
function InsertRGB(col: Integer; value, cpn: Integer): Integer;
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
procedure CribbleEuclideanDCTPtr(cur: PDCTScalar; prev: PDCTScalar; state: PDCTCribbleState; oy: Integer);
procedure CribbleEuclideanDCTPtr_asm(cur_rcx: PDCTScalar; prev_rdx: PDCTScalar; state_r8: PDCTCribbleState; oy_r9: Integer); register; assembler;
generic function DCTInner<T>(pCpn, pLut: T; count: Integer): Double;
function DCTInner_asm(pCpn_rcx, pLut_rdx: PFloat): Double; register; assembler;
function EqualQualityTileCount(tileCount: Double): Integer;
function GoldenRatioSearch(Func: TGRSEvalFunc; MinX, MaxX: Double; ObjectiveY: Double; EpsilonX, EpsilonY: Double; Data: Pointer): TGRSResult;
function EuclideanToPSNR(AEuclidean: Double): Double;
function PSNRToEuclidean(APSNR: Double): Cardinal;

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

procedure RGBToYUV(col: Integer; out y, u, v: TFloat; scl: TFloat); inline;
var
  yy, uu, vv: TFloat;
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  RGBToYUV(r, g, b, yy, uu, vv, scl);
  y := yy; u := uu; v := vv; // for safe "out" param
end;

procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat; scl: TFloat);
begin
  y := (16  +  65.481 / 255.0 * r + 128.553 / 255.0 * g +  24.966 / 255.0 * b) * scl;
  u := (128 -  37.797 / 255.0 * r -  74.203 / 255.0 * g + 112.000 / 255.0 * b) * scl;
  v := (128 + 112.000 / 255.0 * r -  93.786 / 255.0 * g -  18.214 / 255.0 * b) * scl;
end;

function YUVToRGB(y, u, v, scl: TFloat): Integer;
var
  r, g, b: TFloat;
begin
  r := 298.082 / (256.0 * scl) * y                               + 408.583 / (256.0 * scl) * v - 222.921;
  g := 298.082 / (256.0 * scl) * y - 100.291 / (256.0 * scl) * u - 208.120 / (256.0 * scl) * v + 135.576;
  b := 298.082 / (256.0 * scl) * y + 516.412 / (256.0 * scl) * u                               - 276.836;

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

function revlerp(x, r, alpha: Double): Double; inline;
begin
  Result := x + (r - x) / alpha;
end;

function BlendRGB(x, y, alphax, alphay: Integer; shift: Byte): Integer;
var
  r1, g1, b1: Integer;
  r2, g2, b2: Integer;
begin
  FromRGB(x, r1, g1, b1);
  FromRGB(y, r2, g2, b2);

  r1 := (r1 * alphax + r2 * alphay) shr shift;
  g1 := (g1 * alphax + g2 * alphay) shr shift;
  b1 := (b1 * alphax + b2 * alphay) shr shift;

  r1 := EnsureRange(r1, 0, High(Byte));
  g1 := EnsureRange(g1, 0, High(Byte));
  b1 := EnsureRange(b1, 0, High(Byte));

  Result := ToRGB(r1, g1, b1);
end;

function InsertRGB(col: Integer; value, cpn: Integer): Integer;
var
  mask: Integer;
begin
  mask := -1 xor (((1 shl cBitsPerComp) - 1) shl (cpn shl cBitsPerCompBits));
  Result := (col and mask) or (value shl (cpn shl cBitsPerCompBits));
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

procedure CribbleEuclideanDCTPtr(cur: PDCTScalar; prev: PDCTScalar; state: PDCTCribbleState; oy: Integer);
var
  ox: Integer;
  err, best: Cardinal;
begin
  best := state^.Error;

  for ox := state^.oxmn to state^.oxmx do
  begin
    if QuickTestEuclideanDCTPtr_asm(cur, prev, best) then
    begin
      err := CompareEuclideanDCTPtr_asm(cur, prev);
      err += ApplyMotionPredictionPenalty(ox, oy, state^.DX, state^.DY) * state^.PenaltyWeight;

      if err < best then
      begin
        best := err;
        state^.Error := err;
        state^.Y := oy;
        state^.X := ox;
      end;
    end;

    Inc(prev, cTileDCTSize);
  end;
end;

procedure CribbleEuclideanDCTPtr_asm(cur_rcx: PDCTScalar; prev_rdx: PDCTScalar; state_r8: PDCTCribbleState; oy_r9: Integer); register; assembler;
label
  xloop, evicted, worse;
asm
  push rax
  push rbx
  push rdx
  push rsi
  push rdi
  push r10
  push r11
  push r12
  push r13

  sub rsp, 16 * 2
  movdqu oword ptr [rsp], xmm0
  movdqu oword ptr [rsp + $10], xmm1

  movdqu xmm1, oword ptr [rcx]

  mov ebx, dword ptr [r8]
  mov r10d, dword ptr [r8 + 3 * 4]
  mov r11d, dword ptr [r8 + 4 * 4]
  mov esi, dword ptr [r8 + 5 * 4]
  mov edi, dword ptr [r8 + 6 * 4]
  mov r13d, dword ptr [r8 + 9 * 4]

  xloop:
    movdqa xmm0, xmm1
    psubsw xmm0, oword ptr [rdx]

    pmaddwd xmm0, xmm0

    phaddd xmm0, xmm0
    phaddd xmm0, xmm0

    movd eax, xmm0
    cmp eax, ebx
    jae evicted

        call CompareEuclideanDCTPtr_asm

        mov r12d, esi
        sub r12d, r10d
        imul r12d, r12d
        imul r12d, r13d
        add eax, r12d

        mov r12d, r9d
        sub r12d, r11d
        imul r12d, r12d
        imul r12d, r13d
        add eax, r12d

        cmp eax, ebx
        jae worse

           mov ebx, eax
           mov dword ptr [r8 + 1 * 4], esi
           mov dword ptr [r8 + 2 * 4], r9d

        worse:

    evicted:

    add rdx, 192 * 2

    inc esi
    cmp esi, edi
    jbe xloop

  mov dword ptr [r8], ebx

  movdqu xmm0, oword ptr [rsp]
  movdqu xmm1, oword ptr [rsp + $10]
  add rsp, 16 * 2

  pop r13
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

function EuclideanToPSNR(AEuclidean: Double): Double;
begin
  Result := AEuclidean * (1 / cTileDCTSize);
  Result := cBestPSNR - 10.0 * Log10(Max(1.0, Result));
end;

function PSNRToEuclidean(APSNR: Double): Cardinal;
begin
  Result := Round(Power(10.0, (cBestPSNR - APSNR) * 0.1) * cTileDCTSize);
end;

end.

