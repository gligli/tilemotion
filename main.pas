unit main;

{$mode objfpc}{$H+}

{$define ASM_DBMP}

interface

uses
  LazLogger, Classes, SysUtils, windows, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls, FPimage, FPReadPNG, fgl,
  StdCtrls, ComCtrls, Spin, Menus, Math, types, Process, strutils, kmodes, MTProcs, extern, typinfo, tbbmalloc, LCLType;

type
  TPsyVisMode = (pvsDCT, pvsWeightedDCT, pvsWavelets, pvsSpeDCT, pvsWeightedSpeDCT);
  TEncoderStep = (esNone = -1, esLoad = 0, esKeyFrameTiling, esFrameTiling, esDither, esMakeUnique, esFixupTileCount, esReindex, esSmooth, esSave);

const
  cEncoderStepLen: array[TEncoderStep] of Integer = (0, 4, 2, 3, 5, 2, 1, 3, 1, 2);

  cPhi = (1 + sqrt(5)) / 2;
  cInvPhi = 1 / cPhi;

  // Tweakable params
  cGamma: array[0..1] of TFloat = (1.8, 0.9);

{$if false}
  cRedMul = 2126;
  cGreenMul = 7152;
  cBlueMul = 722;
{$else}
  cRedMul = 299;
  cGreenMul = 587;
  cBlueMul = 114;
{$endif}
  cLumaDiv = cRedMul + cGreenMul + cBlueMul;
  cRGBw = 13; // in 1 / 32th

  // SMS consts
  cVecInvWidth = 16;
  cBitsPerComp = 2;
  cTotalColors = 1 shl (cBitsPerComp * 3);
  cTileWidth = 8;
  cPaletteCount = 2;
  cTilePaletteSize = 16;
  cTileMapWidth = 32;
  cTileMapHeight = 24;
  cTileMapSize = cTileMapWidth * cTileMapHeight;
  cScreenWidth = cTileMapWidth * cTileWidth;
  cScreenHeight = cTileMapHeight * cTileWidth;
  cVRAMWriteCmd = $4000;
  cBankSize = 16384;
  cTileSize = cTileWidth * cTileWidth div 2;
  cTilesPerBank = cBankSize div cTileSize;
  cZ80Clock = 3546893;
  cLineCount = 313;
  cRefreshRate = 50;
  cCyclesPerLine = cZ80Clock * 127 div 128 / (cLineCount * cRefreshRate);
  cCyclesPerDisplayPhase : array[Boolean{VBlank?}] of Integer = (
    Round(cScreenHeight * cCyclesPerLine),
    Round((cLineCount - cScreenHeight) * cCyclesPerLine)
  );

  // Video player consts
  cRefreshRateDiv = 3;
  cMaxTilesPerFrame = 414;
  cSmoothingPrevFrame = 2;
  cTileIndexesTileOffset = cTilesPerBank + 1;
  cTileIndexesMaxDiff = 223;
  cTileIndexesRepeatStart = 224;
  cTileIndexesMaxRepeat = 30;
  cTileIndexesDirectValue = 223;
  cTileIndexesTerminator = 254;
  cTileIndexesVBlankSwitch = 255;
  cTileMapIndicesOffset : array[0..1] of Integer = (49, 256 + 49);
  cTileMapCacheBits = 5;
  cTileMapCacheSize = 1 shl cTileMapCacheBits;
  cTileMapMaxRepeat : array[Boolean{Raw?}] of Integer = (5, 4);
  cTileMapMaxSkip = 31;
  cTileMapCommandCache : array[1..5{Rpt}] of Byte = ($01, $40, $41, $80, $81);
  cTileMapCommandSkip = $00;
  cTileMapCommandRaw : array[1..4{Rpt}] of Byte = ($c0, $d0, $e0, $f0);
  cTileMapTerminator = $00; // skip 0
  cClocksPerSample = 344;
  cFrameSoundSize = cZ80Clock / cClocksPerSample / 2 / (cRefreshRate / cRefreshRateDiv);

  // number of Z80 cycles to execute a function
  cTileIndexesTimings : array[Boolean {VBlank?}, 0..4 {Direct/Std/RptFix/RptVar/VBlankSwitch}] of Integer = (
    (343 + 688 + 40, 289 + 17 + 688, 91 + 5, 213 + 12 + 688, 113 + 7),
    (347 + 344 + 40, 309 + 18 + 344, 91 + 5, 233 + 14 + 344, 113 + 7)
  );
  cLineJitterCompensation = 3;
  cTileIndexesInitialLine = 202; // algo starts in VBlank

  cColorCpns = 3;
  cTileDCTSize = cColorCpns * sqr(cTileWidth);
  cUnrolledDCTSize = sqr(sqr(cTileWidth));

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

type
  TSpinlock = LongInt;
  PSpinLock = ^TSpinlock;

  TFloatFloatFunction = function(x: TFloat; Data: Pointer): TFloat of object;

  PTile = ^TTile;
  PPTile = ^PTile;

  TPalPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Byte;
  TRGBPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Integer;
  TCpnPixels = array[0..cColorCpns-1, 0..cTileWidth-1,0..cTileWidth-1] of TFloat;
  PPalPixels = ^TPalPixels;

  TTile = record
    RGBPixels: TRGBPixels;
    PalPixels: TPalPixels;

    PaletteIndexes: TIntegerDynArray;
    PaletteRGB: TIntegerDynArray;

    Active: Boolean;
    UseCount, TmpIndex, MergeIndex: Integer;
  end;

  PTileMapItem = ^TTileMapItem;

  TTileMapItem = record
    TileIdx, FrameTileIndex, TmpIndex: Integer;
    HMirror, VMirror, SpritePal, FrameTileSpritePal, Smoothed: Boolean;
  end;

  TTileMapItems = array of TTileMapItem;

  TTileIndex = record
    RomIndex, VramIndex: Integer;
    InVRAM: Boolean;
  end;

  PTileIndex = ^TTileIndex;

  TTilesIndexes = array of TTileIndex;

  PKeyFrame = ^TKeyFrame;

  TFrame = record
    Index: Integer;
    Tiles: array[0..(cTileMapSize - 1)] of TTile;
    TilesIndexes: TTilesIndexes;
    TileMap: array[0..(cTileMapHeight - 1),0..(cTileMapWidth - 1)] of TTileMapItem;
    FSPixels: TByteDynArray;
    KeyFrame: PKeyFrame;
  end;

  PFrame = ^TFrame;

  TMixingPlan = record
    // static
    LumaPal: array of Integer;
    Y2Palette: array of array[0..3] of Integer;
    Y2MixedColors: Integer;
  end;

  TKeyFrame = record
    StartFrame, EndFrame, FrameCount: Integer;
    FramesLeft: Integer;

    PaletteIndexes: array[Boolean{SpritePal?}] of TIntegerDynArray;
    PaletteRGB: array[Boolean{SpritePal?}] of TIntegerDynArray;

    CS: TRTLCriticalSection;

    PaletteUseCount: array [Boolean] of packed record
      UseCount: Integer;
      PaletteIndexes: TIntegerDynArray;
      PaletteRGB: TIntegerDynArray;
      SpritePal: Boolean;
    end;
  end;

  TTileCache = array[0 .. cTilesPerBank - 1] of record
    Frame: Integer;
    TileIdx: Integer;
  end;

  TCountIndex = packed record
    Index, Count, Luma: Integer;
    R, G, B: Byte;
    Hue, Sat, Val: Byte;
  end;

  PCountIndex = ^TCountIndex;
  TCountIndexList = specialize TFPGList<PCountIndex>;

  TDCTScalar = SmallInt;
  PDCTScalar = ^TDCTScalar;
  TDCT = array[0 .. cTileDCTSize - 1] of TDCTScalar;
  TDCTDynArray = array of TDCT;

  { TMainForm }

  TMainForm = class(TForm)
    btChooseFile: TButton;
    btnRunAll: TButton;
    btnDebug: TButton;
    cbxYilMix: TComboBox;
    chkGamma: TCheckBox;
    chkReduced: TCheckBox;
    chkSprite: TCheckBox;
    chkMirrored: TCheckBox;
    chkDithered: TCheckBox;
    chkPlay: TCheckBox;
    chkUseTK: TCheckBox;
    edInput: TEdit;
    edOutputDir: TEdit;
    edWAV: TEdit;
    imgPalette: TImage;
    Label1: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    lblCorrel: TLabel;
    lblPct: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label9: TLabel;
    lblTileCount: TLabel;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    MenuItem7: TMenuItem;
    miIntra: TMenuItem;
    miLoad: TMenuItem;
    MenuItem1: TMenuItem;
    odInput: TOpenDialog;
    pmProcesses: TPopupMenu;
    PopupMenu1: TPopupMenu;
    pbProgress: TProgressBar;
    seQbTiles: TFloatSpinEdit;
    seMaxTiles: TSpinEdit;
    seMaxTPF: TSpinEdit;
    sePage: TSpinEdit;
    IdleTimer: TIdleTimer;
    imgTiles: TImage;
    imgSource: TImage;
    imgDest: TImage;
    seFrameCount: TSpinEdit;
    seTempoSmoo: TFloatSpinEdit;
    tbFrame: TTrackBar;

    procedure btChooseFileClick(Sender: TObject);
    procedure chkUseTKChange(Sender: TObject);
    procedure edInputChange(Sender: TObject);
    procedure edWAVChange(Sender: TObject);

    procedure btnLoadClick(Sender: TObject);
    procedure btnDoKeyFrameTilingClick(Sender: TObject);
    procedure btnFrameTileClick(Sender: TObject);
    procedure btnDitherClick(Sender: TObject);
    procedure btnMakeUniqueClick(Sender: TObject);
    procedure btnFixupClick(Sender: TObject);
    procedure btnReindexClick(Sender: TObject);
    procedure btnSmoothClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);

    procedure btnRunAllClick(Sender: TObject);
    procedure cbxYilMixChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure IdleTimerTimer(Sender: TObject);
    procedure seQbTilesEditingDone(Sender: TObject);
    procedure seMaxTilesEditingDone(Sender: TObject);
    procedure tbFrameChange(Sender: TObject);
  private
    FKeyFrames: array of PKeyFrame;
    FFrames: array of TFrame;
    FColorMap: array[0..cTotalColors - 1] of Integer;
    FColorMapLuma: array[0..cTotalColors - 1] of Integer;
    FColorMapHue: array[0..cTotalColors - 1] of Integer;
    FColorMapImportance: array[0..cTotalColors - 1] of Integer;
    FTiles: array of PTile;

    FInputPath, FWAVFile: String;
    FUseThomasKnoll: Boolean;
    FY2MixedColors: Integer;
    FFrameTilingMode: TPsyVisMode;
    FGlobalTilingMode: TPsyVisMode;

    FProgressStep: TEncoderStep;
    FProgressPosition, FOldProgressPosition, FProgressStartTime, FProgressPrevTime: Integer;

    FCS: TRTLCriticalSection;

    function PearsonCorrelation(const x: TFloatDynArray; const y: TFloatDynArray): TFloat;
    function ComputeCorrelation(const a, b: TIntegerDynArray): TFloat;
    function ComputeInterFrameCorrelation(a, b: TFrame): TFloat;

    procedure LoadFrame(AFrame: PFrame; ABitmap: TCustomBitmap);
    procedure FindKeyFrames;
    procedure ProgressRedraw(CurFrameIdx: Integer = -1; ProgressStep: TEncoderStep = esNone);
    procedure Render(AFrameIndex: Integer; dithered, mirrored, reduced, gamma: Boolean; palIdx: Integer; ATilePage: Integer
     );

    procedure RGBToHSV(col: Integer; out h, s, v: Byte); overload;
    procedure RGBToHSV(col: Integer; out h, s, v: TFloat); overload;
    procedure RGBToYUV(col: Integer; out y, u, v: TFloat);
    procedure RGBToYUV(r, g, b: Byte; out y, u, v: TFloat);
    procedure RGBToLAB(r, g, b: TFloat; out ol, oa, ob: TFloat);
    procedure RGBToLAB(ir, ig, ib: Integer; out ol, oa, ob: TFloat);
    function LABToRGB(ll, aa, bb: TFloat): Integer;
    function YUVToRGB(y, u, v: TFloat): Integer;

    generic procedure WaveletGS<T, PT>(Data: PT; Output: PT; dx, dy, depth: cardinal);
    generic procedure DeWaveletGS<T, PT>(wl: PT; pic: PT; dx, dy, depth: longint);

    procedure ConvertToCpnPixels(const ATile: TTile; FromPal, UseLAB, HMirror, VMirror: Boolean;
     const APalette: TIntegerDynArray; out ACpnPixel: TCpnPixels);
    procedure ComputeCpnPixelsPsyVisFeatures(const ACpnPixel: TCpnPixels; Mode: TPsyVisMode; ColorCpns: Integer;
     ADCT: PDCTScalar);
    procedure ComputeTilePsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; FromPal, UseLAB, HMirror,
     VMirror: Boolean; ColorCpns: Integer; const APalette: TIntegerDynArray; ADCT: PFloat);
    procedure ComputeInvTilePsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; UseLAB: Boolean; ColorCpns: Integer;
     var ATile: TTile);

    // Dithering algorithms ported from http://bisqwit.iki.fi/story/howto/dither/jy/

    function CompareColor(r1, g1, b1, r2, g2, b2: Int64): Int64;
    procedure PreparePlan(var Plan: TMixingPlan; MixedColors: Integer; const pal: array of Integer);
    procedure TerminatePlan(var Plan: TMixingPlan);
    function DeviseBestMixingPlan(var Plan: TMixingPlan; col: Integer; const List: TByteDynArray): Integer;
    procedure DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: TByteDynArray);
    procedure DitherTile(var ATile: TTile; var Plan: TMixingPlan);

    procedure LoadTiles;
    procedure MirrorTiles(AOnPal, ASimple: Boolean);

    function GetGlobalTileCount: Integer;
    function GetFrameTileCount(AFrame: PFrame; ADelta, AFromTileIdxs: Boolean; ADeltaFrame: PFrame = nil): Integer;
    function GetKeyFrameFrameMaxTileCount(AKF: PKeyFrame; ADelta, ADeltaUsePrevKF: Boolean): Integer;
    procedure CopyTile(const Src: TTile; var Dest: TTile);
    function GetTileUseCount(ATileIndex: Integer): Integer;

    procedure Pallettize(AKeyFrame: PKeyFrame);
    procedure QuantizePalette(AKeyFrame: PKeyFrame; ASpritePal: Boolean);
    procedure FinishQuantizePalette(AKeyFrame: PKeyFrame);
    procedure DitherTiles(AKF: PKeyFrame);

    procedure HMirrorTile(var ATile: TTile);
    procedure VMirrorTile(var ATile: TTile);
    function GetTileZoneSum(const ATile: TTile; AOnPal: Boolean; x, y, w, h: Integer): Integer;
    function GetTileIndexTMItem(ATileIndex: Integer; out AFrame: TFrame): PTileMapItem;

    procedure MakeTilesUnique;
    procedure MergeTiles(const TileIndexes: array of Integer; TileCount: Integer; BestIdx: Integer);
    procedure InitMergeTiles;
    procedure FinishMergeTiles;

    function WriteTileDatasetLine(const ATile: TTile; var DataLine: array of Byte): Integer;
    procedure DoKeyFrameTiling(AKeyFrame: PKeyFrame; DesiredNbTiles: Integer);
    procedure DoFrameTiling(AFrame: PFrame; DesiredNbTiles: Integer; Dual: Boolean);
    procedure FixupTileCount(AFrame: PFrame; DesiredNbTiles: Integer; Dual: Boolean);

    procedure ReindexTiles;
    procedure IndexFrameTiles(AFrame: PFrame);
    procedure DoTemporalSmoothing(AFrameIdx: Integer; Y: Integer; Strength: TFloat);

    function DoExternalPCMEnc(AFN: String; Volume: Integer): String;
    function DoExternalFFMpeg(AFN: String; var AVidPath: String; var AAudioFile: String; AFrameCount: Integer): String;

    procedure SaveTileIndexes(ADataStream: TStream; AFrame: PFrame);
    procedure SaveTilemap(ADataStream: TStream; AFrame: PFrame; AFrameIdx: Integer; ASkipFirst: Boolean);

    procedure BuildTileCacheLUT(var TileCacheLUT: TIntegerDynArray2; AFrameIdx: Integer = -1);
    procedure InitTileCache(var TileCache: TTileCache);
    function PrepareVRAMTileIndexes(AFrameIdx: Integer; var ATileIndexes: TTilesIndexes; var TileCache: TTileCache;
      const TileCacheLUT: TIntegerDynArray2): Integer;
    procedure PrefetchVRAMTileIndexes(AFrame: PFrame; AUploadLimit: Integer; var TileCache: TTileCache; var TileCacheLUT: TIntegerDynArray2);

    procedure Save(ADataStream, ASoundStream: TStream);

    procedure ClearAll;
  public
    { public declarations }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

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

function iDiv0(x,y:Integer):Integer;inline;
begin
  Result:=0;
  if y <> 0 then
    Result:=x div y;
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

function CompareEuclideanDCTPtr(pa, pb: PFloat): TFloat;
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

function CompareEuclideanDCT(const a, b: TFloatDynArray): TFloat; inline;
begin
  Result := CompareEuclideanDCTPtr(@a[0], @b[0]);
end;

var
  gGammaCorLut: array[-1..High(cGamma), 0..High(Byte)] of TFloat;
  gVecInv: array[0..256 * 4 - 1] of Cardinal;
  gDCTLut:array[Boolean {Special?}, 0..cUnrolledDCTSize - 1] of TFloat;
  gInvDCTLut:array[0..cUnrolledDCTSize - 1] of TFloat;

procedure InitLuts;
var
  g, i, v, u, y, x: Int64;
begin
  // gamma

  for g := -1 to High(cGamma) do
    for i := 0 to High(Byte) do
      if g >= 0 then
        gGammaCorLut[g, i] := power(i / 255.0, cGamma[g])
      else
        gGammaCorLut[g, i] := i / 255.0;

  // inverse

  for i := 0 to High(gVecInv) do
    gVecInv[i] := iDiv0(1 shl cVecInvWidth, i shr 2);

  // DCT

  i := 0;
  for v := 0 to cTileWidth - 1 do
    for u := 0 to cTileWidth - 1 do
      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
        begin
          gDCTLut[False, i] := cos((x + 0.5) * u * PI / (cTileWidth)) * cos((y + 0.5) * v * PI / (cTileWidth)) * cDCTUVRatio[Min(v, 7), Min(u, 7)];
          gDCTLut[True, i] := cos((x + 0.5) * u * PI / (cTileWidth * 2)) * cos((y + 0.5) * v * PI / (cTileWidth * 2)) * cDCTUVRatio[Min(v, 7), Min(u, 7)];
          Inc(i);
        end;

  // inverse DCT

  i := 0;
  for v := 0 to cTileWidth - 1 do
    for u := 0 to cTileWidth - 1 do
      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
        begin
          gInvDCTLut[i] := cos((u + 0.5) * x * PI / (cTileWidth)) * cos((v + 0.5) * y * PI / (cTileWidth)) * cDCTUVRatio[Min(y, 7), Min(x, 7)] * 2 / (cTileWidth) * 2 / (cTileWidth);
          Inc(i);
        end;
end;

function GammaCorrect(lut: Integer; x: Byte): TFloat; inline;
begin
  Result := gGammaCorLut[lut, x];
end;

function GammaUncorrect(lut: Integer; x: TFloat): Byte;
begin
  if lut >= 0 then
    x := power(x, 1 / cGamma[lut]);
  Result := EnsureRange(Round(x * 255.0), 0, 255);
end;

function lerp(x, y, alpha: TFloat): TFloat; inline;
begin
  Result := x + (y - x) * alpha;
end;

function revlerp(x, y, alpha: TFloat): TFloat; inline;
begin
  Result := (alpha - x) / (y - x);
end;

function Posterize(v, bpc: Byte): Byte; inline;
var
  cvt: Integer;
begin
  cvt := (1 shl bpc) - 1;

  Result := min(255, Round(Round((v * cvt) / 255.0) * 255.0 / cvt));
end;

function Decimate(col: Integer): Integer; inline;
var
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  r := r shr (8 - cBitsPerComp);
  g := g shr (8 - cBitsPerComp);
  b := b shr (8 - cBitsPerComp);
  Result := r or (g shl cBitsPerComp) or (b shl (cBitsPerComp * 2));
end;

function ToLuma(r, g, b: Byte): Byte; inline;
begin
  Result := (r * cRedMul + g * cGreenMul + b * cBlueMul) div cLumaDiv;
end;

function PlanCompareLuma(Item1,Item2,UserParameter:Pointer):Integer;
var
  pi1, pi2: PInteger;
begin
  pi1 := PInteger(UserParameter);
  pi2 := PInteger(UserParameter);

  Inc(pi1, PByte(Item1)^);
  Inc(pi2, PByte(Item2)^);

  Result := CompareValue(pi1^, pi2^);
end;

function CompareEuclidean(const a, b: TFloatDynArray): TFloat; inline;
var
  i: Integer;
begin
  Result := 0;
  if Length(a) = 0 then
    Exit;

  for i := 0 to High(a) do
    Result += sqr(a[i] - b[i]);

  Result := sqrt(Result / Length(a));
end;

function EqualQualityTileCount(tileCount: TFloat): Integer;
begin
  Result := round(sqrt(tileCount) * log2(1 + tileCount));
end;

function EuclideanToPSNR(AEuclidean: Cardinal): Single;
begin
  Result := AEuclidean * (1 / cTileDCTSize);
  Result := 10 * Log10(255 * 255 / Max(0.5, Result));
end;


{ TMainForm }

function TMainForm.PearsonCorrelation(const x: TFloatDynArray; const y: TFloatDynArray): TFloat;
var
  mx, my, num, den, denx, deny: TFloat;
  i: Integer;
begin
  Assert(Length(x) = Length(y));

  mx := mean(x);
  my := mean(y);

  num := 0.0;
  denx := 0.0;
  deny := 0.0;
  for i := 0 to High(x) do
  begin
    num += (x[i] - mx) * (y[i] - my);
    denx += sqr(x[i] - mx);
    deny += sqr(y[i] - my);
  end;

  denx := sqrt(denx);
  deny := sqrt(deny);
  den := denx * deny;

  Result := 1.0;
  if den <> 0.0 then
    Result := num / den;
end;

function TMainForm.ComputeCorrelation(const a, b: TIntegerDynArray): TFloat;
var
  i: Integer;
  ya, yb: TDoubleDynArray;
  fr, fg, fb: TFloat;
begin
  SetLength(ya, Length(a) * 3);
  SetLength(yb, Length(a) * 3);

  for i := 0 to High(a) do
  begin
    fr := (a[i] shr 16) and $ff; fg := (a[i] shr 8) and $ff; fb := a[i] and $ff;
    ya[i] := fr; ya[i + Length(a)] := fg; ya[i + Length(a) * 2] := fb;

    fr := (b[i] shr 16) and $ff; fg := (b[i] shr 8) and $ff; fb := b[i] and $ff;
    yb[i] := fr; yb[i + Length(a)] := fg; yb[i + Length(a) * 2] := fb;
  end;

  Result := PearsonCorrelation(ya, yb);
end;

function TMainForm.ComputeInterFrameCorrelation(a, b: TFrame): TFloat;
var
  sz, i: Integer;
  ya, yb: TFloatDynArray;
begin
  Assert(Length(a.FSPixels) = Length(b.FSPixels));
  sz := Length(a.FSPixels) div 3;
  SetLength(ya, sz * 3);
  SetLength(yb, sz * 3);

  for i := 0 to sz - 1 do
  begin
    ya[i + sz * 0] := a.FSPixels[i * 3 + 0];
    ya[i + sz * 1] := a.FSPixels[i * 3 + 1];
    ya[i + sz * 2] := a.FSPixels[i * 3 + 2];

    yb[i + sz * 0] := b.FSPixels[i * 3 + 0];
    yb[i + sz * 1] := b.FSPixels[i * 3 + 1];
    yb[i + sz * 2] := b.FSPixels[i * 3 + 2];
  end;

  Result := PearsonCorrelation(ya, yb);
end;

procedure TMainForm.btnDoKeyFrameTilingClick(Sender: TObject);
var
  eqtc: TIntegerDynArray;

  procedure DoKF(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    DoKeyFrameTiling(FKeyFrames[AIndex], eqtc[AIndex]);
  end;

var
  iKF, dnt, acc: Integer;
  rt: TFloat;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esKeyFrameTiling);

  dnt := seMaxTiles.Value;

  acc := 0;
  SetLength(eqtc, Length(FKeyFrames));
  for iKF := 0 to High(FKeyFrames) do
  begin
    eqtc[iKF] := EqualQualityTileCount(FKeyFrames[iKF]^.FrameCount * cTileMapSize);
    acc += eqtc[iKF];
  end;

  rt := dnt / acc;
  for iKF := 0 to High(FKeyFrames) do
    eqtc[iKF] := Max(1, round(eqtc[iKF] * rt));

  MirrorTiles(False, True);
  ProgressRedraw(1);

  InitMergeTiles;
  ProcThreadPool.DoParallelLocalProc(@DoKF, 0, High(FKeyFrames));
  FinishMergeTiles;
  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.btnDitherClick(Sender: TObject);

  procedure DoPalettize(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    if not InRange(AIndex, 0, High(FKeyFrames)) then
      Exit;

    Pallettize(FKeyFrames[AIndex]);
  end;

  procedure DoQuantize(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    if not InRange(AIndex, 0, Length(FKeyFrames) * 2 - 1) then
      Exit;

    QuantizePalette(FKeyFrames[AIndex div 2], Odd(AIndex));
  end;

  procedure DoDither(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    if not InRange(AIndex, 0, High(FKeyFrames)) then
      Exit;

    DitherTiles(FKeyFrames[AIndex]);
  end;

var
  i: Integer;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esDither);

  MirrorTiles(False, False);
  ProgressRedraw(1);

  ProcThreadPool.DoParallelLocalProc(@DoPalettize, 0, High(FKeyFrames));
  ProgressRedraw(2);

  ProcThreadPool.DoParallelLocalProc(@DoQuantize, 0, Length(FKeyFrames) * 2 - 1);
  for i := 0 to High(FKeyFrames) do
    FinishQuantizePalette(FKeyFrames[i]);
  ProgressRedraw(3);

  ProcThreadPool.DoParallelLocalProc(@DoDither, 0, High(FKeyFrames));
  ProgressRedraw(4);

  LoadTiles;
  ProgressRedraw(5);

  tbFrameChange(nil);
end;

procedure TMainForm.btnMakeUniqueClick(Sender: TObject);
begin
  ProgressRedraw(-1, esMakeUnique);

  MirrorTiles(True, True);
  ProgressRedraw(1);

  InitMergeTiles;
  MakeTilesUnique;
  FinishMergeTiles;
  ProgressRedraw(2);

  tbFrameChange(nil);
end;


procedure TMainForm.btnFixupClick(Sender: TObject);
var
  i, MaxTPF: Integer;
begin
  ProgressRedraw(-1, esFixupTileCount);

  MaxTPF := seMaxTPF.Value;

  for i := 0 to High(FFrames) do
    if GetFrameTileCount(@FFrames[i], True, False) > MaxTPF then
    begin
      InitMergeTiles;
      FixupTileCount(@FFrames[i], MaxTPF, True);
      FinishMergeTiles;

      Write((i + 1):6,' / ', Length(FFrames), #13);
    end;
  WriteLn;

  ProgressRedraw(1);

  tbFrameChange(nil);
end;

procedure TMainForm.chkUseTKChange(Sender: TObject);
begin
  FUseThomasKnoll := chkUseTK.Checked;
end;

procedure TMainForm.edInputChange(Sender: TObject);
begin
  FInputPath := edInput.Text;
end;

procedure TMainForm.edWAVChange(Sender: TObject);
begin
  FWAVFile := edWAV.Text;
end;

procedure TMainForm.btnFrameTileClick(Sender: TObject);

  procedure Pass(MaxTPF: Integer; Dual: Boolean);
  var
    i: Integer;
  begin
    for i := 0 to High(FFrames) do
    begin
      InitMergeTiles;
      DoFrameTiling(@FFrames[i], MaxTPF, Dual);
      FinishMergeTiles;

      Write((i + 1):6,' / ', Length(FFrames), #13);
    end;

    WriteLn;
  end;

var
  MaxTPF: Integer;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esFrameTiling);

  MaxTPF := seMaxTPF.Value;

  MirrorTiles(False, False);
  ProgressRedraw(1);

  Pass(MaxTPF, False);
  ProgressRedraw(2);

  Pass(MaxTPF, True);
  ProgressRedraw(3);

  tbFrameChange(nil);
end;

procedure TMainForm.btChooseFileClick(Sender: TObject);
begin
  if odInput.Execute then
    edInput.Text := odInput.FileName;
end;

procedure TMainForm.btnLoadClick(Sender: TObject);

  procedure DoLoadFrame(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    bmp: TPicture;
  begin
    bmp := TPicture.Create;
    try
      EnterCriticalSection(FCS);
      bmp.Bitmap.PixelFormat:=pf32bit;
      bmp.LoadFromFile(Format(PChar(AData), [AIndex]));
      LeaveCriticalSection(FCS);

      LoadFrame(@FFrames[AIndex], bmp.Bitmap);

      FFrames[AIndex].Index := AIndex;
    finally
      bmp.Free;
    end;
  end;

var
  i, j: Integer;
  fn: String;
  frc: Integer;
  sfr, efr: Integer;
  wasAutoQ: Boolean;
begin
  wasAutoQ := seMaxTiles.Value = round(seQbTiles.Value * EqualQualityTileCount(Length(FFrames) * cTileMapSize));

  ProgressRedraw;

  for i := 0 to High(FTiles) do
    Dispose(FTiles[i]);

  SetLength(FFrames, 0);

  for i := 0 to High(FKeyFrames) do
    Dispose(FKeyFrames[i]);

  SetLength(FKeyFrames, 0);
  SetLength(FTiles, 0);

  ProgressRedraw(-1, esLoad);

  if FileExists(edInput.Text) then
  begin
    DoExternalFFMpeg(edInput.Text, FInputPath, FWAVFile, seFrameCount.Value);
  end
  else
  begin
    FInputPath := edInput.Text;
    FWAVFile := edWAV.Text;
  end;

  frc := seFrameCount.Value;

  if frc <= 0 then
  begin
    if Pos('%', FInputPath) > 0 then
    begin
      i := 0;
      repeat
        fn := Format(FInputPath, [i]);
        Inc(i);
      until not FileExists(fn);

      frc := i - 1;
    end
    else
    begin
      frc := 1;
    end;

    seFrameCount.Value := frc;
    seFrameCount.Repaint;
  end;

  SetLength(FFrames, frc);
  tbFrame.Max := High(FFrames);

  for i := 0 to High(FFrames) do
  begin
    fn := Format(FInputPath, [i]);
    if not FileExists(fn) then
    begin
      SetLength(FFrames, 0);
      tbFrame.Max := 0;
      raise EFileNotFoundException.Create('File not found: ' + fn);
    end;
  end;

  WriteLn;

  ProgressRedraw(1);

  ProcThreadPool.DoParallelLocalProc(@DoLoadFrame, 0, High(FFrames), PChar(FInputPath));

  ProgressRedraw(2);

  FindKeyFrames;

  for j := 0 to High(FKeyFrames) do
  begin
    sfr := High(Integer);
    efr := Low(Integer);

    for i := 0 to High(FFrames) do
      if FFrames[i].KeyFrame = FKeyFrames[j] then
      begin
        sfr := Min(sfr, i);
        efr := Max(efr, i);
      end;

    FKeyFrames[j]^.StartFrame := sfr;
    FKeyFrames[j]^.EndFrame := efr;
    FKeyFrames[j]^.FrameCount := efr - sfr + 1;
    FKeyFrames[j]^.FramesLeft := -1;
  end;

  ProgressRedraw(3);

  LoadTiles;

  ProgressRedraw(4);

  if wasAutoQ or (seMaxTiles.Value <= 0) then
    seQbTilesEditingDone(nil);
  tbFrameChange(nil);
end;

procedure TMainForm.btnReindexClick(Sender: TObject);

  procedure DoPruneUnusedTiles(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    if FTiles[AIndex]^.Active then
    begin
      FTiles[AIndex]^.UseCount := GetTileUseCount(AIndex);
      FTiles[AIndex]^.Active := FTiles[AIndex]^.UseCount <> 0;
    end
    else
    begin
      FTiles[AIndex]^.UseCount := 0;
    end;
  end;

  procedure DoIndexFrameTiles(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    IndexFrameTiles(@FFrames[AIndex]);
  end;

begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esReindex);

  ProcThreadPool.DoParallelLocalProc(@DoPruneUnusedTiles, 0, High(FTiles));
  ProgressRedraw(1);
  ReindexTiles;
  ProgressRedraw(2);
  ProcThreadPool.DoParallelLocalProc(@DoIndexFrameTiles, 0, High(FFrames));
  ProgressRedraw(3);

  tbFrameChange(nil);
end;

procedure TMainForm.btnRunAllClick(Sender: TObject);
begin
  btnLoadClick(nil);
  btnDoKeyFrameTilingClick(nil);
  btnFrameTileClick(nil);
  btnDitherClick(nil);
  btnMakeUniqueClick(nil);
  btnFixupClick(nil);
  btnReindexClick(nil);
  btnSmoothClick(nil);
  btnReindexClick(nil);
  btnSaveClick(nil);

  ProgressRedraw;
  tbFrameChange(nil);
end;

procedure TMainForm.btnSaveClick(Sender: TObject);
var
  dataFS, soundFS: TFileStream;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(-1, esSave);

  dataFS := TFileStream.Create(IncludeTrailingPathDelimiter(edOutputDir.Text) + 'data.bin', fmCreate);
  try
    soundFS := nil;
    if FWAVFile <> '' then
      soundFS := TFileStream.Create(DoExternalPCMEnc(FWAVFile, 115), fmOpenRead or fmShareDenyWrite);

    ProgressRedraw(1);

    try
      Save(dataFS, soundFS);
    finally
      if Assigned(soundFS) then
        soundFS.Free;
    end;
  finally
    dataFS.Free;
  end;

  ProgressRedraw(2);

  tbFrameChange(nil);
end;

procedure TMainForm.btnSmoothClick(Sender: TObject);
  procedure DoSmoothing(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var i: Integer;
  begin
    for i := 1 to High(FFrames) do
      DoTemporalSmoothing(i, AIndex, seTempoSmoo.Value);
  end;
begin
  if (Length(FFrames) = 0) or (seTempoSmoo.Value < 0) then
    Exit;

  ProgressRedraw(-1, esSmooth);

  ProcThreadPool.DoParallelLocalProc(@DoSmoothing, 0, cTileMapHeight - 1);

  ProgressRedraw(1);

  tbFrameChange(nil);
end;

procedure TMainForm.cbxYilMixChange(Sender: TObject);
begin
  FY2MixedColors := StrToIntDef(cbxYilMix.Text, 16);
end;

procedure TMainForm.IdleTimerTimer(Sender: TObject);
begin
  if chkPlay.Checked then
  begin
    if tbFrame.Position >= tbFrame.Max then
    begin
      tbFrame.Position := 0;
      Exit;
    end;

    tbFrame.Position := tbFrame.Position + 1;
  end;
end;

procedure TMainForm.seQbTilesEditingDone(Sender: TObject);
var
  RawTileCount: Integer;
begin
  if Length(FFrames) * cTileMapSize = 0 then Exit;
  RawTileCount := Length(FFrames) * cTileMapSize;
  seMaxTiles.Value := min(round(seQbTiles.Value * EqualQualityTileCount(RawTileCount)), RawTileCount);
end;

procedure TMainForm.seMaxTilesEditingDone(Sender: TObject);
begin
  if Length(FFrames) = 0 then Exit;
  seQbTiles.Value := seMaxTiles.Value div Length(FFrames);
end;

procedure TMainForm.tbFrameChange(Sender: TObject);
begin
  Screen.Cursor := crDefault;
  Render(tbFrame.Position, chkDithered.Checked, chkMirrored.Checked, chkReduced.Checked,  chkGamma.Checked, IfThen(chkSprite.State = cbGrayed, -1, Ord(chkSprite.Checked)), sePage.Value);
end;

procedure TMainForm.HMirrorTile(var ATile: TTile);
var
  i, j: Integer;
  v, sv: Integer;
begin
  // hardcode horizontal mirror into the tile

  for j := 0 to cTileWidth - 1 do
    for i := 0 to cTileWidth div 2 - 1  do
    begin
      v := ATile.PalPixels[j, i];
      sv := ATile.PalPixels[j, cTileWidth - 1 - i];
      ATile.PalPixels[j, i] := sv;
      ATile.PalPixels[j, cTileWidth - 1 - i] := v;
      v := ATile.RGBPixels[j, i];
      sv := ATile.RGBPixels[j, cTileWidth - 1 - i];
      ATile.RGBPixels[j, i] := sv;
      ATile.RGBPixels[j, cTileWidth - 1 - i] := v;
    end;
end;

procedure TMainForm.VMirrorTile(var ATile: TTile);
var
  j, i: Integer;
  v, sv: Integer;
begin
  // hardcode vertical mirror into the tile

  for j := 0 to cTileWidth div 2 - 1  do
    for i := 0 to cTileWidth - 1 do
    begin
      v := ATile.PalPixels[j, i];
      sv := ATile.PalPixels[cTileWidth - 1 - j, i];
      ATile.PalPixels[j, i] := sv;
      ATile.PalPixels[cTileWidth - 1 - j, i] := v;
      v := ATile.RGBPixels[j, i];
      sv := ATile.RGBPixels[cTileWidth - 1 - j, i];
      ATile.RGBPixels[j, i] := sv;
      ATile.RGBPixels[cTileWidth - 1 - j, i] := v;
    end;
end;


function TMainForm.DeviseBestMixingPlan(var Plan: TMixingPlan; col: Integer; const List: TByteDynArray): Integer;
label
  pal_loop, inner_loop, worst;
var
  r, g, b: Integer;
  t, index, max_test_count, plan_count, y2pal_len: Integer;
  chosen_amount, chosen, least_penalty, penalty: Int64;
  so_far, sum, add: array[0..3] of Integer;
  VecInv: PCardinal;
  y2pal: PInteger;
  cachePos: Integer;
  pb: PByte;
begin
  FromRGB(col, r, g, b);

{$if defined(ASM_DBMP) and defined(CPUX86_64)}
  asm
    sub rsp, 16 * 6
    movdqu oword ptr [rsp + $00], xmm1
    movdqu oword ptr [rsp + $10], xmm2
    movdqu oword ptr [rsp + $20], xmm3
    movdqu oword ptr [rsp + $30], xmm4
    movdqu oword ptr [rsp + $40], xmm5
    movdqu oword ptr [rsp + $50], xmm6

    push rax
    push rbx
    push rcx

    mov eax, r
    mov ebx, g
    mov ecx, b

    pinsrd xmm4, eax, 0
    pinsrd xmm4, ebx, 1
    pinsrd xmm4, ecx, 2

    imul eax, cRedMul
    imul ebx, cGreenMul
    imul ecx, cBlueMul

    add eax, ebx
    add eax, ecx
    imul eax, (1 shl 22) / cLumaDiv
    shr eax, 22

    pinsrd xmm4, eax, 3

    mov rax, 1 or (1 shl 32)
    pinsrq xmm5, rax, 0
    pinsrq xmm5, rax, 1

    mov rax, (cRedMul * cRGBw / 128) or ((cGreenMul * cRGBw / 128) shl 32)
    pinsrq xmm6, rax, 0
    mov rax, (cBlueMul * cRGBw / 128) or ((cLumaDiv * 32 / 128) shl 32)
    pinsrq xmm6, rax, 1

    pop rcx
    pop rbx
    pop rax
  end;
{$endif}

  VecInv := @gVecInv[0];
  plan_count := 0;
  so_far[0] := 0; so_far[1] := 0; so_far[2] := 0; so_far[3] := 0;

  while plan_count < Plan.Y2MixedColors do
  begin
    max_test_count := IfThen(plan_count = 0, 1, plan_count);

{$if defined(ASM_DBMP) and defined(CPUX86_64)}
    y2pal_len := Length(Plan.Y2Palette);
    y2pal := @Plan.Y2Palette[0][0];

    asm
      push rax
      push rbx
      push rcx
      push rdx
      push rsi
      push rdi
      push r8
      push r9
      push r10

      xor r9, r9
      xor r10, r10
      inc r10

      mov rbx, (1 shl 63) - 1

      mov rdi, y2pal
      mov r8d, dword ptr [y2pal_len]
      shl r8d, 4
      add r8, rdi

      pal_loop:

        movdqu xmm1, oword ptr [so_far]
        movdqu xmm2, oword ptr [rdi]

        mov ecx, plan_count
        inc rcx
        mov edx, max_test_count
        shl rcx, 4
        shl rdx, 4
        add rcx, VecInv
        add rdx, rcx

        inner_loop:
          paddd xmm1, xmm2
          paddd xmm2, xmm5

          movdqu xmm3, oword ptr [rcx]

          pmulld xmm3, xmm1
          psrld xmm3, cVecInvWidth

          psubd xmm3, xmm4
          pmulld xmm3, xmm3
          pmulld xmm3, xmm6

          phaddd xmm3, xmm3
          phaddd xmm3, xmm3
          pextrd eax, xmm3, 0

          cmp rax, rbx
          jae worst

            mov rbx, rax
            mov r9, rdi
            mov r10, rcx

          worst:

        add rcx, 16
        cmp rcx, rdx
        jne inner_loop

      add rdi, 16
      cmp rdi, r8
      jne pal_loop

      sub r9, y2pal
      shr r9, 4
      mov chosen, r9

      sub r10, VecInv
      shr r10, 4
      sub r10d, plan_count
      mov chosen_amount, r10

      pop r10
      pop r9
      pop r8
      pop rdi
      pop rsi
      pop rdx
      pop rcx
      pop rbx
      pop rax
    end ['rax', 'rbx', 'rcx', 'rdx', 'rsi', 'rdi', 'r8', 'r9', 'r10'];
{$else}
    chosen_amount := 1;
    chosen := 0;

    least_penalty := High(Int64);

    for index := 0 to High(Plan.Y2Palette) do
    begin
      sum[0] := so_far[0]; sum[1] := so_far[1]; sum[2] := so_far[2]; sum[3] := so_far[3];
      add[0] := Plan.Y2Palette[index][0]; add[1] := Plan.Y2Palette[index][1]; add[2] := Plan.Y2Palette[index][2]; add[3] := Plan.Y2Palette[index][3];

      for t := plan_count + 1 to plan_count + max_test_count do
      begin
        sum[0] += add[0];
        sum[1] += add[1];
        sum[2] += add[2];

        Inc(add[0]);
        Inc(add[1]);
        Inc(add[2]);

        penalty := ColorCompare(r, g, b, sum[0] div t, sum[1] div t, sum[2] div t);

        if penalty < least_penalty then
        begin
          least_penalty := penalty;
          chosen := index;
          chosen_amount := t - plan_count;
        end;
      end;
    end;
{$endif}

    chosen_amount := Min(chosen_amount, Length(List) - plan_count);
    FillByte(List[plan_count], chosen_amount, chosen);
    Inc(plan_count, chosen_amount);

    so_far[0] += Plan.Y2Palette[chosen][0] * chosen_amount;
    so_far[1] += Plan.Y2Palette[chosen][1] * chosen_amount;
    so_far[2] += Plan.Y2Palette[chosen][2] * chosen_amount;
    so_far[3] += Plan.Y2Palette[chosen][3] * chosen_amount;
  end;

  QuickSort(List[0], 0, plan_count - 1, SizeOf(Byte), @PlanCompareLuma, @Plan.LumaPal[0]);

  Result := plan_count;

{$if defined(ASM_DBMP) and defined(CPUX86_64)}
  asm
    movdqu xmm1, oword ptr [rsp + $00]
    movdqu xmm2, oword ptr [rsp + $10]
    movdqu xmm3, oword ptr [rsp + $20]
    movdqu xmm4, oword ptr [rsp + $30]
    movdqu xmm5, oword ptr [rsp + $40]
    movdqu xmm6, oword ptr [rsp + $50]
    add rsp, 16 * 6
  end;
{$endif}
end;

function TMainForm.CompareColor(r1, g1, b1, r2, g2, b2: Int64): Int64;
var
  luma1, luma2, lumadiff, diffR, diffG, diffB: Int64;
begin
  luma1 := r1 * cRedMul + g1 * cGreenMul + b1 * cBlueMul;
  luma2 := r2 * cRedMul + g2 * cGreenMul + b2 * cBlueMul;
  lumadiff := (luma1 - luma2) div cLumaDiv;
  diffR := r1 - r2;
  diffG := g1 - g2;
  diffB := b1 - b2;
  Result := diffR * diffR * cRGBw div 32;
  Result += diffG * diffG * cRGBw div 32;
  Result += diffB * diffB * cRGBw div 32;
  Result += lumadiff * lumadiff;
end;

procedure TMainForm.PreparePlan(var Plan: TMixingPlan; MixedColors: Integer; const pal: array of Integer);
var
  i, col, r, g, b: Integer;
begin
  FillChar(Plan, SizeOf(Plan), 0);

  Plan.Y2MixedColors := MixedColors;
  SetLength(Plan.LumaPal, Length(pal));
  SetLength(Plan.Y2Palette, Length(pal));

  for i := 0 to High(pal) do
  begin
    col := pal[i];
    r := col and $ff;
    g := (col shr 8) and $ff;
    b := (col shr 16) and $ff;

    Plan.LumaPal[i] := r*cRedMul + g*cGreenMul + b*cBlueMul;

    Plan.Y2Palette[i][0] := r;
    Plan.Y2Palette[i][1] := g;
    Plan.Y2Palette[i][2] := b;
    Plan.Y2Palette[i][3] := Plan.LumaPal[i] div cLumaDiv;
  end
end;

procedure TMainForm.TerminatePlan(var Plan: TMixingPlan);
begin
  SetLength(Plan.LumaPal, 0);
  SetLength(Plan.Y2Palette, 0);
end;

procedure TMainForm.DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: TByteDynArray);
var
  index, chosen, c: Integer;
  src : array[0..2] of Byte;
  s, t, e: array[0..2] of Int64;
  least_penalty, penalty: Int64;
begin
  FromRGB(col, src[0], src[1], src[2]);

  s[0] := src[0];
  s[1] := src[1];
  s[2] := src[2];

  e[0] := 0;
  e[1] := 0;
  e[2] := 0;

  for c := 0 to cDitheringLen - 1 do
  begin
    t[0] := s[0] + (e[0] * 9) div 100;
    t[1] := s[1] + (e[1] * 9) div 100;
    t[2] := s[2] + (e[2] * 9) div 100;

    //t[0] := EnsureRange(t[0], 0, 255);
    //t[1] := EnsureRange(t[1], 0, 255);
    //t[2] := EnsureRange(t[2], 0, 255);

    least_penalty := High(Int64);
    chosen := c and (length(Plan.Y2Palette) - 1);
    for index := 0 to length(Plan.Y2Palette) - 1 do
    begin
      penalty := CompareColor(t[0], t[1], t[2], Plan.Y2Palette[index][0], Plan.Y2Palette[index][1], Plan.Y2Palette[index][2]);
      if penalty < least_penalty then
      begin
        least_penalty := penalty;
        chosen := index;
      end;
    end;

    List[c] := chosen;

    e[0] += s[0];
    e[1] += s[1];
    e[2] += s[2];

    e[0] -= Plan.Y2Palette[chosen][0];
    e[1] -= Plan.Y2Palette[chosen][1];
    e[2] -= Plan.Y2Palette[chosen][2];
  end;

  QuickSort(List[0], 0, cDitheringLen - 1, SizeOf(Byte), @PlanCompareLuma, @Plan.LumaPal[0]);
end;

procedure TMainForm.DitherTile(var ATile: TTile; var Plan: TMixingPlan);
var
  x, y: Integer;
  count, map_value: Integer;
  list: TByteDynArray;
begin
  if FUseThomasKnoll then
  begin
    SetLength(list, cDitheringLen);

   for y := 0 to (cTileWidth - 1) do
     for x := 0 to (cTileWidth - 1) do
     begin
       map_value := cDitheringMap[(y shl 3) + x];
       DeviseBestMixingPlanThomasKnoll(Plan, ATile.RGBPixels[y, x], list);
       ATile.PalPixels[y, x] := list[map_value];
     end;
  end
  else
  begin
    SetLength(list, cDitheringListLen);

    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        map_value := cDitheringMap[(y shl 3) + x];
        count := DeviseBestMixingPlan(Plan, ATile.RGBPixels[y, x], list);
        map_value := (map_value * count) shr 6;
        ATile.PalPixels[y, x] := list[map_value];
      end;
  end;
end;

function TMainForm.GetTileZoneSum(const ATile: TTile; AOnPal: Boolean; x, y, w, h: Integer): Integer;
var
  i, j: Integer;
  r, g, b: Byte;
begin
  Result := 0;

  if AOnPal then
  begin
    for j := y to y + h - 1 do
      for i := x to x + w - 1 do
        Result += ATile.PalPixels[j, i];
  end
  else
  begin
    for j := y to y + h - 1 do
      for i := x to x + w - 1 do
      begin
        FromRGB(ATile.RGBPixels[j, i], r, g, b);
        Result += ToLuma(r, g, b);
      end;
  end;
end;

function CompareCMULHS(const Item1,Item2:PCountIndex):Integer;
begin
  Result := CompareValue(Item2^.Luma, Item1^.Luma);
  if Result = 0 then
    Result := CompareValue(Item2^.Sat, Item1^.Sat);
  if Result = 0 then
    Result := CompareValue(Item2^.Hue, Item1^.Hue);
end;

function ComparePaletteLuma(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

function CompareCMUCnt(const Item1,Item2:PCountIndex):Integer;
begin
  Result := CompareValue(Item2^.Count, Item1^.Count);
  if Result = 0 then
    Result := CompareValue(Item1^.Luma, Item2^.Luma);
end;

procedure TMainForm.Pallettize(AKeyFrame: PKeyFrame);
var
  sx, sy, i, dsIdx: Integer;

  Dataset: TFloatDynArray2;
  Clusters: TIntegerDynArray;

  Yakmo: PYakmo;
begin
  SetLength(Dataset, AKeyFrame^.FrameCount * cTileMapSize, cTileDCTSize);
  SetLength(Clusters, Length(Dataset));

  dsIdx := 0;
  for i := AKeyFrame^.StartFrame to AKeyFrame^.EndFrame do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
        ComputeTilePsyVisFeatures(FFrames[i].Tiles[sy * cTileMapWidth + sx], pvsWeightedDCT, False, True, FFrames[i].TileMap[sy, sx].HMirror, FFrames[i].TileMap[sy, sx].VMirror, cColorCpns, nil, @Dataset[dsIdx, 0]);
        Inc(dsIdx);
      end;
  assert(dsIdx = Length(Dataset));

  if dsIdx > 1 then
  begin
   yakmo_set_num_threads(1);
   Yakmo := yakmo_create(2, 1, MaxInt, 1, 0, 0, 0);
   yakmo_load_train_data(Yakmo, dsIdx, cTileDCTSize, PPFloat(@Dataset[0]));
   SetLength(Dataset, 0); // free up some memmory
   yakmo_train_on_data(Yakmo, @Clusters[0]);
   yakmo_destroy(Yakmo);
  end
  else
  begin
    FillDWord(Clusters[0], Length(Clusters), 0);
  end;

  dsIdx := 0;
  for i := AKeyFrame^.StartFrame to AKeyFrame^.EndFrame do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
        FFrames[i].TileMap[sy, sx].SpritePal := Odd(Clusters[dsIdx]);
        FFrames[i].TileMap[sy, sx].FrameTileSpritePal := Odd(Clusters[dsIdx]);
        Inc(dsIdx);
      end;
  assert(dsIdx = Length(Clusters));

  WriteLn('KF: ', AKeyFrame^.StartFrame:6, ' Yakmo end');
end;

procedure TMainForm.QuantizePalette(AKeyFrame: PKeyFrame; ASpritePal: Boolean);
var
  CMPal: TCountIndexList;

  procedure DoYakmo;
  var
    Dataset, Centroids: TFloatDynArray2;
    Clusters: TIntegerDynArray;
    iMap, iPal, iFrame, sy, sx, ty, tx, dsIdx: Integer;
    rr, gg, bb: Byte;
    l1, a1, b1, l2, a2, b2: TFloat;
    best, v: TFloat;
    GTile: PTile;
    CMItem: PCountIndex;
    CMPicked: TBooleanDynArray;
    Yakmo: PYakmo;
  begin
    SetLength(Dataset, AKeyFrame^.FrameCount * cTileMapSize * Sqr(cTileWidth), cColorCpns);

    dsIdx := 0;
    for iFrame := AKeyFrame^.StartFrame to AKeyFrame^.EndFrame do
      for sy := 0 to cTileMapHeight - 1 do
        for sx := 0 to cTileMapWidth - 1 do
        begin
          GTile := @FFrames[iFrame].Tiles[sy * cTileMapWidth + sx];

          if GTile^.Active and (FFrames[iFrame].TileMap[sy, sx].SpritePal = ASpritePal) then
          begin
            for ty := 0 to cTileWidth - 1 do
              for tx := 0 to cTileWidth - 1 do
              begin
                FromRGB(GTile^.RGBPixels[ty, tx], rr, gg, bb);
                Dataset[dsIdx, 0] := rr;
                Dataset[dsIdx, 1] := gg;
                Dataset[dsIdx, 2] := bb;
                Inc(dsIdx);
              end;

            Inc(AKeyFrame^.PaletteUseCount[ASpritePal].UseCount);
          end;
        end;

    SetLength(Dataset, dsIdx);
    SetLength(Clusters, dsIdx);
    SetLength(Centroids, cTilePaletteSize, cColorCpns);

    yakmo_set_num_threads(1);
    Yakmo := yakmo_create(cTilePaletteSize, 1, MaxInt, 1, 0, 0, 0);
    yakmo_load_train_data(Yakmo, dsIdx, cColorCpns, PPFloat(@Dataset[0]));
    SetLength(Dataset, 0); // free up some memmory
    yakmo_train_on_data(Yakmo, @Clusters[0]);
    yakmo_get_centroids(Yakmo, PPFloat(@Centroids[0]));
    yakmo_destroy(Yakmo);

    SetLength(CMPicked, cTotalColors);

    for iPal := 0 to cTilePaletteSize - 1 do
    begin
      New(CMItem);
      CMItem^.Count := 0;
      CMItem^.Index := 0;

      CMItem^.R := 0;
      if not IsNan(Centroids[iPal, 0]) then
        CMItem^.R := EnsureRange(Round(Centroids[iPal, 0]), 0, High(Byte));

      CMItem^.G := 0;
      if not IsNan(Centroids[iPal, 1]) then
        CMItem^.G := EnsureRange(Round(Centroids[iPal, 1]), 0, High(Byte));

      CMItem^.B := 0;
      if not IsNan(Centroids[iPal, 2]) then
        CMItem^.B := EnsureRange(Round(Centroids[iPal, 2]), 0, High(Byte));

      RGBToLAB(CMItem^.R, CMItem^.G, CMItem^.B, l1, a1, b1);

      best := Infinity;
      for iMap := 0 to High(FColorMap) do
        if not CMPicked[iMap] then
        begin
          FromRGB(FColorMap[iMap], rr, gg, bb);
          RGBToLAB(rr, gg, bb, l2, a2, b2);

          v := Sqr(l1 - l2) + Sqr(a1 - a2) + Sqr(b1 - b2);

          if v <= best then
          begin
            best := v;
            CMItem^.Index := iMap;
          end;
        end;

      Assert(not CMPicked[CMItem^.Index]);
      CMPicked[CMItem^.Index] := True;

      CMItem^.Luma := FColorMapLuma[CMItem^.Index];
      FromRGB(FColorMap[CMItem^.Index], CMItem^.R, CMItem^.G, CMItem^.B);
      RGBToHSV(ToRGB(CMItem^.R, CMItem^.G, CMItem^.B), CMItem^.Hue, CMItem^.Sat, CMItem^.Val);
      CMPal.Add(CMItem);
    end;
  end;

var
  i: Integer;
begin
  CMPal := TCountIndexList.Create;
  try
    AKeyFrame^.PaletteUseCount[ASpritePal].UseCount := 0;

    DoYakmo;

    // split most used colors into tile palettes

    CMPal.Sort(@CompareCMULHS);

    SetLength(AKeyFrame^.PaletteIndexes[ASpritePal], cTilePaletteSize);
    SetLength(AKeyFrame^.PaletteRGB[ASpritePal], cTilePaletteSize);
    for i := 0 to cTilePaletteSize - 1 do
    begin
      AKeyFrame^.PaletteIndexes[ASpritePal, i] := CMPal[i]^.Index;
      AKeyFrame^.PaletteRGB[ASpritePal, i] := FColorMap[CMPal[i]^.Index];
    end;

    for i := 0 to CMPal.Count - 1 do
      Dispose(CMPal[i]);
  finally
    CMPal.Free;
  end;

  WriteLn('KF: ', AKeyFrame^.StartFrame:6, ', SpritePal: ', ASpritePal);
end;

procedure TMainForm.FinishQuantizePalette(AKeyFrame: PKeyFrame);
var
  i, sy, sx: Integer;
  PalIdxLUT: array[Boolean] of Boolean;
  SpritePal: Boolean;
begin
  // sort entire palettes by use count
  for SpritePal := False to True do
  begin
    AKeyFrame^.PaletteUseCount[SpritePal].UseCount := 0;
    for i := 0 to cTilePaletteSize - 1 do
      AKeyFrame^.PaletteUseCount[SpritePal].UseCount += FColorMapLuma[AKeyFrame^.PaletteIndexes[SpritePal, i]];

    AKeyFrame^.PaletteUseCount[SpritePal].PaletteIndexes := AKeyFrame^.PaletteIndexes[SpritePal];
    AKeyFrame^.PaletteUseCount[SpritePal].PaletteRGB := AKeyFrame^.PaletteRGB[SpritePal];
    AKeyFrame^.PaletteUseCount[SpritePal].SpritePal := SpritePal;
  end;
  QuickSort(AKeyFrame^.PaletteUseCount[False], 0, 1, SizeOf(AKeyFrame^.PaletteUseCount[False]), @ComparePaletteLuma, AKeyFrame);
  for SpritePal := False to True do
  begin
    AKeyFrame^.PaletteIndexes[SpritePal] := AKeyFrame^.PaletteUseCount[SpritePal].PaletteIndexes;
    AKeyFrame^.PaletteRGB[SpritePal] := AKeyFrame^.PaletteUseCount[SpritePal].PaletteRGB;
    PalIdxLUT[AKeyFrame^.PaletteUseCount[SpritePal].SpritePal] := SpritePal;
  end;

  for i := AKeyFrame^.StartFrame to AKeyFrame^.EndFrame do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
        FFrames[i].TileMap[sy, sx].SpritePal := PalIdxLUT[FFrames[i].TileMap[sy, sx].SpritePal];
        FFrames[i].TileMap[sy, sx].FrameTileSpritePal := PalIdxLUT[FFrames[i].TileMap[sy, sx].FrameTileSpritePal];
      end;
end;

procedure TMainForm.DitherTiles(AKF: PKeyFrame);
var
  iFrame, sx, sy: Integer;
  pal: Boolean;
  MixingPlans: array[Boolean] of TMixingPlan;
  TMI: PTileMapItem;
  TmpTile: TTile;
begin
  for pal := False to True do
    PreparePlan(MixingPlans[pal], FY2MixedColors, AKF^.PaletteRGB[pal]);

  for iFrame := AKF^.StartFrame to AKF^.EndFrame do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
        TMI := @FFrames[iFrame].TileMap[sy, sx];

        CopyTile(FTiles[TMI^.TileIdx]^, TmpTile);
        DitherTile(TmpTile, MixingPlans[TMI^.SpritePal]);

        Move(TmpTile.PalPixels, FFrames[iFrame].Tiles[sy * cTileMapWidth + sx].PalPixels, SizeOf(TPalPixels));
      end;

  for pal := False to True do
    TerminatePlan(MixingPlans[pal]);
end;

procedure TMainForm.LoadTiles;
var
  i,j,x,y: Integer;
  tileCnt: Integer;
begin
  // free memory from a prev run
  for i := 0 to High(FTiles) do
    Dispose(FTiles[i]);

  tileCnt := Length(FFrames) * cTileMapSize;

  SetLength(FTiles, tileCnt);

  // allocate tiles
  for i := 0 to High(FTiles) do
  begin
    FTiles[i] := New(PTile);
    FillChar(FTiles[i]^, SizeOf(TTile), 0);
    FTiles[i]^.Active := True;
  end;

  // copy frame tiles to global tiles, point tilemap on proper global tiles
  for i := 0 to High(FFrames) do
  begin
    tileCnt := i * cTileMapSize;

    for j := 0 to cTileMapSize - 1 do
      CopyTile(FFrames[i].Tiles[j], FTiles[tileCnt + j]^);

    for y := 0 to (cTileMapHeight - 1) do
      for x := 0 to (cTileMapWidth - 1) do
        FFrames[i].TileMap[y,x].TileIdx := tileCnt + y * cTileMapWidth + x;
  end;
end;

procedure TMainForm.FindKeyFrames;
var
  Correlations: TFloatDynArray;

  procedure DoCorrel(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    Correlations[AIndex] := ComputeInterFrameCorrelation(FFrames[AIndex - 1], FFrames[AIndex]);
  end;

const
  CShotTransCorrelLoThres = 0.4; // interframe pearson correlation low limit
var
  i, j: Integer;
  correl: TFloat;
  kfIdx: Integer;
  isKf: Boolean;
  sfr, efr: Integer;
begin
  // compute interframe correlations

  SetLength(Correlations, Length(FFrames));
  Correlations[0] := 0.0;
  ProcThreadPool.DoParallelLocalProc(@DoCorrel, 1, High(FFrames));

  // find keyframes

  SetLength(FKeyFrames, Length(FFrames));
  kfIdx := 0;
  for i := 0 to High(FFrames) do
  begin
    correl := Correlations[i];

    isKf := correl < CShotTransCorrelLoThres;

    if isKf then
    begin
      New(FKeyFrames[kfIdx]);
      InitializeCriticalSection(FKeyFrames[kfIdx]^.CS);
      Inc(kfIdx);

      WriteLn('KF: ', kfIdx, #9'Frame: ', i, #9'Correlation: ', correl:9:6);
    end;

    FFrames[i].KeyFrame := FKeyFrames[kfIdx - 1];
  end;

  SetLength(FKeyFrames, kfIdx);

  for j := 0 to High(FKeyFrames) do
  begin
    sfr := High(Integer);
    efr := Low(Integer);

    for i := 0 to High(FFrames) do
      if FFrames[i].KeyFrame = FKeyFrames[j] then
      begin
        sfr := Min(sfr, i);
        efr := Max(efr, i);
      end;

    FKeyFrames[j]^.StartFrame := sfr;
    FKeyFrames[j]^.EndFrame := efr;
    FKeyFrames[j]^.FrameCount := efr - sfr + 1;
  end;
end;

generic function DCTInner<T>(pCpn, pLut: T): Double;
begin
  Result := 0;

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

procedure TMainForm.ConvertToCpnPixels(const ATile: TTile; FromPal, UseLAB, HMirror, VMirror: Boolean; const APalette: TIntegerDynArray; out ACpnPixel: TCpnPixels);

  procedure ToCpn(col, x, y: Integer);
  var
    r, g, b: Byte;
    yy, uu, vv: TFloat;
  begin
    FromRGB(col, r, g, b);

    if UseLAB then
    begin
      RGBToLAB(r, g, b, yy, uu, vv)
    end
    else
    begin
      RGBToYUV(r, g, b, yy, uu, vv);
    end;

    ACpnPixel[0, y, x] := yy;
    ACpnPixel[1, y, x] := uu;
    ACpnPixel[2, y, x] := vv;
  end;

var
  x, y, xx, yy: Integer;
begin
  if FromPal then
  begin
    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        xx := x;
        yy := y;
        if HMirror then xx := cTileWidth - 1 - x;
        if VMirror then yy := cTileWidth - 1 - y;

        ToCpn(APalette[ATile.PalPixels[yy,xx]], x, y);
      end;
  end
  else
  begin
    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        xx := x;
        yy := y;
        if HMirror then xx := cTileWidth - 1 - x;
        if VMirror then yy := cTileWidth - 1 - y;

        ToCpn(ATile.RGBPixels[yy,xx], x, y);
      end;
  end;
end;

procedure TMainForm.ComputeCpnPixelsPsyVisFeatures(const ACpnPixel: TCpnPixels; Mode: TPsyVisMode; ColorCpns: Integer; ADCT: PDCTScalar);
var
  u, v, cpn: Integer;
  z: Double;
  pLut: PFloat;
  pDCT: PSmallInt;
  pSnake: PByte;
begin
  Assert(not (Mode in [pvsWavelets]), 'Wavelets on SmallInt vector unimplemented!');

  for cpn := 0 to ColorCpns - 1 do
  begin
    pDCT := @ADCT[cpn * sqr(cTileWidth)];
    pLut := @gDCTLut[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
    pSnake := @cDCTSnake[0];
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
  		  z := specialize DCTInner<PFloat>(@ACpnPixel[cpn, 0, 0], pLut);

        if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
           z *= cDCTWeights[cpn, v, u];

        pDCT[pSnake^] := Round(z);
        Inc(pLut, Sqr(cTileWidth));
        Inc(pSnake);
      end;
  end;
end;

procedure TMainForm.ComputeTilePsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; FromPal, UseLAB, HMirror,
 VMirror: Boolean; ColorCpns: Integer; const APalette: TIntegerDynArray; ADCT: PFloat);
var
  i, u, v, cpn: Integer;
  z: Double;
  CpnPixels: TCpnPixels;
  pDCT, pLut: PDouble;
  LocalDCT: array[0..cTileDCTSize - 1] of Double;
begin
  ConvertToCpnPixels(ATile, FromPal, UseLAB, HMirror, VMirror, APalette, CpnPixels);

  if Mode = pvsWavelets then
  begin
   for cpn := 0 to ColorCpns - 1 do
   begin
     pDCT := @LocalDCT[cpn * sqr(cTileWidth)];
     specialize WaveletGS<Double, PDouble>(@CpnPixels[cpn, 0, 0], pDCT, cTileWidth, cTileWidth, 2);
   end;
  end
  else
  begin
    for cpn := 0 to ColorCpns - 1 do
    begin
      pDCT := @LocalDCT[cpn * sqr(cTileWidth)];
      pLut := @gDCTLut[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
      for v := 0 to cTileWidth - 1 do
        for u := 0 to cTileWidth - 1 do
        begin
          z := specialize DCTInner<PDouble>(@CpnPixels[cpn, 0, 0], pLut);

          if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
             z *= cDCTWeights[cpn, v, u];

          pDCT^ := z;
          Inc(pDCT);
          Inc(pLut, Sqr(cTileWidth));
        end;
    end;
  end;

  for cpn := 0 to ColorCpns - 1 do
    for i := 0 to sqr(cTileWidth) - 1 do
      ADCT[cDCTSnake[i] + cpn * sqr(cTileWidth)] := LocalDCT[i + cpn * sqr(cTileWidth)];
end;

procedure TMainForm.ComputeInvTilePsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; UseLAB: Boolean; ColorCpns: Integer;
 var ATile: TTile);
var
  i, u, v, x, y, cpn: Integer;
  CpnPixels: TCpnPixels;
  pCpn, pLut, pDCT: PDouble;
  LocalDCT: array[0..cTileDCTSize - 1] of Double;
  d: Double;

  function FromCpn(x, y: Integer): Integer; inline;
  var
    yy, uu, vv: TFloat;
  begin
    yy := CpnPixels[0, y, x];
    uu := CpnPixels[1, y, x];
    vv := CpnPixels[2, y, x];

    if UseLAB then
      Result := LABToRGB(yy, uu, vv)
    else
      Result := YUVToRGB(yy, uu, vv);
    end;

begin
  Assert(not (Mode in [pvsSpeDCT, pvsWeightedSpeDCT]), 'Special DCT is non-inversible');

  pDCT := @LocalDCT[0];
  for cpn := 0 to ColorCpns - 1 do
  begin
    i := 0;
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
        d := DCT[cDCTSnake[i] + cpn * sqr(cTileWidth)];
        if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
          pDCT^ := d / cDCTWeights[cpn, v, u]
        else
          pDCT^ := d;
        Inc(pDCT);
        Inc(i);
      end;
  end;

  if Mode = pvsWavelets then
  begin
    for cpn := 0 to ColorCpns - 1 do
    begin
      pCpn := @CpnPixels[cpn, 0, 0];
      specialize DeWaveletGS<Double, PDouble>(@LocalDCT[cpn * sqr(cTileWidth)], pCpn, cTileWidth, cTileWidth, 2);
    end;
  end
  else
  begin
    for cpn := 0 to ColorCpns - 1 do
    begin
      pCpn := @CpnPixels[cpn, 0, 0];
      pLut := @gInvDCTLut[0];

      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
        begin
          pCpn^ := specialize DCTInner<PDouble>(@LocalDCT[cpn * sqr(cTileWidth)], pLut);
          Inc(pCpn);
          Inc(pLut, Sqr(cTileWidth));
        end;
    end;
  end;

  for y := 0 to (cTileWidth - 1) do
    for x := 0 to (cTileWidth - 1) do
      ATile.RGBPixels[y, x] := FromCpn(x, y);
end;


procedure TMainForm.LoadFrame(AFrame: PFrame; ABitmap: TCustomBitmap);
var
  i, j, col, ti, tx, ty: Integer;
  pcol: PInteger;
  pfs: PByte;
begin
  FillChar(AFrame^, SizeOf(TFrame), 0);

  for j := 0 to (cTileMapHeight - 1) do
    for i := 0 to (cTileMapWidth - 1) do
    begin
      AFrame^.TileMap[j, i].TileIdx := cTileMapWidth * j + i;
      AFrame^.TileMap[j, i].HMirror := False;
      AFrame^.TileMap[j, i].VMirror := False;
      AFrame^.TileMap[j, i].SpritePal := False;
      AFrame^.TileMap[j, i].FrameTileSpritePal := False;
      AFrame^.TileMap[j, i].Smoothed := False;
      AFrame^.TileMap[j, i].TmpIndex := -1;
    end;

  ABitmap.BeginUpdate;
  try
    SetLength(AFrame^.FSPixels, CScreenHeight * CScreenWidth * 3);

    pfs := @AFrame^.FSPixels[0];
    for j := 0 to (CScreenHeight - 1) do
    begin
      pcol := ABitmap.ScanLine[j];
      for i := 0 to (CScreenWidth - 1) do
        begin
          col := pcol^;
          Inc(pcol);

          ti := CTileMapWidth * (j shr 3) + (i shr 3);
          tx := i and (cTileWidth - 1);
          ty := j and (cTileWidth - 1);

          col := SwapRB(col);
          AFrame^.Tiles[ti].RGBPixels[ty, tx] := col;

          FromRGB(col, pfs[0], pfs[1], pfs[2]);
          Inc(pfs, 3);
        end;
    end;

    for i := 0 to (cTileMapSize - 1) do
    begin
      for ty := 0 to (cTileWidth - 1) do
        for tx := 0 to (cTileWidth - 1) do
          AFrame^.Tiles[i].PalPixels[ty, tx] := 0;

      AFrame^.Tiles[i].Active := True;
      AFrame^.Tiles[i].UseCount := 1;
      AFrame^.Tiles[i].TmpIndex := -1;
      AFrame^.Tiles[i].MergeIndex := -1;
    end;

  finally
    ABitmap.EndUpdate;
  end;
end;

procedure TMainForm.ClearAll;
var
  i: Integer;
begin
  for i := 0 to High(FTiles) do
  begin
    SetLength(FTiles[i]^.PaletteIndexes, 0);
    SetLength(FTiles[i]^.PaletteRGB, 0);
    Dispose(FTiles[i]);
  end;

  SetLength(FTiles, 0);

  for i := 0 to High(FFrames) do
  begin
    SetLength(FFrames[i].TilesIndexes, 0);
    SetLength(FFrames[i].FSPixels, 0);
  end;

  SetLength(FFrames, 0);

  for i := 0 to High(FKeyFrames) do
  begin
    DeleteCriticalSection(FKeyFrames[i]^.CS);
    Dispose(FKeyFrames[i]);
  end;

  SetLength(FKeyFrames, 0);
end;

procedure TMainForm.Render(AFrameIndex: Integer; dithered, mirrored, reduced, gamma: Boolean; palIdx: Integer;
  ATilePage: Integer);

  procedure DrawTile(bitmap: TBitmap; sx, sy: Integer; tilePtr: PTile; pal: TIntegerDynArray; hmir, vmir: Boolean);
  var
    r, g, b, tx, ty, txm, tym: Integer;
    psl: PInteger;
  begin
    for ty := 0 to cTileWidth - 1 do
    begin
      psl := bitmap.ScanLine[ty + sy * cTileWidth];
      Inc(psl, sx * cTileWidth);

      tym := ty;
      if vmir and mirrored then tym := cTileWidth - 1 - tym;

      for tx := 0 to cTileWidth - 1 do
      begin
        txm := tx;
        if hmir and mirrored then txm := cTileWidth - 1 - txm;

        if dithered and Assigned(pal) then
          FromRGB(pal[tilePtr^.PalPixels[tym, txm]], r, g, b)
        else
          FromRGB(tilePtr^.RGBPixels[tym, txm], r, g, b);

        if gamma then
        begin
          r := round(GammaCorrect(0, r) * 255.0);
          g := round(GammaCorrect(0, g) * 255.0);
          b := round(GammaCorrect(0, b) * 255.0);
        end;

        if not tilePtr^.Active then
        begin
          r := 255;
          g := 0;
          b := 255;
        end;

        psl^ := SwapRB(ToRGB(r, g, b));
        Inc(psl);
      end;
    end;
  end;

var
  i, j, sx, sy, ti, ftc, dftc: Integer;
  p: PInteger;
  tilePtr: PTile;
  TMItem: TTileMapItem;
  Frame: PFrame;
  pal: TIntegerDynArray;
  oriCorr, chgCorr: TIntegerDynArray;
begin
  if Length(FFrames) <= 0 then
    Exit;

  mirrored := mirrored and reduced;

  AFrameIndex := EnsureRange(AFrameIndex, 0, high(FFrames));

  Frame := @FFrames[AFrameIndex];

  if not Assigned(Frame) or not Assigned(Frame^.KeyFrame) then
    Exit;

  try
    ftc := GetFrameTileCount(Frame, False, False);
    dftc := GetFrameTileCount(Frame, True, False);
    lblTileCount.Caption := 'Global: ' + IntToStr(GetGlobalTileCount) + ' / Frame #' + IntToStr(AFrameIndex) + IfThen(Frame^.KeyFrame^.StartFrame = AFrameIndex, ' [KF]', '     ') + ' : ' + IntToStr(ftc) + ' (Cml=' + IntToStr(dftc) + ')';
    if dftc > cMaxTilesPerFrame then
      lblTileCount.Font.Color := clMaroon
    else
      lblTileCount.Font.Color := clGreen;

    imgTiles.Picture.Bitmap.BeginUpdate;
    try
      imgTiles.Picture.Bitmap.Canvas.Brush.Color := clAqua;
      imgTiles.Picture.Bitmap.Canvas.Brush.Style := bsSolid;
      imgTiles.Picture.Bitmap.Canvas.Clear;

      for sy := 0 to CTileMapHeight * 2 - 1 do
        for sx := 0 to CTileMapWidth - 1 do
        begin
          ti := CTileMapWidth * sy + sx + cTileMapSize * 2 * ATilePage;

          if InRange(ti, 0, High(FTiles)) then
          begin
            tilePtr := FTiles[ti];
            pal := Frame^.KeyFrame^.PaletteRGB[Max(0, palIdx) <> 0];

            DrawTile(imgTiles.Picture.Bitmap, sx, sy, tilePtr, pal, False, False);
          end;
        end;
    finally
      imgTiles.Picture.Bitmap.EndUpdate;
    end;

    imgSource.Picture.Bitmap.BeginUpdate;
    try
      for sy := 0 to CTileMapHeight - 1 do
        for sx := 0 to CTileMapWidth - 1 do
        begin
          tilePtr :=  @Frame^.Tiles[sy * CTileMapWidth + sx];

          TMItem := Frame^.TileMap[sy, sx];

          DrawTile(imgSource.Picture.Bitmap, sx, sy, tilePtr, nil, False, False);
        end;
    finally
      imgSource.Picture.Bitmap.EndUpdate;
    end;

    imgDest.Picture.Bitmap.BeginUpdate;
    try
      imgDest.Picture.Bitmap.Canvas.Brush.Color := clFuchsia;
      imgDest.Picture.Bitmap.Canvas.Brush.Style := bsDiagCross;
      imgDest.Picture.Bitmap.Canvas.Clear;

      for sy := 0 to CTileMapHeight - 1 do
        for sx := 0 to CTileMapWidth - 1 do
        begin
          TMItem := Frame^.TileMap[sy, sx];
          ti := TMItem.TileIdx;

          if InRange(ti, 0, High(FTiles)) then
          begin
            tilePtr :=  @Frame^.Tiles[sy * CTileMapWidth + sx];
            pal := tilePtr^.PaletteRGB;

            if reduced then
            begin
              tilePtr := FTiles[ti];
              if palIdx < 0 then
              begin
                pal := Frame^.KeyFrame^.PaletteRGB[TMItem.SpritePal]
              end
              else
              begin
                if palIdx <> Ord(TMItem.SpritePal) then
                  Continue;
                pal := Frame^.KeyFrame^.PaletteRGB[palIdx <> 0];
              end
            end;

            DrawTile(imgDest.Picture.Bitmap, sx, sy, tilePtr, pal, TMItem.HMirror, TMItem.VMirror);
          end;
        end;
    finally
      imgDest.Picture.Bitmap.EndUpdate;
    end;

    imgPalette.Picture.Bitmap.BeginUpdate;
    try
      for j := 0 to imgPalette.Picture.Bitmap.Height - 1 do
      begin
        p := imgPalette.Picture.Bitmap.ScanLine[j];
        for i := 0 to imgPalette.Picture.Bitmap.Width - 1 do
        begin
          if Assigned(Frame^.KeyFrame^.PaletteRGB[j <> 0]) then
            p^ := SwapRB(Frame^.KeyFrame^.PaletteRGB[j <> 0, i])
          else
            p^ := clFuchsia;

          Inc(p);
        end;
      end;
    finally
      imgPalette.Picture.Bitmap.EndUpdate;
    end;

    SetLength(oriCorr, CScreenHeight * CScreenWidth * 2);
    SetLength(chgCorr, CScreenHeight * CScreenWidth * 2);

    for j := 0 to CScreenHeight - 1 do
    begin
      Move(PInteger(imgSource.Picture.Bitmap.ScanLine[j])^, oriCorr[j * CScreenWidth], CScreenWidth * SizeOf(Integer));
      Move(PInteger(imgDest.Picture.Bitmap.ScanLine[j])^, chgCorr[j * CScreenWidth], CScreenWidth * SizeOf(Integer));
    end;

    for j := 0 to CScreenHeight - 1 do
      for i := 0 to CScreenWidth - 1 do
      begin
        oriCorr[CScreenWidth * CScreenHeight + i * CScreenHeight + j] := oriCorr[j * CScreenWidth + i];
        chgCorr[CScreenWidth * CScreenHeight + i * CScreenHeight + j] := chgCorr[j * CScreenWidth + i];
      end;

    lblCorrel.Caption := FormatFloat('0.000000', ComputeCorrelation(oriCorr, chgCorr));
  finally
    Repaint;
  end;
end;

// from https://www.delphipraxis.net/157099-fast-integer-rgb-hsl.html
procedure TMainForm.RGBToHSV(col: Integer; out h, s, v: Byte);
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

procedure TMainForm.RGBToHSV(col: Integer; out h, s, v: TFloat);
var
  bh, bs, bv: Byte;
begin
  bh := 0; bs := 0; bv := 0;
  RGBToHSV(col, bh, bs, bv);
  h := bh / 255.0;
  s := bs / 255.0;
  v := bv / 255.0;
end;

procedure TMainForm.RGBToYUV(col: Integer; out y, u, v: TFloat);
var
  yy, uu, vv: TFloat;
  r, g, b: Byte;
begin
  FromRGB(col, r, g, b);
  RGBToYUV(r, g, b, yy, uu, vv);
  y := yy; u := uu; v := vv; // for safe "out" param
end;

procedure TMainForm.RGBToYUV(r, g, b: Byte; out y, u, v: TFloat);
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

procedure TMainForm.RGBToLAB(r, g, b: TFloat; out ol, oa, ob: TFloat);
var
  ll, aa, bb: TFloat;
begin
  RGBToLAB(Integer(round(r * 255.0)), round(g * 255.0), round(b * 255.0), ll, aa, bb);
  ol := ll;
  oa := aa;
  ob := bb;
end;

procedure TMainForm.RGBToLAB(ir, ig, ib: Integer; out ol, oa, ob: TFloat);
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

function TMainForm.LABToRGB(ll, aa, bb: TFloat): Integer;
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

function TMainForm.YUVToRGB(y, u, v: TFloat): Integer;
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

// from https://lists.freepascal.org/pipermail/fpc-announce/2006-September/000508.html
generic procedure TMainForm.WaveletGS<T, PT>(Data: PT; Output: PT; dx, dy, depth: cardinal);
var
  x, y: longint;
  offset: cardinal;
  factor: T;
  tempX: array[0 .. sqr(cTileWidth) - 1] of T;
  tempY: array[0 .. sqr(cTileWidth) - 1] of T;
begin
  FillChar(tempX[0], SizeOf(tempX), 0);
  FillChar(tempY[0], SizeOf(tempY), 0);

  factor:=(1.0 / sqrt(2.0)); //Normalized Haar

  for y:=0 to dy - 1 do //Transform Rows
  begin
    offset := y * cTileWidth;
    for x := 0 to (dx div 2) - 1 do
    begin
      tempX[x + offset]             := (Data[x * 2 + offset] + Data[(x * 2 + 1) + offset]) * factor; //LOW-PASS
      tempX[(x + dx div 2) +offset] := (Data[x * 2 + offset] - Data[(x * 2 + 1) + offset]) * factor; //HIGH-PASS
    end;
  end;

  for x := 0 to dx - 1 do //Transform Columns
    for y := 0 to (dy div 2) - 1 do
    begin
      tempY[x +y * cTileWidth]              := (tempX[x +y * 2 * cTileWidth] + tempX[x +(y * 2 + 1) * cTileWidth]) * factor; //LOW-PASS
      tempY[x +(y + dy div 2) * cTileWidth] := (tempX[x +y * 2 * cTileWidth] - tempX[x +(y * 2 + 1) * cTileWidth]) * factor; //HIGH-PASS
    end;

  for y := 0 to dy - 1 do
    Move(tempY[y * cTileWidth], Output[y * cTileWidth], dx * sizeof(T)); //Copy to Wavelet

  if depth>0 then
    specialize waveletgs<T, PT>(Output, Output, dx div 2, dy div 2, depth - 1); //Repeat for SubDivisionDepth
end;

generic procedure TMainForm.DeWaveletGS<T, PT>(wl: PT; pic: PT; dx, dy, depth: longint);
Var x,y : longint;
    tempX: array[0 .. sqr(cTileWidth) - 1] of T;
    tempY: array[0 .. sqr(cTileWidth) - 1] of T;
    offset,offsetm1,offsetp1 : longint;
    factor : T;
    dyoff,yhalf,yhalfoff,yhalfoff2,yhalfoff3 : longint;
BEGIN
 FillChar(tempX[0], SizeOf(tempX), 0);
 FillChar(tempY[0], SizeOf(tempY), 0);

 if depth>0 then specialize dewaveletgs<T, PT>(wl,wl,dx div 2,dy div 2,depth-1); //Repeat for SubDivisionDepth

 factor:=(1.0/sqrt(2.0)); //Normalized Haar

 ////

 yhalf:=(dy div 2)-1;
 dyoff:=(dy div 2)*cTileWidth;
 yhalfoff:=yhalf*cTileWidth;
 yhalfoff2:=(yhalf+(dy div 2))*cTileWidth;
 yhalfoff3:=yhalfoff*2 +cTileWidth;

 if (yhalf>0) then begin //The first and last pixel has to be done "normal"
  for x:=0 to dx-1 do begin
   tempy[x]     := (wl[x] + wl[x+dyoff])*factor; //LOW-PASS
   tempy[x+cTileWidth]:= (wl[x] - wl[x+dyoff])*factor; //HIGH-PASS

   tempy[x +yhalfoff*2]:= (wl[x +yhalfoff] + wl[x +yhalfoff2])*factor; //LOW-PASS
   tempy[x +yhalfoff3] := (wl[x +yhalfoff] - wl[x +yhalfoff2])*factor; //HIGH-PASS
  end;
 end else begin
  for x:=0 to dx-1 do begin
   tempy[x]     := (wl[x] + wl[x+dyoff])*factor; //LOW-PASS
   tempy[x+cTileWidth]:= (wl[x] - wl[x+dyoff])*factor; //HIGH-PASS
  end;
 end;

 //

 dyoff:=(dy div 2)*cTileWidth;
 yhalf:=(dy div 2)-2;

 if (yhalf>=1) then begin                  //More then 2 pixels in the row?
  //
  if (dy>=4) then begin                    //DY must be greater then 4 to make the faked algo look good.. else it must be done "normal"
  //
   for x:=0 to dx-1 do begin               //Inverse Transform Colums (fake: if (high-pass coefficient=0.0) and (surrounding high-pass coefficients=0.0) then interpolate between surrounding low-pass coefficients)
    offsetm1:=0;
    offset:=cTileWidth;
    offsetp1:=cTileWidth*2;

    for y:=1 to yhalf do begin
     if (wl[x +offset+dyoff]<>0.0) then begin //!UPDATED
      tempy[x +offset*2]       := (wl[x +offset] + wl[x +offset+dyoff])*factor; //LOW-PASS
      tempy[x +offset*2 +cTileWidth] := (wl[x +offset] - wl[x +offset+dyoff])*factor; //HIGH-PASS
     end else begin //!UPDATED
      if (wl[x +offsetm1 +dyoff]=0.0) and (wl[x +offsetp1]<>wl[x +offset]) and ((y=yhalf) or (wl[x +offsetp1]<>wl[x +offsetp1 +cTileWidth])) then tempy[x +offset*2]:=(wl[x +offset]*0.8 + wl[x +offsetm1]*0.2)*factor //LOW-PASS
       else tempy[x +offset*2]:=wl[x +offset]*factor;
      if (wl[x +offsetp1 +dyoff]=0.0) and (wl[x +offsetm1]<>wl[x +offset]) and ((y=1) or (wl[x +offsetm1]<>wl[x +offsetm1 -cTileWidth])) then tempy[x +offset*2 +cTileWidth]:=(wl[x +offset]*0.8 + wl[x +offsetp1]*0.2)*factor //HIGH-PASS
       else tempy[x +offset*2 +cTileWidth]:=wl[x +offset]*factor;
     end;

     inc(offsetm1,cTileWidth);
     inc(offset,cTileWidth);
     inc(offsetp1,cTileWidth);
    end;

   end;
  //
  end else //DY<4
  //
   for x:=0 to dx-1 do begin
    offset:=cTileWidth;
    for y:=1 to yhalf do begin
     tempy[x +offset*2]      := (wl[x +offset] + wl[x +offset +dyoff])*factor; //LOW-PASS
     tempy[x +offset*2+cTileWidth] := (wl[x +offset] - wl[x +offset +dyoff])*factor; //HIGH-PASS

     inc(offset,cTileWidth);
    end;
   end;
  //
 end;

 ////

 offset:=0;
 yhalf:=(dx div 2)-1;
 yhalfoff:=(yhalf+dx div 2);
 yhalfoff2:=yhalf*2+1;

 if (yhalf>0) then begin
  for y:=0 to dy-1 do begin //The first and last pixel has to be done "normal"
   tempx[offset]   :=(tempy[offset] + tempy[yhalf+1 +offset])*factor; //LOW-PASS
   tempx[offset+1] :=(tempy[offset] - tempy[yhalf+1 +offset])*factor; //HIGH-PASS

   tempx[yhalf*2 +offset]   :=(tempy[yhalf +offset] + tempy[yhalfoff +offset])*factor; //LOW-PASS
   tempx[yhalfoff2 +offset] :=(tempy[yhalf +offset] - tempy[yhalfoff +offset])*factor; //HIGH-PASS

   inc(offset,cTileWidth);
  end;
 end else begin
  for y:=0 to dy-1 do begin //The first and last pixel has to be done "normal"
   tempx[offset]   :=(tempy[offset] + tempy[yhalf+1 +offset])*factor; //LOW-PASS
   tempx[offset+1] :=(tempy[offset] - tempy[yhalf+1 +offset])*factor; //HIGH-PASS

   inc(offset,cTileWidth);
  end;
 end;

 //

 dyoff:=(dx div 2);
 yhalf:=(dx div 2)-2;

 if (yhalf>=1) then begin

  if (dx>=4) then begin

   offset:=0;
   for y:=0 to dy-1 do begin               //Inverse Transform Rows (fake: if (high-pass coefficient=0.0) and (surrounding high-pass coefficients=0.0) then interpolate between surrounding low-pass coefficients)
    for x:=1 to yhalf do
     if (tempy[x +dyoff +offset]<>0.0) then begin //!UPDATED
      tempx[x*2 +offset]   :=(tempy[x +offset] + tempy[x +dyoff +offset])*factor; //LOW-PASS
      tempx[x*2+1 +offset] :=(tempy[x +offset] - tempy[x +dyoff +offset])*factor; //HIGH-PASS
     end else begin //!UPDATED
      if (tempy[x-1+dyoff +offset]=0.0) and (tempy[x+1 +offset]<>tempy[x +offset]) and ((x=yhalf) or (tempy[x+1 +offset]<>tempy[x+2 +offset])) then tempx[x*2 +offset]:=(tempy[x +offset]*0.8 + tempy[x-1 +offset]*0.2)*factor //LOW-PASS
       else tempx[x*2 +offset]:=tempy[x +offset]*factor;
      if (tempy[x+1+dyoff +offset]=0.0) and (tempy[x-1 +offset]<>tempy[x +offset]) and ((x=1) or (tempy[x-1 +offset]<>tempy[x-2 +offset])) then tempx[x*2+1 +offset]:=(tempy[x +offset]*0.8 + tempy[x+1 +offset]*0.2)*factor //HIGH-PASS
       else tempx[x*2+1 +offset]:=tempy[x +offset]*factor;
     end;
    inc(offset,cTileWidth);
   end;

  end else begin //DX<4

   offset:=0;
   for y:=0 to dy-1 do begin               //Inverse Transform Rows (fake: if (high-pass coefficient=0.0) and (surrounding high-pass coefficients=0.0) then interpolate between surrounding low-pass coefficients)
    for x:=1 to yhalf do begin
     tempx[x*2 +offset]   := (tempy[x +offset] + tempy[x +dyoff +offset])*factor; //LOW-PASS
     tempx[x*2+1 +offset] := (tempy[x +offset] - tempy[x +dyoff +offset])*factor; //HIGH-PASS
    end;
    inc(offset,cTileWidth);
   end;

  end;

 end;

 ////

 for y:=0 to dy-1 do
  move(tempx[y*cTileWidth],pic[y*cTileWidth],dx*sizeof(T)); //Copy to Pic
END;

procedure TMainForm.ProgressRedraw(CurFrameIdx: Integer; ProgressStep: TEncoderStep);
const
  cProgressMul = 100;
var
  esLen: Integer;
  t: Integer;
begin
  scalable_allocation_command(TBBMALLOC_CLEAN_ALL_BUFFERS, nil); // force the mem allocator to release unused memory

  pbProgress.Max := (Ord(High(TEncoderStep)) + 1) * cProgressMul;

  if CurFrameIdx >= 0 then
  begin
    esLen := Max(0, cEncoderStepLen[FProgressStep]) + Max(0, -cEncoderStepLen[FProgressStep]) * Length(FKeyFrames);
    FProgressPosition := iDiv0(CurFrameIdx * cProgressMul, esLen);
  end;

  if ProgressStep <> esNone then
  begin
    FProgressPosition := 0;
    FOldProgressPosition := 0;
    FProgressStep := ProgressStep;
    pbProgress.Position := Ord(FProgressStep) * cProgressMul;
    Screen.Cursor := crHourGlass;
    FProgressPrevTime := GetTickCount;
  end;

  if (CurFrameIdx < 0) and (ProgressStep = esNone) then
  begin
    FProgressPosition := 0;
    FOldProgressPosition := 0;
    FProgressStep := esNone;
    FProgressPosition := 0;
    FProgressPrevTime := GetTickCount;
    FProgressStartTime := FProgressPrevTime;
  end;

  pbProgress.Position := pbProgress.Position + (FProgressPosition - FOldProgressPosition);
  pbProgress.Invalidate;
  lblPct.Caption := IntToStr(pbProgress.Position * 100 div pbProgress.Max) + '%';
  lblPct.Invalidate;
  Repaint;

  t := GetTickCount;
  if CurFrameIdx >= 0 then
  begin
    WriteLn('Step: ', Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(FProgressStep)), 3), ' / ', FProgressPosition,
      #9'Time: ', FormatFloat('0.000', (t - FProgressPrevTime) / 1000), #9'All: ', FormatFloat('0.000', (t - FProgressStartTime) / 1000));
  end;
  FProgressPrevTime := t;

  FOldProgressPosition := FProgressPosition;
end;

function TMainForm.GetGlobalTileCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(FTiles) do
    if FTiles[i]^.Active then
      Inc(Result);
end;

function TMainForm.GetFrameTileCount(AFrame: PFrame; ADelta, AFromTileIdxs: Boolean; ADeltaFrame: PFrame): Integer;
var
  Used: array of Boolean;
  i, j: Integer;
begin
  Result := 0;

  if Length(FTiles) = 0 then
    Exit;

  SetLength(Used, Length(FTiles));
  FillChar(Used[0], Length(FTiles) * SizeOf(Boolean), 0);

  if AFromTileIdxs then
  begin
    for i := 0 to High(AFrame^.TilesIndexes) do
      Used[AFrame^.TilesIndexes[i].RomIndex] := True;

    if ADelta then
    begin
      Assert(not Assigned(ADeltaFrame));
      if AFrame^.Index > 0 then
        for i := 0 to High(FFrames[AFrame^.Index - 1].TilesIndexes) do
          Used[FFrames[AFrame^.Index - 1].TilesIndexes[i].RomIndex] := True;
    end;
  end
  else
  begin
    for j := 0 to cTileMapHeight - 1 do
      for i := 0 to cTileMapWidth - 1 do
        Used[AFrame^.TileMap[j, i].TileIdx] := True;

    if ADelta then
    begin
      if Assigned(ADeltaFrame) then
      begin
        for j := 0 to cTileMapHeight - 1 do
          for i := 0 to cTileMapWidth - 1 do
            Used[ADeltaFrame^.TileMap[j, i].TileIdx] := True;
      end
      else if AFrame^.Index > 0 then
      begin
        for j := 0 to cTileMapHeight - 1 do
          for i := 0 to cTileMapWidth - 1 do
            Used[FFrames[AFrame^.Index - 1].TileMap[j, i].TileIdx] := True;
      end;
    end;
  end;

  for i := 0 to High(Used) do
    Inc(Result, ifthen(Used[i], 1));
end;

function TMainForm.GetKeyFrameFrameMaxTileCount(AKF: PKeyFrame; ADelta, ADeltaUsePrevKF: Boolean): Integer;
var
  Used: array of Boolean;
  i, j, frmIdx, ftc: Integer;
begin
  Result := 0;

  if Length(FTiles) = 0 then
    Exit;

  SetLength(Used, Length(FTiles));

  for frmIdx := AKF^.StartFrame to AKF^.EndFrame do
  begin
    FillChar(Used[0], Length(FTiles) * SizeOf(Boolean), 0);

    for j := 0 to cTileMapHeight - 1 do
      for i := 0 to cTileMapWidth - 1 do
        Used[FFrames[frmIdx].TileMap[j, i].TileIdx] := True;

    if ADelta and (frmIdx > IfThen(ADeltaUsePrevKF, 0, AKF^.StartFrame)) then
      for j := 0 to cTileMapHeight - 1 do
        for i := 0 to cTileMapWidth - 1 do
          Used[FFrames[frmIdx - 1].TileMap[j, i].TileIdx] := True;

    ftc := 0;
    for i := 0 to High(Used) do
      Inc(ftc, ifthen(Used[i], 1));

    Result := max(Result, ftc);
  end;
end;

procedure TMainForm.CopyTile(const Src: TTile; var Dest: TTile);
var x,y: Integer;
begin
  Dest.Active := Src.Active;
  Dest.TmpIndex := Src.TmpIndex;
  Dest.MergeIndex := Src.MergeIndex;
  Dest.UseCount := Src.UseCount;

  SetLength(Dest.PaletteIndexes, Length(Src.PaletteIndexes));
  SetLength(Dest.PaletteRGB, Length(Src.PaletteRGB));

  if Assigned(Dest.PaletteIndexes) then
    move(Src.PaletteIndexes[0], Dest.PaletteIndexes[0], Length(Src.PaletteIndexes) * SizeOf(Integer));
  if Assigned(Dest.PaletteRGB) then
    move(Src.PaletteRGB[0], Dest.PaletteRGB[0], Length(Src.PaletteRGB) * SizeOf(Integer));

  for y := 0 to cTileWidth - 1 do
    for x := 0 to cTileWidth - 1 do
    begin
      Dest.RGBPixels[y, x] := Src.RGBPixels[y, x];
      Dest.PalPixels[y, x] := Src.PalPixels[y, x];
    end;
end;


function CompareTilePalPixels(Item1, Item2, UserParameter:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PPTile(Item1)^;
  t2 := PPTile(Item2)^;
  Result := CompareByte(t1^.PalPixels[0, 0], t2^.PalPixels[0, 0], sqr(cTileWidth));
end;

procedure TMainForm.MakeTilesUnique;
var
  i, firstSameIdx: Integer;
  sortArr: array of PTile;
  sameIdxArr: array of Integer;

  procedure DoOneMerge;
  var
    j: Integer;
  begin
    if i - firstSameIdx >= 2 then
    begin
      for j := firstSameIdx to i - 1 do
        sameIdxArr[j - firstSameIdx] := sortArr[j]^.TmpIndex;
      MergeTiles(sameIdxArr, i - firstSameIdx, sameIdxArr[0]);
    end;
    firstSameIdx := i;
  end;

begin
  // sort global tiles by palette indexes (L to R, T to B)

  SetLength(sameIdxArr, Length(FTiles));
  sortArr := Copy(FTiles);

  for i := 0 to High(sortArr) do
    sortArr[i]^.TmpIndex := i;

  QuickSort(sortArr[0], 0, High(sortArr), SizeOf(PTile), @CompareTilePalPixels);

  // merge exactly similar tiles (so, consecutive after prev code)

  firstSameIdx := 0;
  for i := 1 to High(sortArr) do
    if CompareByte(sortArr[i - 1]^.PalPixels[0, 0], sortArr[i]^.PalPixels[0, 0], sqr(cTileWidth)) <> 0 then
      DoOneMerge;

  i := High(sortArr);
  DoOneMerge;
end;

procedure TMainForm.MergeTiles(const TileIndexes: array of Integer; TileCount: Integer; BestIdx: Integer);
var
  j, k: Integer;
begin
  if TileCount <= 0 then
    Exit;

  for k := 0 to TileCount - 1 do
  begin
    j := TileIndexes[k];

    if j = BestIdx then
      Continue;

    Inc(FTiles[BestIdx]^.UseCount, FTiles[j]^.UseCount);

    FTiles[j]^.Active := False;
    FTiles[j]^.MergeIndex := BestIdx;
    FTiles[j]^.UseCount := 0;

    FillChar(FTiles[j]^.RGBPixels, SizeOf(FTiles[j]^.RGBPixels), 0);
    FillChar(FTiles[j]^.PalPixels, SizeOf(FTiles[j]^.PalPixels), 0);
  end;
end;

procedure TMainForm.InitMergeTiles;
var
  i: Integer;
begin
  for i := 0 to High(FTiles) do
    FTiles[i]^.MergeIndex := -1;
end;

procedure TMainForm.FinishMergeTiles;
var
  i, j, k, idx: Integer;
begin
  for k := 0 to High(FFrames) do
    for j := 0 to (CTileMapHeight - 1) do
      for i := 0 to (CTileMapWidth - 1) do
      begin
        idx := FTiles[FFrames[k].TileMap[j, i].TileIdx]^.MergeIndex;
        if idx >= 0 then
          FFrames[k].TileMap[j, i].TileIdx := idx;
      end;
end;

procedure TMainForm.MirrorTiles(AOnPal, ASimple: Boolean);

  procedure DoMirror(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    iFrame, sy, sx: Integer;
    q00, q01, q10, q11: Integer;
    hmir, vmir: Boolean;
    TMI: PTileMapItem;
    TileFrame: TFrame;
  begin
    if not FTiles[AIndex]^.Active then
      Exit;

    // enforce a 'spin' on tiles mirrors (brighter top-left corner)

    q00 := GetTileZoneSum(FTiles[AIndex]^, AOnPal, 0, 0, cTileWidth div 2, cTileWidth div 2);
    q01 := GetTileZoneSum(FTiles[AIndex]^, AOnPal, cTileWidth div 2, 0, cTileWidth div 2, cTileWidth div 2);
    q10 := GetTileZoneSum(FTiles[AIndex]^, AOnPal, 0, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);
    q11 := GetTileZoneSum(FTiles[AIndex]^, AOnPal, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);

    hmir := q00 + q10 < q01 + q11;
    vmir := q00 + q01 < q10 + q11;

    if hmir then HMirrorTile(FTiles[AIndex]^);
    if vmir then VMirrorTile(FTiles[AIndex]^);

    if ASimple then
    begin
      TMI := GetTileIndexTMItem(AIndex, TileFrame);

      TMI^.HMirror := TMI^.HMirror xor hmir;
      TMI^.VMirror := TMI^.VMirror xor vmir;
    end
    else
    begin
      for iFrame := 0 to High(FFrames) do
        for sy := 0 to cTileMapHeight - 1 do
          for sx := 0 to cTileMapWidth - 1 do
          begin
            TMI := @FFrames[iFrame].TileMap[sy, sx];

            if TMI^.TileIdx = AIndex then
            begin
              TMI^.HMirror := TMI^.HMirror xor hmir;
              TMI^.VMirror := TMI^.VMirror xor vmir;
            end;
          end;
    end;
  end;

begin
  ProcThreadPool.DoParallelLocalProc(@DoMirror, 0, High(FTiles));
end;

procedure TMainForm.DoFrameTiling(AFrame: PFrame; DesiredNbTiles: Integer; Dual: Boolean);
var
  iTile, iFrm, iUC, iDCT, dsIdx, dsLen, clusterLineCount, lineIdx, tileIdx, clusterIdx, sx, sy: Integer;
  Yakmo: PYakmo;
  Dataset, Centroids: TFloatDynArray2;
  Clusters, DSToTileIdx: TIntegerDynArray;
  ToMergeIdxs: TIntegerDynArray;
  DCT: array[0 .. cTileDCTSize - 1] of TFloat;
begin
  for iTile := 0 to High(FTiles) do
    FTiles[iTile]^.TmpIndex := 0;

  for iFrm := IfThen(Dual and (AFrame^.Index > 0), AFrame^.Index - 1, AFrame^.Index) to AFrame^.Index + 1 - 1 do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
        tileIdx := FFrames[iFrm].TileMap[sy, sx].TileIdx;
        Inc(FTiles[tileIdx]^.TmpIndex);
      end;

  dsLen := 0;
  for iTile := 0 to High(FTiles) do
    if FTiles[iTile]^.TmpIndex > 0 then
      Inc(dsLen, FTiles[iTile]^.UseCount);

  SetLength(Dataset, dsLen, cTileDCTSize);
  SetLength(Clusters, dsLen);
  SetLength(Centroids, DesiredNbTiles, cTileDCTSize);
  SetLength(DSToTileIdx, dsLen);

  dsIdx := 0;
  for iTile := 0 to High(FTiles) do
    if FTiles[iTile]^.TmpIndex > 0 then
    begin
      ComputeTilePsyVisFeatures(FTiles[iTile]^, FFrameTilingMode, False, False, False, False, cColorCpns, nil, @DCT[0]);

      for iUC := 1 to FTiles[iTile]^.UseCount do
      begin
        Move(DCT[0], Dataset[dsIdx, 0], cTileDCTSize * SizeOf(TFloat));
        DSToTileIdx[dsIdx] := iTile;
        Inc(dsIdx);
      end;
    end;

  Assert(dsIdx = dsLen);

  DesiredNbTiles := min(dsLen, DesiredNbTiles);

  yakmo_set_num_threads(ProcThreadPool.MaxThreadCount);
  Yakmo := yakmo_create(DesiredNbTiles, 1, MaxInt, 1, 0, 0, 0);
  yakmo_load_train_data(Yakmo, dsLen, cTileDCTSize, PPFloat(@Dataset[0]));
  SetLength(Dataset, 0); // free up some memory
  yakmo_train_on_data(Yakmo, @Clusters[0]);
  yakmo_get_centroids(Yakmo, PPFloat(@Centroids[0]));
  yakmo_destroy(Yakmo);

  SetLength(ToMergeIdxs, dsLen);

  // build a list of this centroid tiles

  for clusterIdx := 0 to DesiredNbTiles - 1 do
  begin
    clusterLineCount := 0;
    for lineIdx := 0 to dsLen - 1 do
    begin
      if Clusters[lineIdx] = clusterIdx then
      begin
        ToMergeIdxs[clusterLineCount] := DSToTileIdx[lineIdx];
        Inc(clusterLineCount);
      end;
    end;

    if clusterLineCount >= 2 then
    begin
      // use the centroid as RGB tile

      for iDCT := 0 to cTileDCTSize - 1 do
      begin
        DCT[iDCT] := 0.0;
        if not IsNan(Centroids[clusterIdx, iDCT]) and not IsInfinite(Centroids[clusterIdx, iDCT]) then
          DCT[iDCT] := Centroids[clusterIdx, iDCT];
      end;

      ComputeInvTilePsyVisFeatures(@DCT[0], FFrameTilingMode, False, cColorCpns, FTiles[ToMergeIdxs[0]]^);

      // apply to cluster
      MergeTiles(ToMergeIdxs, clusterLineCount, ToMergeIdxs[0]);
    end;
  end;
end;

procedure TMainForm.FixupTileCount(AFrame: PFrame; DesiredNbTiles: Integer; Dual: Boolean);
var
  iTile, iFrm, iUC, dsIdx, dsLen, clusterLineCount, lineIdx, tileIdx, clusterIdx, sx, sy: Integer;
  Dataset, Centroids: TByteDynArray2;
  Clusters, DSToTileIdx: TIntegerDynArray;
  ToMergeIdxs: TIntegerDynArray;
  Line: array[0 .. cKModesFeatureCount - 1] of Byte;
  KModes: TKModes;
begin
  for iTile := 0 to High(FTiles) do
    FTiles[iTile]^.TmpIndex := 0;

  for iFrm := IfThen(Dual and (AFrame^.Index > 0), AFrame^.Index - 1, AFrame^.Index) to AFrame^.Index + 1 - 1 do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
      begin
        tileIdx := FFrames[iFrm].TileMap[sy, sx].TileIdx;
        Inc(FTiles[tileIdx]^.TmpIndex);
      end;

  dsLen := 0;
  for iTile := 0 to High(FTiles) do
    if FTiles[iTile]^.TmpIndex > 0 then
      Inc(dsLen, FTiles[iTile]^.UseCount);

  SetLength(Dataset, dsLen, cKModesFeatureCount);
  SetLength(Clusters, dsLen);
  SetLength(Centroids, DesiredNbTiles, cKModesFeatureCount);
  SetLength(DSToTileIdx, dsLen);

  dsIdx := 0;
  for iTile := 0 to High(FTiles) do
    if FTiles[iTile]^.TmpIndex > 0 then
    begin
      WriteTileDatasetLine(FTiles[iTile]^, Line);

      for iUC := 1 to FTiles[iTile]^.UseCount do
      begin
        Move(Line[0], Dataset[dsIdx, 0], cKModesFeatureCount * SizeOf(Byte));
        DSToTileIdx[dsIdx] := iTile;
        Inc(dsIdx);
      end;
    end;

  Assert(dsIdx = dsLen);

  DesiredNbTiles := min(dsLen, DesiredNbTiles);

  KModes := TKModes.Create;
  try
    KModes.ComputeKModes(Dataset, DesiredNbTiles, 1, cTilePaletteSize, Clusters, Centroids);
  finally
    KModes.Free;
  end;

  SetLength(ToMergeIdxs, dsLen);

  // build a list of this centroid tiles

  for clusterIdx := 0 to DesiredNbTiles - 1 do
  begin
    clusterLineCount := 0;
    for lineIdx := 0 to dsLen - 1 do
    begin
      if Clusters[lineIdx] = clusterIdx then
      begin
        ToMergeIdxs[clusterLineCount] := DSToTileIdx[lineIdx];
        Inc(clusterLineCount);
      end;
    end;

    if clusterLineCount >= 2 then
    begin
      // use the centroid as pal tile
      Move(Centroids[clusterIdx, 0], FTiles[ToMergeIdxs[0]]^.PalPixels[0, 0], cKModesFeatureCount * SizeOf(Byte));

      // apply to cluster
      MergeTiles(ToMergeIdxs, clusterLineCount, ToMergeIdxs[0]);
    end;
  end;
end;

procedure TMainForm.DoTemporalSmoothing(AFrameIdx: Integer; Y: Integer; Strength: TFloat);
var
  sx: Integer;
  cmp: TFloat;
  TMI, PrevTMI: PTileMapItem;
  Tile_, PrevTile: PTile;
  TileDCT, PrevTileDCT: TFloatDynArray;
begin
  if FFrames[AFrameIdx].KeyFrame <> FFrames[AFrameIdx - 1].KeyFrame then // prevent ghosting between keyframes
    Exit;

  SetLength(PrevTileDCT, cTileDCTSize);
  SetLength(TileDCT, cTileDCTSize);

  for sx := 0 to cTileMapWidth - 1 do
  begin
    PrevTMI := @FFrames[AFrameIdx - 1].TileMap[Y, sx];
    TMI := @FFrames[AFrameIdx].TileMap[Y, sx];

    // compare DCT of current tile with tile from prev frame tilemap

    PrevTile := FTiles[PrevTMI^.TileIdx];
    Tile_ := FTiles[TMI^.TileIdx];

    ComputeTilePsyVisFeatures(PrevTile^, pvsWeightedDCT, True, False, PrevTMI^.HMirror, PrevTMI^.VMirror, cColorCpns, FFrames[AFrameIdx - 1].KeyFrame^.PaletteRGB[PrevTMI^.SpritePal], @PrevTileDCT[0]);
    ComputeTilePsyVisFeatures(Tile_^, pvsWeightedDCT, True, False, TMI^.HMirror, TMI^.VMirror, cColorCpns, FFrames[AFrameIdx].KeyFrame^.PaletteRGB[TMI^.SpritePal], @TileDCT[0]);

    cmp := CompareEuclideanDCT(TileDCT, PrevTileDCT);
    cmp := sqrt(cmp / cTileDCTSize);

    // if difference is low enough, mark the tile as smoothed for tilemap compression use

    TMI^.Smoothed := False;

    if Abs(cmp) <= Strength then
    begin
      if TMI^.TileIdx >= PrevTMI^.TileIdx then // lower tile index means the tile is used more often
      begin
        TMI^.TileIdx := PrevTMI^.TileIdx;
        TMI^.HMirror := PrevTMI^.HMirror;
        TMI^.VMirror := PrevTMI^.VMirror;
        TMI^.SpritePal := PrevTMI^.SpritePal;
      end
      else
      begin
        PrevTMI^.TileIdx := TMI^.TileIdx;
        PrevTMI^.HMirror := TMI^.HMirror;
        PrevTMI^.VMirror := TMI^.VMirror;
        PrevTMI^.SpritePal := TMI^.SpritePal;
      end;

      if AFrameIdx >= cSmoothingPrevFrame then
      begin
        PrevTMI := @FFrames[AFrameIdx - cSmoothingPrevFrame].TileMap[Y, sx];
        TMI^.Smoothed := CompareMem(PrevTMI, TMI, SizeOf(TTileMapItem));
      end;
    end;
  end;
end;

function TMainForm.GetTileUseCount(ATileIndex: Integer): Integer;
var
  i, sx, sy: Integer;
begin
  Result := 0;
  for i := 0 to High(FFrames) do
    for sy := 0 to cTileMapHeight - 1 do
      for sx := 0 to cTileMapWidth - 1 do
        Inc(Result, Ord(FFrames[i].TileMap[sy, sx].TileIdx = ATileIndex));
end;

function TMainForm.GetTileIndexTMItem(ATileIndex: Integer; out AFrame: TFrame): PTileMapItem;
var
  frmIdx, int, sy, sx: Integer;
begin
  DivMod(ATileIndex , cTileMapSize, frmIdx, int);
  DivMod(int, cTileMapWidth, sy, sx);

  Result := @FFrames[frmIdx].TileMap[sy, sx];
  AFrame := FFrames[frmIdx];

  Assert(Result^.TileIdx = ATileIndex);
end;

function TMainForm.WriteTileDatasetLine(const ATile: TTile; var DataLine: array of Byte): Integer;
var
  x, y: Integer;
begin
  Result := 0;
  for y := 0 to cTileWidth - 1 do
    for x := 0 to cTileWidth - 1 do
    begin
      DataLine[Result] := ATile.PalPixels[y, x];
      Inc(Result);
    end;

  Assert(Result = cKModesFeatureCount);
end;
procedure TMainForm.DoKeyFrameTiling(AKeyFrame: PKeyFrame; DesiredNbTiles: Integer);
var
  YakmoDataset: TFloatDynArray2;
  TileIndices: TIntegerDynArray;

  procedure DoYakmo;
  var
    Yakmo: PYakmo;
    LocCentroids: TFloatDynArray2;
    LocClusters: TIntegerDynArray;
    iDCT, lineIdx, clusterIdx, clusterLineCount, DSLen: Integer;
    ToMergeIdxs: TIntegerDynArray;
    DCT: array[0 .. cTileDCTSize - 1] of TFloat;
  begin

    DSLen := Length(YakmoDataset);
    if DSLen <= DesiredNbTiles then
      Exit;

    SetLength(LocClusters, DSLen);
    SetLength(LocCentroids, DesiredNbTiles, cTileDCTSize);

    yakmo_set_num_threads(max(1, ProcThreadPool.MaxThreadCount div Length(FKeyFrames)));
    Yakmo := yakmo_create(DesiredNbTiles, 1, MaxInt, 1, 0, 0, 0);
    yakmo_load_train_data(Yakmo, DSLen, cTileDCTSize, PPFloat(@YakmoDataset[0]));
    SetLength(YakmoDataset, 0); // free up some memmory
    yakmo_train_on_data(Yakmo, @LocClusters[0]);
    yakmo_get_centroids(Yakmo, PPFloat(@LocCentroids[0]));
    yakmo_destroy(Yakmo);

    SetLength(ToMergeIdxs, DSLen);

    // build a list of this centroid tiles

    for clusterIdx := 0 to DesiredNbTiles - 1 do
    begin
      clusterLineCount := 0;
      for lineIdx := 0 to High(TileIndices) do
      begin
        if LocClusters[lineIdx] = clusterIdx then
        begin
          ToMergeIdxs[clusterLineCount] := TileIndices[lineIdx];
          Inc(clusterLineCount);
        end;
      end;

      if clusterLineCount >= 2 then
      begin
        // use the centroid as RGB tile

        for iDCT := 0 to cTileDCTSize - 1 do
        begin
          DCT[iDCT] := 0.0;
          if not IsNan(LocCentroids[clusterIdx, iDCT]) and not IsInfinite(LocCentroids[clusterIdx, iDCT]) then
            DCT[iDCT] := LocCentroids[clusterIdx, iDCT];
        end;

        ComputeInvTilePsyVisFeatures(@DCT[0], FGlobalTilingMode, False, cColorCpns, FTiles[ToMergeIdxs[0]]^);

        // apply to cluster
        MergeTiles(ToMergeIdxs, clusterLineCount, ToMergeIdxs[0]);
      end;
    end;

    // free up memory

    SetLength(TileIndices, 0);
  end;
var
  iTile: Integer;
  di: Integer;
begin
  SetLength(YakmoDataset, AKeyFrame^.FrameCount * cTileMapSize, cTileDCTSize);
  SetLength(TileIndices, Length(YakmoDataset));

  // prepare KModes KModesDataset, one line per tile, 64 palette indexes per line
  // also choose KModes starting point

  di := 0;
  for iTile := AKeyFrame^.StartFrame * cTileMapSize to (AKeyFrame^.EndFrame + 1) * cTileMapSize - 1 do
  begin
    Assert(FTiles[iTile]^.Active and (FTiles[iTile]^.UseCount = 1));

    ComputeTilePsyVisFeatures(FTiles[iTile]^, FGlobalTilingMode, False, False, False, False, cColorCpns, nil, @YakmoDataset[di, 0]);
    TileIndices[di] := iTile;
    Inc(di);
  end;

  Assert(di = Length(YakmoDataset));

  // run the KMeans algorithm, which will group similar tiles until it reaches a fixed amount of groups
  DoYakmo;

  WriteLn('KF: ', AKeyFrame^.StartFrame:6, ' Yakmo end');
end;

function CompareTileUseCountRev(Item1, Item2, UserParameter:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PPTile(Item1)^;
  t2 := PPTile(Item2)^;
  Result := CompareValue(t2^.UseCount, t1^.UseCount);
  if Result = 0 then
    Result := CompareValue(t1^.TmpIndex, t2^.TmpIndex);
end;

procedure TMainForm.ReindexTiles;
var
  i, j, x, y, cnt: Integer;
  IdxMap: TIntegerDynArray;
begin
  cnt := 0;
  for i := 0 to High(FTiles) do
  begin
    FTiles[i]^.TmpIndex := i;
    if FTiles[i]^.Active then
      Inc(cnt);
  end;

  // pack the global tiles, removing inactive ones

  j := 0;
  for i := 0 to High(FTiles) do
    if not FTiles[i]^.Active then
    begin
      Dispose(FTiles[i])
    end
    else
    begin
      FTiles[j] := FTiles[i];
      Inc(j);
    end;

  SetLength(IdxMap, Length(FTiles));
  FillDWord(IdxMap[0], Length(FTiles), $ffffffff);

  // sort global tiles by use count descending (to make smoothing work better) then by tile index (to make tile indexes compression work better)

  SetLength(FTiles, cnt);
  QuickSort(FTiles[0], 0, High(FTiles), SizeOf(PTile), @CompareTileUseCountRev);

  // point tilemap items on new tiles indexes

  for i := 0 to High(FTiles) do
    IdxMap[FTiles[i]^.TmpIndex] := i;

  for i := 0 to High(FFrames) do
    for y := 0 to (cTileMapHeight - 1) do
      for x := 0 to (cTileMapWidth - 1) do
        FFrames[i].TileMap[y,x].TileIdx := IdxMap[FFrames[i].TileMap[y,x].TileIdx];
end;

function CompareTilesIndexes(Item1, Item2, UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PTileIndex(Item1)^.RomIndex, PTileIndex(Item2)^.RomIndex);
end;

procedure TMainForm.IndexFrameTiles(AFrame: PFrame);
var
  x, y, i, cnt, UseCount: Integer;
begin
  // build a list of tiles indexes used by the frame

  SetLength(AFrame^.TilesIndexes, cTileMapSize);

  cnt := 0;
  for i := 0 to High(FTiles) do
    if FTiles[i]^.Active then
    begin
      UseCount := 0;
      for y := 0 to (cTileMapHeight - 1) do
        for x := 0 to (cTileMapWidth - 1) do
          if AFrame^.TileMap[y, x].TileIdx = i then
          begin
            AFrame^.TilesIndexes[cnt].RomIndex := i;
            Inc(UseCount);
          end;

      if UseCount <> 0 then
        Inc(cnt);
    end;

  SetLength(AFrame^.TilesIndexes, cnt);

  // sort it

  QuickSort(AFrame^.TilesIndexes[0], 0, High(AFrame^.TilesIndexes), SizeOf(AFrame^.TilesIndexes[0]), @CompareTilesIndexes);

  // point tilemap on those indexes

  for i := 0 to High(AFrame^.TilesIndexes) do
    for y := 0 to (cTileMapHeight - 1) do
      for x := 0 to (cTileMapWidth - 1) do
        if AFrame^.TileMap[y, x].TileIdx = AFrame^.TilesIndexes[i].RomIndex then
          AFrame^.TileMap[y, x].FrameTileIndex := i;
end;

function TMainForm.DoExternalPCMEnc(AFN: String; Volume: Integer): String;
var
  i: Integer;
  Output, ErrOut: String;
  Process: TProcess;
begin
  Process := TProcess.Create(nil);

  Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
  Process.Executable := 'pcmenc.exe';
  Process.Parameters.Add('-p 4 -dt1 ' + IntToStr(cClocksPerSample) + ' -dt2 ' + IntToStr(cClocksPerSample) + ' -dt3 ' +
    IntToStr(cClocksPerSample) + ' -cpuf ' + IntToStr(cZ80Clock) + ' -rto 3 -a ' + IntToStr(Volume) + ' -r 4096 -precision 8 -smooth 10 "' + AFN + '"');
  Process.ShowWindow := swoHIDE;
  Process.Priority := ppIdle;

  i := 0;
  internalRuncommand(Process, Output, ErrOut, i, True); // destroys Process

  Result := AFN + '.pcmenc';
end;

function TMainForm.DoExternalFFMpeg(AFN: String; var AVidPath: String; var AAudioFile: String; AFrameCount: Integer): String;
var
  i: Integer;
  Output, ErrOut, vfl, afl: String;
  Process: TProcess;
begin
  Process := TProcess.Create(nil);

  Result := IncludeTrailingPathDelimiter(sysutils.GetTempDir) + 'tiler_png\';
  ForceDirectories(Result);

  DeleteDirectory(Result, True);

  AVidPath := Result + '%.4d.png';
  AAudioFile := Result + 'audio.wav';

  vfl := '';
  afl := '';
  if AFrameCount > 0 then
  begin
    vfl := ' -frames:v ' + IntToStr(AFrameCount);
    afl := ' -t ' + FloatToStr(AFrameCount * cRefreshRateDiv / cRefreshRate);
  end;

  Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
  Process.Executable := 'ffmpeg.exe';
  Process.Parameters.Add('-y -i "' + AFN + '" -r ' + FloatToStr(cRefreshRate / cRefreshRateDiv) + ' -vf scale=-1:192:flags=lanczos,crop=256:192 -start_number 0 ' + vfl + ' -compression_level 0 -pix_fmt rgb24 "' + Result + '%04d.png' + '" -ac 1 -af loudnorm=I=-16:TP=-1:LRA=11 -ar 10310 ' + afl + ' "' + AAudioFile + '"');
  Process.ShowWindow := swoHIDE;
  Process.Priority := ppIdle;

  i := 0;
  internalRuncommand(Process, Output, ErrOut, i, True); // destroys Process
end;

function CompareTilesIndexesVram(Item1, Item2, UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PTileIndex(Item1)^.VramIndex, PTileIndex(Item2)^.VramIndex);
end;

procedure TMainForm.SaveTileIndexes(ADataStream: TStream; AFrame: PFrame);
var
  tileIdxStream: TMemoryStream;
  prevDTI, sameCount, tiZ80Cycles: Integer;
  tiVBlank: Boolean;

  function CurrentLineJitter: Integer;
  begin
    Result := round(IfThen(tiVBlank, -cLineJitterCompensation * cCyclesPerLine, cLineJitterCompensation * cCyclesPerLine));
  end;

  procedure CountZ80Cycles(ACycleAdd: Integer);
  var
    cyPh: Integer;
  begin
    cyPh := cCyclesPerDisplayPhase[tiVBlank];
    tiZ80Cycles += ACycleAdd;
    if tiZ80Cycles > cyPh + CurrentLineJitter then
    begin
      tiZ80Cycles -= cyPh;
      tiVBlank := not tiVBlank;
      tileIdxStream.WriteByte(cTileIndexesVBlankSwitch);
      tiZ80Cycles += cTileIndexesTimings[tiVBlank, 4];
    end;
  end;

  procedure DoTileIndex;
  var
    priorCount, cyAdd: Integer;
    vbl: Boolean;
  begin
    vbl := tiVBlank;
    if sameCount = 1 then
    begin
      if vbl then
        CountZ80Cycles(cTileIndexesTimings[tiVBlank, 1]);
      tileIdxStream.WriteByte(prevDTI - 1);
      if not vbl then
        CountZ80Cycles(cTileIndexesTimings[tiVBlank, 1]);
    end
    else if sameCount <> 0 then
    begin
      // split upload in case we need to switch VBlank in the midlde of it
      priorCount := sameCount;
      cyAdd := cTileIndexesTimings[tiVBlank, 2] + priorCount * cTileIndexesTimings[tiVBlank, 3];

      while (tiZ80Cycles + cyAdd > cCyclesPerDisplayPhase[tiVBlank] + CurrentLineJitter) and (priorCount > 0) do
      begin
        Dec(priorCount);
        cyAdd := cTileIndexesTimings[tiVBlank, 2] + priorCount * cTileIndexesTimings[tiVBlank, 3];
      end;

      // compute cycles
      cyAdd := cTileIndexesTimings[tiVBlank, 2] + priorCount * cTileIndexesTimings[tiVBlank, 3] +
               cTileIndexesTimings[not tiVBlank, 2] + (sameCount - priorCount) * cTileIndexesTimings[not tiVBlank, 3];

      // in case we need to switch VBlank in the middle of the upload, add one more tile in "slow" not VBlank state
      if tiZ80Cycles + cyAdd > cCyclesPerDisplayPhase[tiVBlank] + CurrentLineJitter then
      begin
        if (priorCount > 0) and tiVBlank then
        begin
          Dec(priorCount);
          cyAdd -= cTileIndexesTimings[tiVBlank, 3];
          cyAdd += cTileIndexesTimings[not tiVBlank, 3];
        end
        else if (priorCount < sameCount) and not tiVBlank then
        begin
          Inc(priorCount);
          cyAdd += cTileIndexesTimings[tiVBlank, 3];
          cyAdd -= cTileIndexesTimings[not tiVBlank, 3];
        end;
      end;

      // if we output only one command, only one fixed cost should have been added
      if priorCount = 0 then
        cyAdd -= cTileIndexesTimings[tiVBlank, 2]
      else if priorCount = sameCount then
        cyAdd -= cTileIndexesTimings[not tiVBlank, 2];

      if priorCount > 0 then
        tileIdxStream.WriteByte(cTileIndexesRepeatStart + priorCount - 1);

      CountZ80Cycles(cyAdd);

      if sameCount - priorCount > 0 then
        tileIdxStream.WriteByte(cTileIndexesRepeatStart + sameCount - priorCount - 1);
    end;
  end;

var
  j, diffTileIndex: Integer;
  vbl: Boolean;
  prevTI: TTileIndex;
  LocalTIs: TTilesIndexes;
begin
  LocalTIs := Copy(AFrame^.TilesIndexes);
  QuickSort(LocalTIs[0], 0, High(LocalTIs), SizeOf(LocalTIs[0]), @CompareTilesIndexesVram);

  tileIdxStream := TMemoryStream.Create;
  try
    tiZ80Cycles :=  Round((cTileIndexesInitialLine - cScreenHeight) * cCyclesPerLine);
    tiVBlank := True;

    prevTI.RomIndex := -1;
    prevTI.VramIndex := -1;
    prevTI.InVRAM := False;
    prevDTI := -1;
    sameCount := 0;
    for j := 0 to High(AFrame^.TilesIndexes) do
    begin
      if LocalTIs[j].InVRAM then // already in VRAM?
        Continue;

      diffTileIndex := LocalTIs[j].RomIndex - prevTI.RomIndex;

      if (diffTileIndex <> 1) or (diffTileIndex <> prevDTI) or
          (diffTileIndex >= cTileIndexesMaxDiff) or (sameCount >= cTileIndexesMaxRepeat) or
          ((LocalTIs[j].RomIndex + cTileIndexesTileOffset) mod cTilesPerBank = 0) then // don't change bank while repeating
      begin
        DoTileIndex;
        sameCount := 1;
      end
      else
      begin
        Inc(sameCount);
      end;

      if (prevTI.RomIndex = -1) or (diffTileIndex >= cTileIndexesMaxDiff) or (diffTileIndex < 0) or
          ((LocalTIs[j].RomIndex + cTileIndexesTileOffset) div cTilesPerBank <>
           (prevTI.RomIndex + cTileIndexesTileOffset) div cTilesPerBank) or // any bank change must be a direct value
          (LocalTIs[j].VramIndex <> prevTI.VramIndex + 1) then // no VRAM continuity
      begin
        vbl := tiVBlank;
        if vbl then
          CountZ80Cycles(cTileIndexesTimings[tiVBlank, 0]);

        tileIdxStream.WriteByte(cTileIndexesDirectValue);
        tileIdxStream.WriteWord(cVRAMWriteCmd or (LocalTIs[j].VramIndex * cTileSize));
        tileIdxStream.WriteWord(LocalTIs[j].RomIndex + cTileIndexesTileOffset);

        if not vbl then
          CountZ80Cycles(cTileIndexesTimings[tiVBlank, 0]);

        diffTileIndex := -1;
        sameCount := 0;
      end;

      prevTI := LocalTIs[j];
      prevDTI := diffTileIndex;
    end;

    DoTileIndex;
    tileIdxStream.WriteByte(cTileIndexesTerminator);
    tileIdxStream.WriteByte(0);

    // the whole tiles indices should stay in the same bank
    if ADataStream.Size div cBankSize <> (ADataStream.Size + tileIdxStream.Size) div cBankSize then
    begin
      ADataStream.WriteByte(1);
      while ADataStream.Size mod cBankSize <> 0 do
        ADataStream.WriteByte(0);
      //WriteLn('Crossed bank limit!');
    end
    else
    begin
      ADataStream.WriteByte(0);
    end;

    tileIdxStream.Position := 0;
    ADataStream.CopyFrom(tileIdxStream, tileIdxStream.Size);

  finally
    tileIdxStream.Free;
  end;
end;

function CompareTMICache(Item1,Item2,UserParameter:Pointer):Integer;
begin
  Result := CompareValue(PInteger(Item2)^, PInteger(Item1)^);
end;

procedure TMainForm.SaveTilemap(ADataStream: TStream; AFrame: PFrame; AFrameIdx: Integer; ASkipFirst: Boolean);
var
  j, k, x, y, skipCount: Integer;
  rawTMI, tmiCacheIdx, awaitingCacheIdx, awaitingCount: Integer;
  smoothed: Boolean;
  tmi: PTileMapItem;
  rawTMIs: array[0..cTileMapSize] of Integer;
  tmiCache: array[0..4095] of packed record
    UsedCount: Integer;
    RawTMI: Integer;
  end;

  procedure DoTilemapTileCommand(DoCache, DoSkip: Boolean);
  begin
    if DoSkip and (skipCount > 0) then
    begin
      ADataStream.WriteByte(cTileMapCommandSkip or (skipCount shl 1));
      skipCount := 0;
    end;

    if DoCache and (awaitingCacheIdx <> cTileMapCacheSize) then
      if awaitingCacheIdx < 0 then
      begin
        ADataStream.WriteByte(cTileMapCommandRaw[awaitingCount] or ((-awaitingCacheIdx) shr 8));
        ADataStream.WriteByte((-awaitingCacheIdx) and $ff);
      end
      else
      begin
        ADataStream.WriteByte(cTileMapCommandCache[awaitingCount] or (awaitingCacheIdx shl 1));
      end;
  end;

begin
  for j := 0 to High(tmiCache) do
  begin
    tmiCache[j].UsedCount := 0;
    tmiCache[j].RawTMI := j;
  end;

  for y := 0 to cTileMapHeight - 1 do
    for x := 0 to cTileMapWidth - 1 do
    begin
      tmi := @AFrame^.TileMap[y, x];
      rawTMI := AFrame^.TilesIndexes[tmi^.FrameTileIndex].VramIndex;
      if tmi^.HMirror then rawTMI := rawTMI or $200;
      if tmi^.VMirror then rawTMI := rawTMI or $400;
      if tmi^.SpritePal then rawTMI := rawTMI or $800;
      rawTMIs[x + y * cTileMapWidth] := rawTMI;
      Inc(tmiCache[rawTMI].UsedCount);
    end;

  QuickSort(tmiCache[0], 0, High(tmiCache), SizeOf(tmiCache[0]), @CompareTMICache);

  for j := 0 to cTileMapCacheSize div 2 - 1 do
  begin
    k := j * 2;

    // 2:3 compression: high nibble b / high nibble a / low byte a / low byte b
    ADataStream.WriteByte(((tmiCache[k + 1].RawTMI shr 8) shl 4) or (tmiCache[k].RawTMI shr 8));
    ADataStream.WriteByte(tmiCache[k].RawTMI and $ff);
    ADataStream.WriteByte(tmiCache[k + 1].RawTMI and $ff);
  end;

  awaitingCacheIdx := cTileMapCacheSize;
  awaitingCount := 0;
  skipCount := 0;
  for j := 0 to cTileMapSize - 1 do
  begin
    smoothed := AFrame^.TileMap[j div cTileMapWidth, j mod cTileMapWidth].Smoothed;
    rawTMI := rawTMIs[j];

    tmiCacheIdx := -1;
    for k := 0 to cTileMapCacheSize -1 do
      if tmiCache[k].RawTMI = rawTMI then
      begin
        tmiCacheIdx := k;
        Break;
      end;
    if tmiCacheIdx = -1  then
      tmiCacheIdx := -rawTMI;

    if ASkipFirst then
    begin
      if smoothed and (skipCount < cTileMapMaxSkip) then
      begin
        DoTilemapTileCommand(True, False);

        Inc(skipCount);

        awaitingCacheIdx := cTileMapCacheSize;
        awaitingCount := 0;
      end
      else
      begin
        DoTilemapTileCommand(False, True);

        if tmiCacheIdx = awaitingCacheIdx then
        begin
          Inc(awaitingCount);

          if awaitingCount >= cTileMapMaxRepeat[awaitingCacheIdx < 0] then
          begin
            DoTilemapTileCommand(True, False);

            awaitingCacheIdx := cTileMapCacheSize;
            awaitingCount := 0;
          end;
        end
        else
        begin
          DoTilemapTileCommand(True, False);

          awaitingCacheIdx := tmiCacheIdx;
          awaitingCount := 1;
        end;
      end;
    end
    else
    begin
      if tmiCacheIdx = awaitingCacheIdx then
      begin
        Inc(awaitingCount);

        if awaitingCount >= cTileMapMaxRepeat[awaitingCacheIdx < 0] then
        begin
          DoTilemapTileCommand(True, False);

          awaitingCacheIdx := cTileMapCacheSize;
          awaitingCount := 0;
        end;
      end
      else
      begin
        DoTilemapTileCommand(True, False);

        if smoothed and (skipCount < cTileMapMaxSkip) then
        begin
          Inc(skipCount);

          awaitingCacheIdx := cTileMapCacheSize;
          awaitingCount := 0;
        end
        else
        begin
          DoTilemapTileCommand(False, True);

          awaitingCacheIdx := tmiCacheIdx;
          awaitingCount := 1;
        end;
      end;
    end;
  end;

  DoTilemapTileCommand(True, True);

  ADataStream.WriteByte(cTileMapTerminator);
end;

procedure TMainForm.BuildTileCacheLUT(var TileCacheLUT: TIntegerDynArray2; AFrameIdx: Integer);
var
  i, j, x, y: Integer;
begin
  SetLength(TileCacheLUT, Length(FFrames), Length(FTiles));
  for i := 0 to High(FFrames) do
  begin
    if (AFrameIdx >= 0) and (AFrameIdx <> i) then
      Continue;

    FillDWord(TileCacheLUT[i, 0], Length(FTiles), DWORD(MaxInt));
  end;

  for i := 0 to High(FFrames) do
  begin
    if (AFrameIdx >= 0) and (AFrameIdx <> i) then
      Continue;

    for j := High(FFrames) downto i do
      for y := (cTileMapHeight - 1) downto 0 do
        for x := (cTileMapWidth - 1) downto 0 do
          TileCacheLUT[i, FFrames[j].TileMap[y, x].TileIdx] := j * cTileMapSize + y * cTileMapWidth + x;
  end;
end;

procedure TMainForm.InitTileCache(var TileCache: TTileCache);
var
  i: Integer;
begin
  for i := 0 to High(TTileCache) do
  begin
    TileCache[i].TileIdx := -1;
    TileCache[i].Frame := IfThen((i mod (Length(TTileCache) div 2)) < (cTileMapSize * 2 div cTileSize + 1), MaxInt, -1); // avoid tile addresses within tilemaps
  end;
end;

function TMainForm.PrepareVRAMTileIndexes(AFrameIdx: Integer; var ATileIndexes: TTilesIndexes; var TileCache: TTileCache;
  const TileCacheLUT: TIntegerDynArray2): Integer;

  function EnsureTileInCache(ATileIdx: Integer; out ANeedsUpload: Boolean): Integer;
  var
    i, bestIdx, best, cur: Integer;
  begin
    Result := -1;
    ANeedsUpload := False;

    // Was in cache already?

    for i := 0 to High(TileCache) do
      if (TileCache[i].Frame <> MaxInt) and (TileCache[i].TileIdx = ATileIdx) then
      begin
        TileCache[i].Frame := AFrameIdx;
        Exit(i);
      end;

    ANeedsUpload := True;

    // Free cache index?

    for i := 0 to High(TileCache) do
      if (TileCache[i].Frame <> MaxInt) and (TileCache[i].TileIdx < 0) then
      begin
        TileCache[i].TileIdx := ATileIdx;
        TileCache[i].Frame := AFrameIdx;
        Exit(i);
      end;

    // Use the Belady optimal cache algorithm (replace the item that will be used the furthest into the future)

    bestIdx := -1;
    best := -1;
    for i := 0 to High(TileCache) do
    begin
      if TileCache[i].Frame >= AFrameIdx - 1 then  // don't choose an index that hasn't been displayed yet
        Continue;

      cur := TileCacheLUT[TileCache[i].Frame, TileCache[i].TileIdx];

      if cur > best then
      begin
        best := cur;
        bestIdx := i;
        if best = MaxInt then // can't find better
          Break;
      end;
    end;

    Assert(bestIdx >= 0, 'Frame ' + IntToStr(AFrameIdx) + ' used too many tiles!');

    TileCache[bestIdx].TileIdx := ATileIdx;
    TileCache[bestIdx].Frame := AFrameIdx;
    Exit(bestIdx);
  end;

var
  i, idx: Integer;
  needsUpload: Boolean;
begin
  Result := 0;

  for i := 0 to High(ATileIndexes) do
  begin
    idx := EnsureTileInCache(ATileIndexes[i].RomIndex, needsUpload);
    ATileIndexes[i].VramIndex := idx;
    ATileIndexes[i].InVRAM := True;
    if needsUpload then
    begin
      ATileIndexes[i].VramIndex := idx;
      ATileIndexes[i].InVRAM := False;
      Inc(Result);
    end;
  end;

  //WriteLn('FrmIdx: ', AFrameIdx, #9'UploadCnt: ', Result);
end;

procedure TMainForm.PrefetchVRAMTileIndexes(AFrame: PFrame; AUploadLimit: Integer; var TileCache: TTileCache;
  var TileCacheLUT: TIntegerDynArray2);
var
  i, j, ulCnt, cnt, pos, TPF: Integer;
  found: Boolean;
  frm: PFrame;
begin
  TPF := GetFrameTileCount(AFrame, True, True);

  if TPF < cMaxTilesPerFrame then
  begin
    ulCnt := 0;
    frm := AFrame;
    for i := 0 to High(frm^.TilesIndexes) do
      if not frm^.TilesIndexes[i].InVRAM then
        Inc(ulCnt);

    if ((ulCnt < AUploadLimit) or (AUploadLimit < 0)) and (AFrame^.Index < High(FFrames)) then
    begin
      cnt := 0;
      frm := @FFrames[AFrame^.Index + 1];
      for i := 0 to High(frm^.TilesIndexes) do
        if not frm^.TilesIndexes[i].InVRAM then // not already in VRAM?
          Inc(cnt);

      pos := High(AFrame^.TilesIndexes);
      SetLength(AFrame^.TilesIndexes, pos + 1 + length(frm^.TilesIndexes));

      if (cnt >= AUploadLimit) or (AUploadLimit < 0) then
      begin
        for i := 0 to High(frm^.TilesIndexes) do
          if not frm^.TilesIndexes[i].InVRAM then // not already in VRAM?
          begin
            // prevent 2 uploads in the same cache index
            found := False;
            for j := 0 to pos do
              if AFrame^.TilesIndexes[j].VramIndex = frm^.TilesIndexes[i].VramIndex then
              begin
                found := True;
                Break;
              end;
            if found then
              Continue;

            Inc(pos);
            AFrame^.TilesIndexes[pos] := frm^.TilesIndexes[i];
            frm^.TilesIndexes[i].InVRAM := True;
            Inc(ulCnt);
            Dec(cnt);
            Inc(TPF);

            if (ulCnt >= cnt) or (TPF >= cMaxTilesPerFrame) then
              Break;
          end;

        //WriteLn('FrmIdx: ', AFrame^.Index, #9'NewUploadCnt: ', ulCnt, #9'(balancing)');
      end;

      SetLength(AFrame^.TilesIndexes, pos + 1);
    end;
  end;
end;

procedure TMainForm.Save(ADataStream, ASoundStream: TStream);
var pp, i, j, x, y, frameStart, avgUploadCnt, prevUploadCnt, maxUploadCnt, iter: Integer;
    palpx, sb: Byte;
    prevKF: PKeyFrame;
    SkipFirst, b: Boolean;
    tilesPlanes: array[0..cTileWidth - 1, 0..3] of Byte;
    TMStream: array[Boolean] of TMemoryStream;

    TileCache: TTileCache;
    TileCacheLUT: TIntegerDynArray2;
begin
  // prepare belady cache

  avgUploadCnt := 0;
  InitTileCache(TileCache);
  for i := 0 to High(FFrames) do
  begin
    BuildTileCacheLUT(TileCacheLUT, i);
    avgUploadCnt += PrepareVRAMTileIndexes(i, FFrames[i].TilesIndexes, TileCache, TileCacheLUT);
  end;
  avgUploadCnt := (avgUploadCnt - 1) div length(FFrames) + 1;
  WriteLn('AvgUploadCnt: ', avgUploadCnt);

  maxUploadCnt := MaxInt;
  iter := 0;
  repeat
    prevUploadCnt := maxUploadCnt;
    InitTileCache(TileCache);
    for i := High(FFrames) - 1 downto 0 do
    begin
      PrefetchVRAMTileIndexes(@FFrames[i], -1, TileCache, TileCacheLUT);
    end;

    maxUploadCnt := 0;
    for i := 0 to High(FFrames) do
    begin
      BuildTileCacheLUT(TileCacheLUT, i);
      maxUploadCnt := max(maxUploadCnt, PrepareVRAMTileIndexes(i, FFrames[i].TilesIndexes, TileCache, TileCacheLUT));
    end;

    WriteLn('MaxUploadCnt: ', maxUploadCnt);
    Inc(iter);
  until maxUploadCnt >= prevUploadCnt;

  // leave the size of one tile for index

  for x := 0 to cTileWidth - 1 do
    ADataStream.WriteDWord(0);

  // tiles

  for i := 0 to High(FTiles) do
  begin
    FillByte(tilesPlanes[0, 0], Sizeof(tilesPlanes), 0);
    for y := 0 to cTileWidth - 1 do
    begin
      for x := 0 to cTileWidth - 1 do
      begin
        palpx := FTiles[i]^.PalPixels[y, x];
        tilesPlanes[y, 0] := tilesPlanes[y, 0] or (((palpx and 1) shl 7) shr x);
        tilesPlanes[y, 1] := tilesPlanes[y, 1] or (((palpx and 2) shl 6) shr x);
        tilesPlanes[y, 2] := tilesPlanes[y, 2] or (((palpx and 4) shl 5) shr x);
        tilesPlanes[y, 3] := tilesPlanes[y, 3] or (((palpx and 8) shl 4) shr x);
      end;
      for x := 0 to 3 do
        ADataStream.WriteByte(tilesPlanes[y, x]);
    end;
  end;

  WriteLn('Total tiles size:'#9, ADataStream.Position);
  pp := ADataStream.Position;


  // index

  frameStart := ADataStream.Position + cBankSize;
  i := ADataStream.Position;
  ADataStream.Position := 0;
  ADataStream.WriteWord(Length(FFrames));
  ADataStream.WriteWord(frameStart div cBankSize);
  ADataStream.WriteWord(frameStart mod cBankSize);
  ADataStream.Position := i;

  prevKF := nil;
  sb := 0;
  for i := 0 to High(FFrames) do
  begin
    // palette

    if FFrames[i].KeyFrame <> prevKF then
    begin
      ADataStream.WriteByte(cTilePaletteSize * 2);
      for b := False to True do
        for j := 0 to cTilePaletteSize - 1 do
          ADataStream.WriteByte(FFrames[i].KeyFrame^.PaletteIndexes[b, j]);
    end
    else
    begin
      ADataStream.WriteByte(0);
    end;

    // tiles indexes

    SaveTileIndexes(ADataStream, @FFrames[i]);

    // tilemap

    for SkipFirst := False to True do
    begin
      TMStream[SkipFirst] := TMemoryStream.Create;
      SaveTileMap(TMStream[SkipFirst], @FFrames[i], i, SkipFirst);
    end;

    SkipFirst := True;
    if TMStream[SkipFirst].Size > TMStream[not SkipFirst].Size then
      SkipFirst := not SkipFirst;

    TMStream[SkipFirst].Position := 0;
    ADataStream.CopyFrom(TMStream[SkipFirst], TMStream[SkipFirst].Size);

    for SkipFirst := False to True do
      TMStream[SkipFirst].Free;

    // sound

    if Assigned(ASoundStream) then
    begin
      ASoundStream.Position := 2 + Floor(cFrameSoundSize * i);

      for j := 0 to ceil(cFrameSoundSize) - 1 do
        if ASoundStream.Read(sb, 1) = 1 then
          ADataStream.WriteByte(sb)
        else
          ADataStream.WriteByte($ff);
    end;

    prevKF := FFrames[i].KeyFrame;
  end;

  WriteLn('Total frames size:'#9, ADataStream.Position - pp);

  WriteLn('Total unpadded size:'#9, ADataStream.Position);

  while (ADataStream.Position + cBankSize) mod (cBankSize * 4) <> 0 do
    ADataStream.WriteByte($ff);

  WriteLn('Total padded size:'#9, ADataStream.Position);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  r,g,b,i,mx,mn,col,prim_col,sr: Integer;
begin
  FFrameTilingMode := pvsWeightedDCT;
  FGlobalTilingMode := pvsWeightedDCT;

  IdleTimer.Interval := 20 * cRefreshRateDiv;
  IdleTimer.Enabled := True;

  Constraints.MinWidth := Width;
  Constraints.MinHeight := Height;

  InitializeCriticalSection(FCS);

  FormatSettings.DecimalSeparator := '.';

{$ifdef DEBUG}
  //ProcThreadPool.MaxThreadCount := 1;
  btnDebug.Visible := True;
{$else}
  ProcThreadPool.MaxThreadCount := max(1, ProcThreadPool.MaxThreadCount - 2);
  SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS);
{$endif}

  imgSource.Picture.Bitmap.Width:=CScreenWidth;
  imgSource.Picture.Bitmap.Height:=CScreenHeight;
  imgSource.Picture.Bitmap.PixelFormat:=pf32bit;

  imgDest.Picture.Bitmap.Width:=CScreenWidth;
  imgDest.Picture.Bitmap.Height:=CScreenHeight;
  imgDest.Picture.Bitmap.PixelFormat:=pf32bit;

  imgTiles.Picture.Bitmap.Width:=CScreenWidth;
  imgTiles.Picture.Bitmap.Height:=CScreenHeight * 2;
  imgTiles.Picture.Bitmap.PixelFormat:=pf32bit;

  imgPalette.Picture.Bitmap.Width := cTilePaletteSize;
  imgPalette.Picture.Bitmap.Height := cPaletteCount;
  imgPalette.Picture.Bitmap.PixelFormat:=pf32bit;

  cbxYilMixChange(nil);
  chkUseTKChange(nil);

  sr := (1 shl cBitsPerComp) - 1;

  for i := 0 to cTotalColors - 1 do
  begin
    col :=
       ((((i shr (cBitsPerComp * 0)) and sr) * 255 div sr) and $ff) or //R
      (((((i shr (cBitsPerComp * 1)) and sr) * 255 div sr) and $ff) shl 8) or //G
      (((((i shr (cBitsPerComp * 2)) and sr) * 255 div sr) and $ff) shl 16);  //B

    prim_col :=
      (((i shr 1) and 1) * 255) or //R
      ((((i shr 3) and 1) * 255) shl 8) or //G
      ((((i shr 5) and 1) * 255) shl 16);  //B

    FColorMap[i] := col;
    FColorMapImportance[i] := Ord(col = prim_col);
  end;

  for i := 0 to cTotalColors - 1 do
  begin
    col := FColorMap[i];
    r := col and $ff;
    g := (col shr 8) and $ff;
    b := col shr 16;

    FColorMapLuma[i] := (r*cRedMul + g*cGreenMul + b*cBlueMul) div cLumaDiv;

    mx := MaxIntValue([r, g, b]);
    mn := MinIntValue([r, g, b]);

    if r = mx then FColorMapHue[i] := iDiv0((g - b) shl 7, mx - mn);
    if g = mx then FColorMapHue[i] := iDiv0((b - r) shl 7, mx - mn);
    if b = mx then FColorMapHue[i] := iDiv0((r - g) shl 7, mx - mn);
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  DeleteCriticalSection(FCS);

  ClearAll;
end;

initialization
  InitLuts;
end.

