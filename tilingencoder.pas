unit tilingencoder;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$TYPEDADDRESS ON}
{$CODEALIGN LOCALMIN=16}
{$PACKSET 1}

{$define ASM_DBMP}

interface

uses
  windows, Classes, SysUtils, strutils, types, Math, FileUtil, typinfo, zstream, IniFiles, Graphics,
  IntfGraphics, FPimage, FPCanvas, FPWritePNG, GraphType, fgl, MTProcs, bufstream,
  tbbmalloc, extern, utils, kmodes, powell, sle;
type
  TEncoderStep = (esAll = -1, esLoad = 0, esPredict, esReduce, esPreparePalettes, esDither, esReindex1, esReconstruct, esReindex2, esSave);
  TKeyFrameReason = (kfrNone, kfrManual, kfrLength, kfrDecorrelation, kfrEuclidean);
  TRenderPage = (rpNone, rpInput, rpOutput, rpTilesPalette);
  TPsyVisMode = (pvsDCT, pvsWeightedDCT, pvsWavelets, pvsSpeDCT, pvsWeightedSpeDCT);

const
  cEncoderStepLen: array[TEncoderStep] of Integer = ({esAll} -1, {esLoad} 5, {esPredict} 1, {esReduce} 3, {esPreparePalettes} 4, {esDither} 2, {esReindex1} 3, {esReconstruct} 2, {esReindex2} 3, {esSave} 1);

type
  // GliGli's TileMotion header structs and commands

  TGTMHeader = packed record
    FourCC: array[0..3] of AnsiChar; // ASCII "GTMv"
    RIFFSize: Cardinal;
    WholeHeaderSize: Cardinal; // including TGTMKeyFrameInfo and all
    EncoderVersion: Cardinal;
    FramePixelWidth: Cardinal;
    FramePixelHeight: Cardinal;
    KFCount: Cardinal;
    FrameCount: Cardinal;
    AverageBytesPerSec: Cardinal;
    KFMaxBytesPerSec: Cardinal;
    PSNRHVS: Cardinal; // in 1 / 1000000 of dB
  end;

  TGTMKeyFrameInfo = packed record
    FourCC: array[0..3] of AnsiChar; // ASCII "GTMk"
    RIFFSize: Cardinal;
    KFIndex: Cardinal;
    FrameIndex: Cardinal;
    RawSize: Cardinal;
    CompressedSize: Cardinal;
    TimeCodeMillisecond: Cardinal;
    PSNRHVS: Cardinal; // in 1 / 1000000 of dB
  end;

  // Commands Description:
  // =====================
  //
  // PredictedTileOffsets6x6:          data -> none; commandBits -> y offset (6 bits); x offset (6 bits)
  // PredictedTileOffsets8x8:          data -> y offset (8 bits); x offset (8 bits); commandBits -> none (10 bits); backbuffer offset - 1 (2 bits)
  // PredictedFm1Fm2Blend6x6:          data -> none; commandBits -> alpha additive weight (256 + w) (6 bits); frame -2 to frame -1 alpha (6 bits)
  // PredictedOffsetBlock0x0:          data -> none; commandBits -> block size in tiles - 1 (12 bits)
  // GlobalTile10:                     data -> none; commandBits -> global tile index (10 bits); V mirror (1 bit); H mirror (1 bit)
  // KeyFrmTile10:                     data -> none; commandBits -> keyframe tile index (10 bits); V mirror (1 bit); H mirror (1 bit)
  // GlobalTile16:                     data -> global tile index (16 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // KeyFrmTile16:                     data -> keyframe tile index (16 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // GlobalTile32:                     data -> global tile index (32 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // KeyFrmTile32:                     data -> keyframe tile index (32 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  //
  // (insert new commands here...)
  //
  // FrameEnd:                         data -> none; commandBits -> none (11 bits); keyframe end (1 bit)
  // LoadPalette:                      data -> palette index (16 bits); { RGBA bytes (32bits) } * indexes count; commandBits -> palette format (0: RGBA32) (6 bits); indexes count per palette - 1 (6 bits)
  // TileSet:                          data -> start tile (32 bits); end tile (32 bits); { palette index (16 bits) } * count; { indexes per pixel (64 bytes) } * count; commandBits -> none (11 bits); is keyframe tileset (1 bit)
  // SetDimensions:                    data -> width in tiles (32 bits); height in tiles (32 bits); frame length in nanoseconds (32 bits) (2^32-1: still frame); global tile count (32 bits); maximum local tile count (32 bits); commandBits -> none (12 bits)
  // ExtendedCommand:                  data -> following bytes count (32 bits); custom commands, proprietary extensions, ...; commandBits -> extended command index (12 bits)

  TGTMCommand = (
    gtPredictedTileOffsets6x6 = 0,
    gtPredictedTileOffsets8x8 = 1,
    gtPredictedFm1Fm2Blend6x6 = 2,
    gtPredictedOffsetBlock0x0 = 3,
    gtGlobalTile10 = 4,
    gtKeyFrmTile10 = 5,
    gtGlobalTile16 = 6,
    gtKeyFrmTile16 = 7,
    gtGlobalTile32 = 8,
    gtKeyFrmTile32 = 9,

    gtFrameEnd = 11,
    gtLoadPalette = 12,
    gtTileSet = 13,
    gtSetDimensions = 14,
    gtExtendedCommand = 15
  );

  PIntegerDynArray = ^TIntegerDynArray;
  PBoolean = ^Boolean;
  PPBoolean = ^PBoolean;

  TIntegerList=specialize TFPGList<Integer>;
  TFloatFloatFunction = function(x: TFloat; Data: Pointer): TFloat;

  PTile = ^TTile;
  PPTile = ^PTile;

  PTileDynArray = array of PTile;
  PTileDynArray2 = array of PTileDynArray;

  TRGBPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Integer;
  TPalPixels = array[0..(cTileWidth - 1),0..(cTileWidth - 1)] of Byte;
  PRGBPixels = ^TRGBPixels;
  PPalPixels = ^TPalPixels;

  TCpnPixels = array[0..cColorCpns-1, 0..cTileWidth-1,0..cTileWidth-1] of Single;
  TCpnPixelsDouble = array[0..cColorCpns-1, 0..cTileWidth-1,0..cTileWidth-1] of Double;

  PCpnPixels = ^TCpnPixels;
  TPCpnPixelsDynArray = array of PCpnPixels;

  ETilingEncoderGTMReloadError = class(Exception);

  { TTile }

  TTile = packed record // /!\ update TTileHelper.CopyFrom each time this structure is changed /!\
    UseCount: Cardinal;
    TmpIndex, MergeIndex: Integer;
    PalIdx: Integer;
    Flags: set of (tfActive, tfHasRGBPixels, tfHasPalPixels, tfHMirror_Initial, tfVMirror_Initial);
  end;

  { TTileHelper }

  TTileHelper = record helper for TTile
  private
    function GetActive: Boolean;
    function GetHasPalPixels: Boolean;
    function GetHasRGBPixels: Boolean;
    function GetHMirror_Initial: Boolean;
    function GetVMirror_Initial: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure SetHasPalPixels(AValue: Boolean);
    procedure SetHasRGBPixels(AValue: Boolean);
    procedure SetHMirror_Initial(AValue: Boolean);
    procedure SetVMirror_Initial(AValue: Boolean);
  public
    function GetRGBPixelsPtr: PRGBPixels;
    function GetPalPixelsPtr: PPalPixels;

    function GetRGBPixels(y, x: Integer): Integer;
    function GetPalPixels(y, x: Integer): Byte;
    procedure SetRGBPixels(y, x: Integer; value: Integer);
    procedure SetPalPixels(y, x: Integer; value: Byte);

    class function Array1DNew(x: Integer; ARGBPixels, APalPixels: Boolean): PTileDynArray; static;
    class procedure Array1DDispose(var AArray: PTileDynArray); static;
    class procedure Array1DRealloc(var AArray: PTileDynArray; ANewX: integer); static;
    class function New(ARGBPixels, APalPixels: Boolean): PTile; static;
    class procedure Dispose(var ATile: PTile); static;
    procedure CopyFrom(const ATile: TTile);
    procedure CopyPalPixelsFrom(const ATile: TTile);
    procedure CopyPalPixels(const APalPixels: TPalPixels); overload;
    procedure CopyPalPixels(const APalPixels: TByteDynArray); overload;
    procedure CopyRGBPixels(const ARGBPixels: TRGBPixels); overload;
    procedure CopyRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer); overload;
    procedure BlendRGBPixels(const AM1Buffer, AM2Buffer: TIntegerDynArray2; AY, AX: Integer; AAlpha: Byte; AWeight: ShortInt);
    procedure BlitPalPixels(const AFrameBuffer: TIntegerDynArray2; const APalette: TIntegerDynArray; AVMirror, AHMirror: Boolean; AY, AX: Integer);
    procedure BlitRGBPixels(const AFrameBuffer: TIntegerDynArray2; AVMirror, AHMirror: Boolean; AY, AX: Integer);
    procedure ClearPalPixels;
    procedure ClearRGBPixels;
    procedure ClearPixels;
    procedure ExtractPalPixels(AArray: PFloat);
    procedure LoadPalPixels(AArray: PFloat);
    function ComparePalPixelsTo(const ATile: TTile): Integer;
    function CompareRGBPixelsTo(const ATile: TTile): Integer;
    function CompareRGBColorsTo(const ATile: TTile): Double;

    property RGBPixels[y, x: Integer]: Integer read GetRGBPixels write SetRGBPixels;
    property PalPixels[y, x: Integer]: Byte read GetPalPixels write SetPalPixels;

    property Active: Boolean read GetActive write SetActive;
    property HasRGBPixels: Boolean read GetHasRGBPixels write SetHasRGBPixels;
    property HasPalPixels: Boolean read GetHasPalPixels write SetHasPalPixels;
    property HMirror_Initial: Boolean read GetHMirror_Initial write SetHMirror_Initial;
    property VMirror_Initial: Boolean read GetVMirror_Initial write SetVMirror_Initial;
  end;

  { TTileMapItem }

  TTileMapItem = packed record
    TileIdx: Integer; // 4
    Error: Cardinal; // 4
    Attrs: record case Boolean of // 3 * 1
      False: (MotionX, MotionY: ShortInt; MotionBackBufferOffset: Byte);
      True: (BlendAlpha: Byte; BlendWeight: ShortInt; Dummy: Byte);
    end;
    Flags: set of (tmfHMirror, tmfVMirror, tmfPredicted, tmfBlended); // 1
  end;

{$if SizeOf(TTileMapItem) <> 12}
  {$error misaligned SizeOf(TTileMapItem) !}
{$endif}

  PTileMapItem = ^TTileMapItem;

  TTileMapItems = array of TTileMapItem;
  TTileMapItems2 = array of TTileMapItems;

  { TTileMapItemHelper }

  TTileMapItemHelper = record helper for TTileMapItem
  private
    function GetHMirror: Boolean;
    function GetIsBlended: Boolean;
    function GetIsSmoothed: Boolean;
    function GetVMirror: Boolean;
    procedure SetHMirror(AValue: Boolean);
    procedure SetIsBlended(AValue: Boolean);
    procedure SetVMirror(AValue: Boolean);
    function GetIsPredicted: Boolean;
    procedure SetIsPredicted(AValue: Boolean);
  public
    procedure Reset(AKeepMirrors: Boolean);

    property IsPredicted: Boolean read GetIsPredicted write SetIsPredicted;
    property IsBlended: Boolean read GetIsBlended write SetIsBlended;
    property IsSmoothed: Boolean read GetIsSmoothed;
    property HMirror: Boolean read GetHMirror write SetHMirror;
    property VMirror: Boolean read GetVMirror write SetVMirror;
  end;

  { TTilingDataset }

  TTilingDataset = record
    KNNSize: Integer;
    Dataset: TSmallIntDynArray2;
    ANN: PANNkdtree;
  end;

  PTilingDataset = ^TTilingDataset;

  { TMixingPlan }

  TMixingPlan = record
    // static
    LumaPal: array of Integer;
    Remap: array of Byte;
    Y2Palette: array of array[0..3] of Integer;
    Y2MixedColors: Integer;
  end;

  TTilingEncoder = class;
  TKeyFrame = class;

  { TPalette }

  TPalette = record
    UseCount: Integer;
    PalIdx_Initial: Integer;
    PaletteRGB: TIntegerDynArray;
    MixingPlan: TMixingPlan;
    TileCount, TileOffset: Integer;
    CMPal: TCountIndexList;
  end;

  TPaletteArray = array of TPalette;

  { TFrameBuffer }

  TFrameBuffer = class
    FrameBuffer: TIntegerDynArray3;
    CurBufferIndex: Integer;

    constructor Create(ABufferCount, AHeight, AWidth: Integer);

    function GetBuffer(ARelativeIndex: Integer): TIntegerDynArray2; overload;
    function GetBuffer: TIntegerDynArray2; overload;
    procedure AdvanceFrame;
  end;

  { TDCTBuffer }

  TDCTBuffer = class
    DCTBuffer: TDCTDynArray2;
    CurBufferIndex: Integer;

    constructor Create(ABufferCount, ASize: Integer);

    function GetBuffer(ARelativeIndex: Integer): TDCTDynArray; overload;
    function GetBuffer: TDCTDynArray; overload;
    procedure AdvanceFrame;
  end;

  { TFrame }

  TFrame = class
  const
    CFrameTilesHaveRGBPixels = True;
    CFrameTilesHavePalPixels = False;
    CFrameTileSize = SizeOf(TTile) + SizeOf(TRGBPixels) * Ord(CFrameTilesHaveRGBPixels) + SizeOf(TPalPixels) * Ord(CFrameTilesHavePalPixels);
  public
    Encoder: TTilingEncoder;
    PKeyFrame: TKeyFrame;
    Index: Integer;

    TileMap: TTileMapItems2;

    InterframeCorrelationData: TFloatDynArray;
    InterframeCorrelation: TFloat; // with previous frame
    InterframeCorrelationEvent: THandle;
    LoadFromImageFinishedEvent: THandle;

    FrameTiles: PTileDynArray;
    FrameTilesRefCount: Integer;
    FrameTilesEvent: THandle;
    FrameTilesLock: TSpinlock;
    CompressedFrameTiles: TMemoryStream;

    IntraReducedTiles: PTileDynArray;
    IntraReducedTileIndexes: TIntegerDynArray2;

    constructor Create(AParent: TTilingEncoder; AIndex: Integer);
    destructor Destroy; override;

    function PrepareInterFrameData: TFloatDynArray;
    procedure AsyncLoadFromImage;

    procedure CompressFrameTiles;
    procedure AcquireFrameTiles;
    procedure ReleaseFrameTiles;

    function GetUsedTileCount: Integer;
    function GetUnpredictedTileCount: Integer;
    procedure ResetTileMap(AKeepMirrors: Boolean);

    function PowellBlend(const x: TVector; data: Pointer): TScalar;
    procedure GetPredictExtents(ARadius, ADY, ADX: Integer; out oxmn, oxmx, oymn, oymx: Integer);

    procedure PrepareDCTs(const ADCTs: TDCTDynArray; const ABuffer: TIntegerDynArray2);
    function PredictTileBlending(AUnipolar: Boolean; ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; AFrameBuffer: TFrameBuffer): Cardinal;
    function PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Cardinal;
    function PredictTileIntra(ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Cardinal;

    // processes

    procedure LoadFromImage(AImageWidth, AImageHeight: Integer; AImage: PInteger);
    procedure IntraReduce(ATargetTileCount: Integer);
    procedure Predict(ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer; AFrameBuffer: TFrameBuffer);
    procedure Reconstruct(ARadius: Integer; AFrameBuffer: TFrameBuffer);
    procedure DirectBlit(const ABuffer: TIntegerDynArray2);
  end;

  TFrameArray =  array of TFrame;

  { TKeyFrame }

  TKeyFrame = class
    Encoder: TTilingEncoder;
    Index, StartFrame, EndFrame, FrameCount: Integer;
    Reason: TKeyFrameReason;

    ReconstructFramesLeft: Integer;
    ReconstructErrCml: UInt64;
    ReconstructLock: TSpinlock;
    ReconstructPSNR: Double;

    procedure LogPSNR;

    constructor Create(AParent: TTilingEncoder; AIndex, AStartFrame, AEndFrame: Integer);
    destructor Destroy; override;
  end;

  TKeyFrameArray =  array of TKeyFrame;

  TTilingEncoderProgressEvent = procedure(ASender: TTilingEncoder; APosition, AMax: Integer; AHourGlass: Boolean) of object;

  { TTilingEncoder }

  TTilingEncoder = class
  private
    // encoder state variables

    FCS: TRTLCriticalSection;
    FKeyFramesLeft: Integer;
    FReconstructPSNR: Double;

    FGamma: array[0..1] of TFloat;
    FGammaCorLut: array[-1..1, 0..High(Byte)] of TFloat;
    FVecInv: array[0..256 * 4 - 1] of Cardinal;
    FDCTLut:array[Boolean {Special?}, 0..cUnrolledDCTSize - 1] of TFloat;
    FDCTLutDouble:array[Boolean {Special?}, 0..cUnrolledDCTSize - 1] of Double;
    FInvDCTLutDouble:array[0..cUnrolledDCTSize - 1] of Double;

    FTiles: PTileDynArray;
    FKeyFrames: TKeyFrameArray;
    FFrames: TFrameArray;
    FPalettes: TPaletteArray;

    FTilingDataset: PTilingDataset;

    // video properties

    FLoadedInputPath: String;
    FTileMapWidth: Integer;
    FTileMapHeight: Integer;
    FTileMapSize: Integer;
    FScreenWidth: Integer;
    FScreenHeight: Integer;
    FFramesPerSecond: Double;

    // settings

    FInputFileName: String;
    FOutputFileName: String;
    FStartFrame: Integer;
    FFrameCountSetting: Integer;
    FScaling: Double;
    FPaletteSize: Integer;
    FPaletteCount: Integer;
    FMotionPredictRadius: Integer;
    FMotionPredictMaxBufferedFrames: Integer;
    FDitheringMode: TPsyVisMode;
    FDitheringUseThomasKnoll: Boolean;
    FDitheringYliluoma2MixedColors: Integer;
    FGlobalTilingUseTargetPSNR: Boolean;
    FGlobalTilingTargetPSNR: Double;
    FGlobalTilingTileCount: Integer;
    FGlobalTilingQualityBasedTileCount: Double;
    FShotTransMaxSecondsPerKF: Double;
    FShotTransMinSecondsPerKF: Double;
    FShotTransCorrelLoThres: Double;

    // GUI state variables

    FRenderPredicted: Boolean;
    FRenderFrameIndex: Integer;
    FRenderPrevFrameIndex: Integer;
    FRenderPage: TRenderPage;
    FRenderPsychoVisualQuality: Double;
    FRenderTitleText: String;
    FRenderUseGamma: Boolean;
    FRenderMirrored: Boolean;
    FRenderPaletteIndex: Integer;
    FRenderPlaying: Boolean;
    FRenderOutputDithered: Boolean;
    FRenderTilePage: Integer;
    FRenderFrameBuffer: TFrameBuffer;
    FOutputBitmap: TBitmap;
    FInputBitmap: TBitmap;
    FPaletteBitmap: TBitmap;
    FTilesBitmap: TBitmap;
    FOnProgress: TTilingEncoderProgressEvent;
    FProgressStep: TEncoderStep;
    FProgressAllStartTime, FProgressProcessStartTime, FProgressPrevTime: Int64;

    FProgressSyncPos, FProgressSyncMax: Integer;
    FProgressSyncHG: Boolean;

    function GetFrameCount: Integer;
    function GetKeyFrameCount: Integer;
    function GetMaxThreadCount: Integer;
    function GetTiles: PTileDynArray;
    function GetRenderGammaValue: Double;
    procedure SetDitheringYliluoma2MixedColors(AValue: Integer);
    procedure SetFrameCountSetting(AValue: Integer);
    procedure SetFramesPerSecond(AValue: Double);
    procedure SetGlobalTilingQualityBasedTileCount(AValue: Double);
    procedure SetMaxThreadCount(AValue: Integer);
    procedure SetPaletteCount(AValue: Integer);
    procedure SetPaletteSize(AValue: Integer);
    procedure SetMotionPredictRadius(AValue: Integer);
    procedure SetMotionPredictMaxBufferedFrames(AValue: Integer);
    procedure SetRenderFrameIndex(AValue: Integer);
    procedure SetRenderGammaValue(AValue: Double);
    procedure SetRenderPaletteIndex(AValue: Integer);
    procedure SetRenderTilePage(AValue: Integer);
    procedure SetGlobalTilingTargetPSNR(AValue: Double);
    procedure SetGlobalTilingTileCount(AValue: Integer);
    procedure SetScaling(AValue: Double);
    procedure SetShotTransCorrelLoThres(AValue: Double);
    procedure SetShotTransMaxSecondsPerKF(AValue: Double);
    procedure SetShotTransMinSecondsPerKF(AValue: Double);
    procedure SetStartFrame(AValue: Integer);

    function PearsonCorrelation(const x: TFloatDynArray; const y: TFloatDynArray): TFloat;

    function GetSettings: AnsiString;
    procedure SetSettings(ASettings: AnsiString);
    procedure ProgressRedraw(ASubStepIdx: Integer; AReason: String; AProgressStep: TEncoderStep = esAll; AThread: TThread = nil);
    procedure SyncProgress;

    function GammaCorrect(lut: Integer; x: Byte): TFloat; inline;
    function GammaUncorrect(lut: Integer; x: TFloat): Byte; inline;

    generic procedure WaveletGS<T, PT>(Data: PT; Output: PT; dx, dy, depth: cardinal);
    generic procedure DeWaveletGS<T, PT>(wl: PT; pic: PT; dx, dy, depth: longint);

    procedure ConvertToCpnPixels(const ATile: TTile; FromPal, UseLAB, VMirror, HMirror: Boolean; const APalette: TIntegerDynArray; out ACpnPixel: TCpnPixels); inline;
    procedure ComputeCpnPixelsPsyVisFeatures(const ACpnPixel: TCpnPixels; Mode: TPsyVisMode; ColorCpns: Integer; ADCT: PDCTScalar); inline;

    procedure ComputeTilePsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; FromPal, UseLAB, VMirror, HMirror: Boolean;
     ColorCpns: Integer; const APalette: TIntegerDynArray; ADCT: PDouble); inline; overload;
    procedure ComputeInvTilePsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; UseLAB: Boolean; ColorCpns: Integer; var ATile: TTile);

    // Dithering algorithms ported from http://bisqwit.iki.fi/story/howto/dither/jy/

    class function ColorCompare(r1, g1, b1, r2, g2, b2: Int64): Int64;
    procedure PreparePlan(var Plan: TMixingPlan; const pal: array of Integer);
    procedure TerminatePlan(var Plan: TMixingPlan);
    function DeviseBestMixingPlanYliluoma(var Plan: TMixingPlan; col: Integer; var List: array of Byte): Integer;
    procedure DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: array of Byte);

    function GetTileCount(AActiveOnly: Boolean): Integer;
    procedure DitherTile(var ATile: TTile; var Plan: TMixingPlan);
    class function GetTileZoneSum(const ATile: TTile; AOnPal: Boolean; x, y, w, h: Integer): Integer;
    class procedure GetTileHVMirrorHeuristics(const ATile: TTile; AOnPal: Boolean; out AHMirror, AVMirror: Boolean);
    class procedure HMirrorTile(var ATile: TTile; APalOnly: Boolean = False);
    class procedure VMirrorTile(var ATile: TTile; APalOnly: Boolean = False);

    procedure InitLuts;
    procedure ClearAll(AKeepFrames: Boolean);
    procedure ReframeUI(AWidth, AHeight: Integer);
    procedure InitFrames(AFrameCount: Integer);
    procedure LoadInputVideo;
    procedure FindKeyFrames(AManualMode: Boolean);

    function GRPSNR(x: Double; Data: Pointer): Double;
    function SolveTileCount(ATileCount: Integer): Integer;
    function SolveAvgPSNR(AAvgPSNR: Double): Integer;
    procedure TransferTiles;

    procedure DoPalettization;
    function MinimizeOP(const x: TDoubleDynArray; data: Pointer): Double;
    procedure QuantizeUsingYakmo(APalIdx, AColorCount, APosterize: Integer);
    procedure DoQuantization(APalIdx: Integer);
    procedure OptimizePalettes;

    procedure PrepareReconstruct;
    procedure FinishReconstruct;

    procedure ReindexTiles(OnRGBPixels: Boolean);
    procedure MakeTilesUnique(OnRGBPixels: Boolean);
    procedure InitMergeTiles;
    procedure FinishMergeTiles;
    procedure MergeTiles(const TileIndexes: array of Int64; TileCount: Integer; BestIdx: Int64; NewTile: PPalPixels; NewTileRGB: PRGBPixels);

    procedure RenderFrame(AFrameIndex: Integer; APage: TRenderPage);

    procedure LoadStream(AStream: TStream);
    procedure SaveStream(AStream: TStream);

    // processes

    procedure Load;
    procedure PredictMotion;
    procedure Reduce;
    procedure PreparePalettes;
    procedure Dither;
    procedure Reconstruct;
    procedure Reindex(AStep: TEncoderStep);
    procedure Save;
  public
    // constructor / destructor

    constructor Create;
    destructor Destroy; override;

    // functions

    procedure Run(AStep: TEncoderStep = esAll);
    procedure RunRange(AStartStep, AEndStep: TEncoderStep);

    procedure Render;
    procedure GeneratePNGs(AInput: Boolean);
    procedure GenerateY4M(AFileName: String; AInput: Boolean);
    procedure SaveSettings(ASettingsFileName: String);
    procedure LoadSettings(ASettingsFileName: String);
    procedure LoadDefaultSettings;

    procedure ReloadGTM(AFileName: String);

    procedure Test;

    // encoder state variables

    property Tiles: PTileDynArray read GetTiles;
    property KeyFrames: TKeyFrameArray read FKeyFrames;
    property Frames: TFrameArray read FFrames;
    property Palettes: TPaletteArray read FPalettes;

    // video properties

    property ScreenWidth: Integer read FScreenWidth;
    property ScreenHeight: Integer read FScreenHeight;
    property FramesPerSecond: Double read FFramesPerSecond write SetFramesPerSecond;
    property TileMapWidth: Integer read FTileMapWidth;
    property TileMapHeight: Integer read FTileMapHeight;
    property TileMapSize: Integer read FTileMapSize;
    property FrameCount: Integer read GetFrameCount;
    property KeyFrameCount: Integer read GetKeyFrameCount;

    // settings

    property InputFileName: String read FInputFileName write FInputFileName;
    property OutputFileName: String read FOutputFileName write FOutputFileName;
    property StartFrame: Integer read FStartFrame write SetStartFrame;
    property FrameCountSetting: Integer read FFrameCountSetting write SetFrameCountSetting;
    property Scaling: Double read FScaling write SetScaling;
    property PaletteSize: Integer read FPaletteSize write SetPaletteSize;
    property PaletteCount: Integer read FPaletteCount write SetPaletteCount;
    property MotionPredictRadius: Integer read FMotionPredictRadius write SetMotionPredictRadius;
    property MotionPredictMaxBufferedFrames: Integer read FMotionPredictMaxBufferedFrames write SetMotionPredictMaxBufferedFrames;
    property DitheringMode: TPsyVisMode read FDitheringMode write FDitheringMode;
    property DitheringUseThomasKnoll: Boolean read FDitheringUseThomasKnoll write FDitheringUseThomasKnoll;
    property DitheringYliluoma2MixedColors: Integer read FDitheringYliluoma2MixedColors write SetDitheringYliluoma2MixedColors;
    property GlobalTilingUseTargetPSNR: Boolean read FGlobalTilingUseTargetPSNR write FGlobalTilingUseTargetPSNR;
    property GlobalTilingTargetPSNR: Double read FGlobalTilingTargetPSNR write SetGlobalTilingTargetPSNR;
    property GlobalTilingTileCount: Integer read FGlobalTilingTileCount write SetGlobalTilingTileCount;
    property GlobalTilingQualityBasedTileCount: Double read FGlobalTilingQualityBasedTileCount write SetGlobalTilingQualityBasedTileCount;
    property MaxThreadCount: Integer read GetMaxThreadCount write SetMaxThreadCount;
    property ShotTransMaxSecondsPerKF: Double read FShotTransMaxSecondsPerKF write SetShotTransMaxSecondsPerKF;
    property ShotTransMinSecondsPerKF: Double read FShotTransMinSecondsPerKF write SetShotTransMinSecondsPerKF;
    property ShotTransCorrelLoThres: Double read FShotTransCorrelLoThres write SetShotTransCorrelLoThres;

    // GUI state variables

    property RenderPlaying: Boolean read FRenderPlaying write FRenderPlaying;
    property RenderFrameIndex: Integer read FRenderFrameIndex write SetRenderFrameIndex;
    property RenderPredicted: Boolean read FRenderPredicted write FRenderPredicted;
    property RenderMirrored: Boolean read FRenderMirrored write FRenderMirrored;
    property RenderOutputDithered: Boolean read FRenderOutputDithered write FRenderOutputDithered;
    property RenderUseGamma: Boolean read FRenderUseGamma write FRenderUseGamma;
    property RenderPaletteIndex: Integer read FRenderPaletteIndex write SetRenderPaletteIndex;
    property RenderTilePage: Integer read FRenderTilePage write SetRenderTilePage;
    property RenderGammaValue: Double read GetRenderGammaValue write SetRenderGammaValue;
    property RenderPage: TRenderPage read FRenderPage write FRenderPage;
    property RenderTitleText: String read FRenderTitleText;
    property RenderPsychoVisualQuality: Double read FRenderPsychoVisualQuality;
    property OutputBitmap: TBitmap read FOutputBitmap;
    property InputBitmap: TBitmap read FInputBitmap;
    property PaletteBitmap: TBitmap read FPaletteBitmap;
    property TilesBitmap: TBitmap read FTilesBitmap;
    property ProgressStep: TEncoderStep read FProgressStep;
    property OnProgress: TTilingEncoderProgressEvent read FOnProgress write FOnProgress;
  end;

  { TFastPortableNetworkGraphic }

  TFastPortableNetworkGraphic = class(TPortableNetworkGraphic)
    procedure InitializeWriter(AImage: TLazIntfImage; AWriter: TFPCustomImageWriter); override;
  end;


implementation

const
  CGTMCommandsCount = Ord(High(TGTMCommand)) + 1;
  CGTMCommandCodeBits = round(ln(CGTMCommandsCount) / ln(2));
  CGTMCommandBits = 16 - CGTMCommandCodeBits;
  CGTMBlendBufferCount = 2;
  CGTMBlendAlphaShift = 6;
  CGTMBlendAlphaMax = (1 shl CGTMBlendAlphaShift) - 1;
  CGTMBlendWeightBaseShift = 8;
  CGTMBlendWeightMin = -32;
  CGTMBlendWeightMax = 31;

  function CompareTileUseCountRev(Item1, Item2, UserParameter:Pointer):Integer;
  var
    t1, t2: PTile;
  begin
    t1 := PPTile(Item1)^;
    t2 := PPTile(Item2)^;

    Result := CompareValue(t2^.UseCount, t1^.UseCount);
    if Result = 0 then
    begin
      if Assigned(UserParameter) then
        Result := t1^.CompareRGBPixelsTo(t2^)
      else
        Result := t1^.ComparePalPixelsTo(t2^);
    end;
  end;

{ TTileMapItemHelper }

function TTileMapItemHelper.GetIsPredicted: Boolean;
begin
  Result := tmfPredicted in Flags;
end;

procedure TTileMapItemHelper.SetIsPredicted(AValue: Boolean);
begin
  if AValue then
    Flags += [tmfPredicted]
  else
    Flags -= [tmfPredicted];
end;

procedure TTileMapItemHelper.Reset(AKeepMirrors: Boolean);
begin
  TileIdx := -1;
  Error := 0;
  Attrs.MotionX := 0;
  Attrs.MotionY := 0;
  Attrs.MotionBackBufferOffset := 0;
  IsPredicted := False;
  IsBlended := False;
  if not AKeepMirrors then
    Flags := [];
end;

function TTileMapItemHelper.GetHMirror: Boolean;
begin
  Result := tmfHMirror in Flags;
end;

function TTileMapItemHelper.GetIsBlended: Boolean;
begin
  Result := tmfBlended in Flags;
end;

function TTileMapItemHelper.GetIsSmoothed: Boolean;
begin
  Result := IsPredicted and
    ((not IsBlended and (Attrs.MotionX = 0) and (Attrs.MotionY = 0) and (Attrs.MotionBackBufferOffset = 1)) or
     (IsBlended and (Attrs.BlendAlpha = 0) and (Attrs.BlendWeight = 0)));
end;

function TTileMapItemHelper.GetVMirror: Boolean;
begin
  Result := tmfVMirror in Flags;
end;

procedure TTileMapItemHelper.SetHMirror(AValue: Boolean);
begin
  if AValue then
    Flags += [tmfHMirror]
  else
    Flags -= [tmfHMirror];
end;

procedure TTileMapItemHelper.SetIsBlended(AValue: Boolean);
begin
  if AValue then
    Flags += [tmfBlended]
  else
    Flags -= [tmfBlended];
end;

procedure TTileMapItemHelper.SetVMirror(AValue: Boolean);
begin
  if AValue then
    Flags += [tmfVMirror]
  else
    Flags -= [tmfVMirror];
end;

{ TFastPortableNetworkGraphic }

procedure TFastPortableNetworkGraphic.InitializeWriter(AImage: TLazIntfImage; AWriter: TFPCustomImageWriter);
var
  W: TFPWriterPNG absolute AWriter;
begin
  inherited InitializeWriter(AImage, AWriter);
  W.CompressionLevel := clfastest;
end;

{ TTileHelper }

function TTileHelper.GetActive: Boolean;
begin
  Result := tfActive in Flags;
end;

function TTileHelper.GetHasPalPixels: Boolean;
begin
  Result := tfHasPalPixels in Flags;
end;

function TTileHelper.GetHasRGBPixels: Boolean;
begin
  Result := tfHasRGBPixels in Flags;
end;

function TTileHelper.GetHMirror_Initial: Boolean;
begin
  Result := tfHMirror_Initial in Flags;
end;

function TTileHelper.GetVMirror_Initial: Boolean;
begin
  Result := tfVMirror_Initial in Flags;
end;

procedure TTileHelper.SetActive(AValue: Boolean);
begin
  if AValue then
    Flags += [tfActive]
  else
    Flags -= [tfActive];
end;

procedure TTileHelper.SetHasPalPixels(AValue: Boolean);
begin
  if AValue then
    Flags += [tfHasPalPixels]
  else
    Flags -= [tfHasPalPixels];
end;

procedure TTileHelper.SetHasRGBPixels(AValue: Boolean);
begin
  if AValue then
    Flags += [tfHasRGBPixels]
  else
    Flags -= [tfHasRGBPixels];
end;

procedure TTileHelper.SetHMirror_Initial(AValue: Boolean);
begin
  if AValue then
    Flags += [tfHMirror_Initial]
  else
    Flags -= [tfHMirror_Initial];
end;

procedure TTileHelper.SetVMirror_Initial(AValue: Boolean);
begin
  if AValue then
    Flags += [tfVMirror_Initial]
  else
    Flags -= [tfVMirror_Initial];
end;

function TTileHelper.GetRGBPixelsPtr: PRGBPixels;
begin
  Assert(HasRGBPixels, 'TTileHelper !HasRGBPixels');
  Result := PRGBPixels(PByte(@Self) + SizeOf(TTile) + IfThen(HasPalPixels, SizeOf(TPalPixels)));
end;

function TTileHelper.GetPalPixelsPtr: PPalPixels;
begin
  Assert(HasPalPixels, 'TTileHelper !HasPalPixels');
  Result := PPalPixels(PByte(@Self) + SizeOf(TTile));
end;

function TTileHelper.GetRGBPixels(y, x: Integer): Integer;
begin
  Result := GetRGBPixelsPtr^[y, x];
end;

function TTileHelper.GetPalPixels(y, x: Integer): Byte;
begin
  Result := GetPalPixelsPtr^[y, x];
end;

procedure TTileHelper.SetRGBPixels(y, x: Integer; value: Integer);
begin
  GetRGBPixelsPtr^[y, x] := value;
end;

procedure TTileHelper.SetPalPixels(y, x: Integer; value: Byte);
begin
  GetPalPixelsPtr^[y, x] := value;
end;

class function TTileHelper.Array1DNew(x: Integer; ARGBPixels, APalPixels: Boolean): PTileDynArray;
var
  i, size: Integer;
  data: PByte;
begin
  Result := nil;
  size := SizeOf(TTile) + IfThen(APalPixels, SizeOf(TPalPixels)) + IfThen(ARGBPixels, SizeOf(TRGBPixels));
  data := AllocMem(size * x);

  FillByte(data^, size * x, 0);
  SetLength(Result, x);

  for i := 0 to x - 1 do
  begin
    PTile(data)^.HasPalPixels := APalPixels;
    PTile(data)^.HasRGBPixels := ARGBPixels;
    PTile(data)^.PalIdx := -1;
    Result[i] := PTile(data);
    Inc(data, size);
  end;
end;

class procedure TTileHelper.Array1DDispose(var AArray: PTileDynArray);
var
  i: Integer;
  smallest: Pointer;
begin
  if Length(AArray) > 0 then
  begin
    // account for the array having been sorted
    smallest := AArray[0];
    for i := 1 to High(AArray) do
      if AArray[i] < smallest then
        smallest := AArray[i];

    if Assigned(smallest) then
      Freemem(smallest);
    SetLength(AArray, 0);
  end;
end;

class procedure TTileHelper.Array1DRealloc(var AArray: PTileDynArray; ANewX: integer);
var
  prevLen, i, size: Integer;
  data: PByte;
  smallest: PTile;
  HasPalPx, HasRGBPx: Boolean;
begin
  Assert(Length(AArray) > 0);

  // account for the array having been sorted
  smallest := AArray[0];
  for i := 1 to High(AArray) do
    if AArray[i] < smallest then
      smallest := AArray[i];

  prevLen := Length(AArray);
  HasPalPx := smallest^.HasPalPixels;
  HasRGBPx := smallest^.HasRGBPixels;

  size := SizeOf(TTile) + IfThen(HasPalPx, SizeOf(TPalPixels)) + IfThen(HasRGBPx, SizeOf(TRGBPixels));
  data := PByte(smallest);

  data := ReAllocMem(data, size * ANewX);
  SetLength(AArray, ANewX);

  // recompute existing array pointers
  for i := 0 to min(ANewX, prevLen) - 1 do
    AArray[i] := PTile(PByte(AArray[i]) + (data - PByte(smallest)));

  // init new pointers
  Inc(data, size * prevLen);
  for i := prevLen to ANewX - 1 do
  begin
    AArray[i] := PTile(data);
    FillChar(AArray[i]^, size, 0);
    AArray[i]^.HasPalPixels := HasPalPx;
    AArray[i]^.HasRGBPixels := HasRGBPx;
    AArray[i]^.PalIdx := -1;
    Inc(data, size);
  end;
end;

class function TTileHelper.New(ARGBPixels, APalPixels: Boolean): PTile;
begin
  Result := AllocMem(SizeOf(TTile) + IfThen(APalPixels, SizeOf(TPalPixels)) + IfThen(ARGBPixels, SizeOf(TRGBPixels)));
  FillByte(Result^, SizeOf(TTile), 0);

  Result^.HasPalPixels := APalPixels;
  Result^.HasRGBPixels := ARGBPixels;
  Result^.PalIdx := -1;

  if APalPixels then
    FillByte(Result^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth), 0);

  if ARGBPixels then
    FillDWord(Result^.GetRGBPixelsPtr^[0, 0], sqr(cTileWidth), 0);
end;

class procedure TTileHelper.Dispose(var ATile: PTile);
begin
  FreeMemAndNil(ATile);
end;

procedure TTileHelper.CopyPalPixelsFrom(const ATile: TTile);
begin
  Move(ATile.GetPalPixelsPtr^[0, 0], GetPalPixelsPtr^[0, 0], SizeOf(TPalPixels));
end;

procedure TTileHelper.CopyPalPixels(const APalPixels: TPalPixels);
begin
  Move(APalPixels[0, 0], GetPalPixelsPtr^[0, 0], SizeOf(TPalPixels));
end;

procedure TTileHelper.CopyPalPixels(const APalPixels: TByteDynArray);
begin
  Move(APalPixels[0], GetPalPixelsPtr^[0, 0], SizeOf(TPalPixels));
end;

procedure TTileHelper.CopyRGBPixels(const ARGBPixels: TRGBPixels);
begin
  Move(ARGBPixels[0, 0], GetRGBPixelsPtr^[0, 0], SizeOf(TRGBPixels));
end;

procedure TTileHelper.CopyRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer);
var
  ty: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    Move(AFrameBuffer[AY, AX], GetRGBPixelsPtr^[ty, 0], cTileWidth * SizeOf(Integer));
    Inc(AY);
  end;
end;

procedure TTileHelper.BlendRGBPixels(const AM1Buffer, AM2Buffer: TIntegerDynArray2; AY, AX: Integer; AAlpha: Byte; AWeight: ShortInt);
var
  ty, tx: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    for tx := 0 to cTileWidth - 1 do
    begin
      RGBPixels[ty, tx] := BlendRGB(AM1Buffer[AY, AX], AM2Buffer[AY, AX], AAlpha, AWeight, CGTMBlendAlphaShift, CGTMBlendWeightBaseShift);
      Inc(AX);
    end;
    Dec(AX, cTileWidth);
    Inc(AY);
  end;
end;

procedure TTileHelper.BlitPalPixels(const AFrameBuffer: TIntegerDynArray2; const APalette: TIntegerDynArray; AVMirror,
  AHMirror: Boolean; AY, AX: Integer);
var
  ty, tx, tym, txm: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    tym := ty;
    if AVMirror then tym := cTileWidth - 1 - tym;

    for tx := 0 to cTileWidth - 1 do
    begin
      txm := tx;
      if AHMirror then txm := cTileWidth - 1 - txm;

      AFrameBuffer[AY + ty, AX + tx] := APalette[PalPixels[tym, txm]];
    end;
  end;
end;

procedure TTileHelper.BlitRGBPixels(const AFrameBuffer: TIntegerDynArray2; AVMirror, AHMirror: Boolean; AY, AX: Integer);
var
  ty, tx, tym, txm: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    tym := ty;
    if AVMirror then tym := cTileWidth - 1 - tym;

    for tx := 0 to cTileWidth - 1 do
    begin
      txm := tx;
      if AHMirror then txm := cTileWidth - 1 - txm;

      AFrameBuffer[AY + ty, AX + tx] := RGBPixels[tym, txm];
    end;
  end;
end;

procedure TTileHelper.ClearPalPixels;
begin
  FillByte(GetPalPixelsPtr^[0, 0], sqr(cTileWidth), 0);
end;

procedure TTileHelper.ClearRGBPixels;
begin
  FillDWord(GetRGBPixelsPtr^[0, 0], sqr(cTileWidth), 0);
end;

procedure TTileHelper.ClearPixels;
begin
  if HasPalPixels then ClearPalPixels;
  if HasRGBPixels then ClearRGBPixels;
end;

procedure TTileHelper.ExtractPalPixels(AArray: PFloat);
var
  i: Integer;
  PB: PByte;
  PF: PFloat;
begin
  Assert(HasPalPixels);
  PB := @GetPalPixelsPtr^[0, 0];
  PF := AArray;
  for i := 0 to Sqr(cTileWidth) - 1 do
  begin
    PF^ := PB^;
    Inc(PB);
    Inc(PF);
  end;
end;

procedure TTileHelper.LoadPalPixels(AArray: PFloat);
var
  i: Integer;
  PB: PByte;
  PF: PFloat;
begin
  Assert(HasPalPixels);
  PB := @GetPalPixelsPtr^[0, 0];
  PF := AArray;
  for i := 0 to Sqr(cTileWidth) - 1 do
  begin
    PB^ := Round(PF^);
    Inc(PB);
    Inc(PF);
  end;
end;

function TTileHelper.ComparePalPixelsTo(const ATile: TTile): Integer;
begin
  Result := CompareByte(GetPalPixelsPtr^[0, 0], ATile.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
end;

function TTileHelper.CompareRGBPixelsTo(const ATile: TTile): Integer;
begin
  Result := CompareDWord(GetRGBPixelsPtr^[0, 0], ATile.GetRGBPixelsPtr^[0, 0], sqr(cTileWidth));
end;

function TTileHelper.CompareRGBColorsTo(const ATile: TTile): Double;

  function DoOneComponent(APSelf, APOther: PByte): Integer;
  var
    ty: Integer;
  begin
    Result := 0;
    for ty := 0 to cTileWidth - 1 do
    begin
      // unroll by cTileWidth

      Result += Abs(APSelf[ 0] - APOther[ 0]);
      Result += Abs(APSelf[ 4] - APOther[ 4]);
      Result += Abs(APSelf[ 8] - APOther[ 8]);
      Result += Abs(APSelf[12] - APOther[12]);
      Result += Abs(APSelf[16] - APOther[16]);
      Result += Abs(APSelf[20] - APOther[20]);
      Result += Abs(APSelf[24] - APOther[24]);
      Result += Abs(APSelf[28] - APOther[28]);

      inc(APSelf, sizeof(Integer) * cTileWidth);
      inc(APOther, sizeof(Integer) * cTileWidth);
    end;
  end;

var
  PSelf, POther: PByte;
begin
  PSelf := PByte(GetRGBPixelsPtr);
  POther := PByte(ATile.GetRGBPixelsPtr);

  Result := DoOneComponent(@PSelf[0], @POther[0]);
  Result += DoOneComponent(@PSelf[1], @POther[1]);
  Result += DoOneComponent(@PSelf[2], @POther[2]);

  Result /= Sqr(cTileWidth) * cColorCpns;
end;

procedure TTileHelper.CopyFrom(const ATile: TTile);
begin
  UseCount := ATile.UseCount;
  TmpIndex := ATile.TmpIndex;
  PalIdx := ATile.PalIdx;
  MergeIndex := ATile.MergeIndex;
  Active := ATile.Active;
  HMirror_Initial := ATile.HMirror_Initial;
  VMirror_Initial := ATile.VMirror_Initial;

  if HasPalPixels and ATile.HasPalPixels then
    CopyPalPixels(ATile.GetPalPixelsPtr^);
  if HasRGBPixels and ATile.HasRGBPixels then
    CopyRGBPixels(ATile.GetRGBPixelsPtr^);
end;

{ TKeyFrame }

procedure TKeyFrame.LogPSNR;
var
  kfIdx: Integer;
  errCml: UInt64;
begin
  InterLockedDecrement(ReconstructFramesLeft);
  if ReconstructFramesLeft <= 0 then
  begin
    ReconstructPSNR := EuclideanToPSNR(ReconstructErrCml / (Encoder.FTileMapSize * FrameCount));
    WriteLn('KF: ', StartFrame:8, ' PSNR-HVS: ', ReconstructPSNR:12:6, ' (by tile)');

    InterLockedDecrement(Encoder.FKeyFramesLeft);
    if Encoder.FKeyFramesLeft <= 0 then
    begin
      errCml := 0;
      for kfIdx := 0 to High(Encoder.FKeyFrames) do
        errCml += Encoder.FKeyFrames[kfIdx].ReconstructErrCml;

      Encoder.FReconstructPSNR := EuclideanToPSNR(errCml / (Encoder.FTileMapSize * Length(Encoder.FFrames)));
      WriteLn('All:', Length(Encoder.FFrames):8, ' PSNR-HVS: ', Encoder.FReconstructPSNR:12:6, ' (by tile)');
    end;
  end;
end;

constructor TKeyFrame.Create(AParent: TTilingEncoder; AIndex, AStartFrame, AEndFrame: Integer);
begin
  Encoder := AParent;
  Index := AIndex;
  StartFrame := AStartFrame;
  EndFrame := AEndFrame;
  FrameCount := AEndFrame - AStartFrame + 1;

  SpinLeave(@ReconstructLock);
end;

destructor TKeyFrame.Destroy;
begin
  inherited Destroy;
end;

{ TFrameBuffer }

constructor TFrameBuffer.Create(ABufferCount, AHeight, AWidth: Integer);
begin
  SetLength(FrameBuffer, ABufferCount, AHeight, AWidth);
end;

function TFrameBuffer.GetBuffer(ARelativeIndex: Integer): TIntegerDynArray2;
begin
  Result := FrameBuffer[(CurBufferIndex + ARelativeIndex + Length(FrameBuffer)) mod Length(FrameBuffer)];
end;

function TFrameBuffer.GetBuffer: TIntegerDynArray2;
begin
  Result := FrameBuffer[CurBufferIndex];
end;

procedure TFrameBuffer.AdvanceFrame;
begin
  CurBufferIndex := (CurBufferIndex + 1) mod Length(FrameBuffer);
end;

{ TDCTBuffer }

constructor TDCTBuffer.Create(ABufferCount, ASize: Integer);
begin
  SetLength(DCTBuffer, ABufferCount, ASize);
end;

function TDCTBuffer.GetBuffer(ARelativeIndex: Integer): TDCTDynArray;
begin
  Result := DCTBuffer[(CurBufferIndex + ARelativeIndex + Length(DCTBuffer)) mod Length(DCTBuffer)];
end;

function TDCTBuffer.GetBuffer: TDCTDynArray;
begin
  Result := DCTBuffer[CurBufferIndex];
end;

procedure TDCTBuffer.AdvanceFrame;
begin
  CurBufferIndex := (CurBufferIndex + 1) mod Length(DCTBuffer);
end;

{ TFrame }

constructor TFrame.Create(AParent: TTilingEncoder; AIndex: Integer);
var
  sy, sx: Integer;
begin
  Encoder := AParent;
  Index := AIndex;

  FrameTilesEvent := CreateEvent(nil, True, False, nil);
  CompressedFrameTiles := TMemoryStream.Create;
  InterframeCorrelationEvent := CreateEvent(nil, True, False, nil);
  LoadFromImageFinishedEvent := CreateEvent(nil, True, False, nil);
  SpinLeave(@FrameTilesLock);

  SetLength(TileMap, Encoder.FTileMapHeight, Encoder.FTileMapWidth);
  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
      TileMap[sy, sx].Reset(False);
end;

destructor TFrame.Destroy;
begin
  CloseHandle(LoadFromImageFinishedEvent);
  CloseHandle(InterframeCorrelationEvent);
  CompressedFrameTiles.Free;
  CloseHandle(FrameTilesEvent);

  if Assigned(IntraReducedTiles) then
    TTile.Array1DDispose(IntraReducedTiles);

  inherited Destroy;
end;

procedure TFrame.CompressFrameTiles;
var
  CompStream: Tcompressionstream;
begin
  CompressedFrameTiles.Clear;
  CompStream := Tcompressionstream.create(Tcompressionlevel.cldefault, CompressedFrameTiles, True);
  try
    CompStream.WriteBuffer(FrameTiles[0]^, Length(TileMap) * Length(TileMap[0]) * CFrameTileSize);
    CompStream.flush;
  finally
    CompStream.Free;
  end;

  Assert(CompressedFrameTiles.Size > 0);

  // now that FrameTiles are compressed, dispose them

  TTile.Array1DDispose(FrameTiles);
end;

procedure TFrame.AcquireFrameTiles;
var
  CompStream: Tdecompressionstream;
  ftrc: Integer;
begin
  SpinEnter(@FrameTilesLock);
  try
    Inc(FrameTilesRefCount);
    ftrc := FrameTilesRefCount;
  finally
    SpinLeave(@FrameTilesLock);
  end;

  if ftrc = 1 then
  begin
    Assert(CompressedFrameTiles.Size > 0);

    CompressedFrameTiles.Position := 0;
    FrameTiles := TTile.Array1DNew(Length(TileMap) * Length(TileMap[0]), CFrameTilesHaveRGBPixels, CFrameTilesHavePalPixels);

    CompStream := Tdecompressionstream.create(CompressedFrameTiles, True);
    try
      CompStream.ReadBuffer(FrameTiles[0]^, Length(TileMap) * Length(TileMap[0]) * CFrameTileSize);
    finally
      CompStream.Free;
    end;

    // signal other threads decompression is done
    SetEvent(FrameTilesEvent);
  end
  else
  begin
    WaitForSingleObject(FrameTilesEvent, INFINITE);
  end;
end;

procedure TFrame.ReleaseFrameTiles;
begin
  SpinEnter(@FrameTilesLock);
  try
    Dec(FrameTilesRefCount);
    if FrameTilesRefCount <= 0 then
    begin
      Assert(FrameTilesRefCount = 0);
      TTile.Array1DDispose(FrameTiles);

      ResetEvent(FrameTilesEvent);
    end;
  finally
    SpinLeave(@FrameTilesLock);
  end;
end;

function TFrame.GetUsedTileCount: Integer;
var
  Used: TByteDynArray;
  sx, sy: Integer;
  TMI: PTileMapItem;
begin
  Result := 0;

  if Length(Encoder.Tiles) = 0 then
    Exit;

  SetLength(Used, Length(Encoder.Tiles));
  FillByte(Used[0], Length(Encoder.Tiles), 0);

  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      TMI := @TileMap[sy, sx];

      if TMI^.TileIdx >= 0 then
        Used[TMI^.TileIdx] := 1;
    end;

  for sx := 0 to High(Used) do
    Inc(Result, Used[sx]);
end;

function TFrame.GetUnpredictedTileCount: Integer;
var
  sy, sx: Integer;
  TMI: PTileMapItem;
begin
  Result := 0;
  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      TMI := @TileMap[sy, sx];

      if not TMI^.IsPredicted then
        Inc(Result);
    end;
end;

procedure TFrame.ResetTileMap(AKeepMirrors: Boolean);
var
  sy, sx: Integer;
begin
  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
      TileMap[sy,sx].Reset(AKeepMirrors);
end;

type
  TPowellBlendData = record
    DX, DY, AlphaMax: Integer;
    DCT: TDCT;
    FrameM1, FrameM2: TIntegerDynArray2;
    BlendTile: PTile;
  end;

  PPowellBlendData = ^TPowellBlendData;

function TFrame.PowellBlend(const x: TVector; data: Pointer): TScalar;
var
  pbData: PPowellBlendData absolute data;
  alpha, weight: Integer;
  BlendCpnPixels: TCpnPixels;
  BlendDCT: TDCT;
begin
  alpha := EnsureRange(Round(x[0]), 0, pbData^.AlphaMax);
  weight := EnsureRange(Round(x[1]), CGTMBlendWeightMin, CGTMBlendWeightMax);

  pbData^.BlendTile^.BlendRGBPixels(pbData^.FrameM1, pbData^.FrameM2, pbData^.DY, pbData^.DX, alpha, weight);

  Encoder.ConvertToCpnPixels(pbData^.BlendTile^, False, False, False, False, nil, BlendCpnPixels);
  Encoder.ComputeCpnPixelsPsyVisFeatures(BlendCpnPixels, pvsWeightedDCT, cColorCpns, BlendDCT);

  Result := CompareEuclideanDCTPtr_asm(pbData^.DCT, BlendDCT);
end;

procedure TFrame.GetPredictExtents(ARadius, ADY, ADX: Integer; out oxmn, oxmx, oymn, oymx: Integer);
begin
  oymn := Max(0, ADY - ARadius - 1);
  oymx := Min(Encoder.FScreenHeight - cTileWidth, ADY + ARadius);
  oxmn := Max(0, ADX - ARadius - 1);
  oxmx := Min(Encoder.FScreenWidth - cTileWidth, ADX + ARadius);
end;

procedure TFrame.PrepareDCTs(const ADCTs: TDCTDynArray; const ABuffer: TIntegerDynArray2);

  procedure DoDCTs(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    x, yx: Integer;
    DCTTile: PTile;
    CpnPixels: TCpnPixels;
  begin
    if not InRange(AIndex, 0, Encoder.FScreenHeight - cTileWidth) then
      Exit;

    yx := AIndex * (Encoder.FScreenWidth - cTileWidth + 1);

    DCTTile := TTile.New(True, False);
    try
      for x := 0 to Encoder.FScreenWidth - cTileWidth do
      begin
        DCTTile^.CopyRGBPixels(ABuffer, AIndex, x);

        Encoder.ConvertToCpnPixels(DCTTile^, False, False, False, False, nil, CpnPixels);
        Encoder.ComputeCpnPixelsPsyVisFeatures(CpnPixels, pvsWeightedDCT, cColorCpns, ADCTs[yx]);

        Inc(yx);
      end;
    finally
      TTile.Dispose(DCTTile);
    end;
  end;

begin
  ProcThreadPool.DoParallelLocalProc(@DoDCTs, 0, Encoder.FScreenHeight - cTileWidth);
end;

function TFrame.PredictTileBlending(AUnipolar: Boolean; ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; AFrameBuffer: TFrameBuffer): Cardinal;
var
  bestAlpha, bestWeight: Integer;
  BlendTile: PTile;
  pbData: TPowellBlendData;
  X: TVector;
begin
  BlendTile := TTile.New(True, False);
  try
    pbData.AlphaMax := IfThen(AUnipolar, 0, CGTMBlendAlphaMax);
    pbData.BlendTile := BlendTile;
    pbData.DCT := ADCT;
    pbData.DX := ADX;
    pbData.DY := ADY;
    pbData.FrameM1 := AFrameBuffer.GetBuffer(-1);
    pbData.FrameM2 := AFrameBuffer.GetBuffer(-2);

    X := [pbData.AlphaMax * 0.5, 0.0];

    Result := Round(PowellMinimize(@PowellBlend, X, 16.0, 0.5, 0.5, MaxInt, @pbData)[0]);
    bestAlpha := EnsureRange(Round(x[0]), 0, pbData.AlphaMax);
    bestWeight := EnsureRange(Round(x[1]), CGTMBlendWeightMin, CGTMBlendWeightMax);
  finally
    TTile.Dispose(BlendTile);
  end;

  if not ATMI^.IsPredicted or (Result < ATMI^.Error) then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsBlended := True;
    ATMI^.Error := Result;
    ATMI^.Attrs.BlendAlpha := bestAlpha;
    ATMI^.Attrs.BlendWeight := bestWeight;
  end
  else
  begin
    Result := High(Cardinal);
  end;
end;

function TFrame.PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Cardinal;
var
  oy, yx: Integer;
  state: TDCTCribbleState;
  PrevDCTPtr: PDCTScalar;
begin
  Result := High(Cardinal);
  state.Error := High(Cardinal);
  state.Y := MaxInt;
  state.X := MaxInt;
  state.DY := ADY;
  state.DX := ADX;
  state.PenaltyWeight := ABackBufferOffset;

  GetPredictExtents(ARadius, state.DY, state.DX, state.oxmn, state.oxmx, state.oymn, state.oymx);

  for oy := state.oymn to state.oymx do
  begin
    yx := oy * (Encoder.FScreenWidth - cTileWidth + 1) + state.oxmn;
    PrevDCTPtr := ADCTs[yx];

    CribbleEuclideanDCTPtr_asm(ADCT, PrevDCTPtr, @state, oy);
  end;

  if not ATMI^.IsPredicted or (state.Error < ATMI^.Error) then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsBlended := False;
    ATMI^.Error := state.Error;
    ATMI^.Attrs.MotionY := state.Y - ADY;
    ATMI^.Attrs.MotionX := state.X - ADX;
    ATMI^.Attrs.MotionBackBufferOffset := ABackBufferOffset;
    Result := state.Error;
  end;
end;

function TFrame.PredictTileIntra(ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Cardinal;
var
  oy, ox, oymn, oymx, oxmn, oxmx, yx, bestX, bestY: Integer;
  PSNRAcc: TFloat;
  PSNRIdx, PSNRCnt, err: Cardinal;
  PrevDCTPtr: PDCTScalar;
begin
  GetPredictExtents(High(ShortInt), ADY, ADX, oxmn, oxmx, oymn, oymx);

  Result := High(Cardinal);
  bestY := MaxInt;
  bestX := MaxInt;

  PSNRAcc := 0;
  PSNRIdx := 1;
  PSNRCnt := 0;
  for oy := oymn to oymx do
  begin
    if InRange(oy - ADY, -cTileWidth, cTileWidth - 1) then
      Continue;

    yx := oy * (Encoder.FScreenWidth - cTileWidth + 1) + oxmn;
    for ox := oxmn to oxmx do
    begin
      if InRange(ox - ADX, -cTileWidth, cTileWidth - 1) then
        Continue;

      PrevDCTPtr := ADCTs[yx];

      err := CompareEuclideanDCTPtr_asm(ADCT, PrevDCTPtr);

      if err < Result then
      begin
        Result := err;
        bestY := oy;
        bestX := ox;

        PSNRAcc += EuclideanToPSNR(err) * PSNRIdx;
        Inc(PSNRCnt, PSNRIdx);
        Inc(PSNRIdx);
      end;

      Inc(yx);
    end;
  end;

  ATMI^.IsPredicted := True;
  ATMI^.IsBlended := False;
  ATMI^.Error := PSNRToEuclidean(PSNRAcc / PSNRCnt);
  ATMI^.Attrs.MotionY := bestY - ADY;
  ATMI^.Attrs.MotionX := bestX - ADX;
end;

procedure TFrame.Predict(ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer; AFrameBuffer: TFrameBuffer);

  procedure DoXY(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    dx, dy, sy, sx: Integer;
    TMI: PTileMapItem;
    FrameTile: PTile;
    CurCpnPixels: TCpnPixels;
    CurDCT: TDCT;
  begin
    if not InRange(AIndex, 0, Encoder.FTileMapSize - 1) then
      Exit;

    DivMod(AIndex, Encoder.FTileMapWidth, sy, sx);

    TMI := @TileMap[sy, sx];
    FrameTile := FrameTiles[AIndex];

    Encoder.ConvertToCpnPixels(FrameTile^, False, False, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, nil, CurCpnPixels);
    Encoder.ComputeCpnPixelsPsyVisFeatures(CurCpnPixels, pvsWeightedDCT, cColorCpns, CurDCT);

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    if ABackBufferOffset = 0 then
    begin
      PredictTileIntra(dy, dx, TMI, CurDCT, ADCTBuffer.GetBuffer)
    end
    else
    begin
      if ABackBufferOffset = CGTMBlendBufferCount then
        PredictTileBlending(False, dy, dx, TMI, CurDCT, AFrameBuffer)
      else if (ABackBufferOffset = 1) and (Index = PKeyFrame.StartFrame + 1) then
        PredictTileBlending(True, dy, dx, TMI, CurDCT, AFrameBuffer);
      PredictTileMotion(ARadius, ABackBufferOffset, dy, dx, TMI, CurDCT, ADCTBuffer.GetBuffer(-ABackBufferOffset));
    end;
  end;

begin
  Assert(ARadius >= 0);
  Assert(ABackBufferOffset >= 0);

  if ARadius = 0 then
    Exit;

  Dec(ARadius);

  ProcThreadPool.DoParallelLocalProc(@DoXY, 0, Encoder.FTileMapSize - 1);
end;

procedure DoAsyncLoadFromImage(AData : Pointer);
var
  Frame: TFrame;
begin
  Frame := TFrame(AData);

  Frame.AsyncLoadFromImage;
end;

procedure TFrame.LoadFromImage(AImageWidth, AImageHeight: Integer; AImage: PInteger);
var
  i, j, col, ti, tx, ty: Integer;
  pcol: PInteger;
begin
  // create frame tiles from image data

  FrameTiles := TTile.Array1DNew(Encoder.FTileMapSize, CFrameTilesHaveRGBPixels, CFrameTilesHavePalPixels);

  pcol := PInteger(AImage);
  for j := 0 to AImageHeight - 1 do
  begin
    for i := 0 to AImageWidth - 1 do
      begin
        col := pcol^;
        Inc(pcol);

        if (j < Encoder.FScreenHeight) and (i < Encoder.FScreenWidth) then
        begin
          ti := Encoder.FTileMapWidth * (j shr cTileWidthBits) + (i shr cTileWidthBits);
          tx := i and (cTileWidth - 1);
          ty := j and (cTileWidth - 1);
          col := SwapRB(col);

          FrameTiles[ti]^.RGBPixels[ty, tx] := col;
        end;
      end;
  end;

  // moderate the number of threads
  if Index >= Encoder.MaxThreadCount then
    WaitForSingleObject(Encoder.FFrames[Index - Encoder.MaxThreadCount].LoadFromImageFinishedEvent, INFINITE);

  TThread.ExecuteInThread(@DoAsyncLoadFromImage, Self);
end;

procedure TFrame.IntraReduce(ATargetTileCount: Integer);
var
  YakmoDataset: TDoubleDynArray2;

  procedure DoDCT(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    Tile: PTile;
  begin
    if not InRange(AIndex, 0, Encoder.FTileMapSize - 1) then
      Exit;

    Tile := FrameTiles[AIndex];
    Assert(Tile^.Active);

    Encoder.ComputeTilePsyVisFeatures(Tile^, pvsWeightedDCT, False, False, False, False, cColorCpns, nil, @YakmoDataset[AIndex, 0]);
  end;

var
  nbTiles, DSLen, sy, sx, iDS, iCluster, iDCT: Integer;

  Tile: PTile;
  TMI: PTileMapItem;
  Yakmo: PYakmo;

  YakmoCentroids: TDoubleDynArray2;
  YakmoClusters: TIntegerDynArray;
begin
  AcquireFrameTiles;
  try
    DSLen := Encoder.FTileMapSize;

    // compute frame tiles DCT

    SetLength(YakmoDataset, DSLen, cTileDCTSize);
    ProcThreadPool.DoParallelLocalProc(@DoDCT, 0, DSLen - 1);

    // reduce to TileCount tiles (use Yakmo KMeans)

    DSLen := Length(YakmoDataset);
    nbTiles := min(ATargetTileCount, DSLen);
    SetLength(YakmoClusters, DSLen);
    SetLength(YakmoCentroids, nbTiles, cTileDCTSize);

    Yakmo := yakmo_create(nbTiles, 1, cYakmoMaxIterations, 1, 0, 0, 1);
    try
      yakmo_set_num_threads(Encoder.MaxThreadCount);

      yakmo_load_train_data(Yakmo, Length(YakmoDataset), cTileDCTSize, PPDouble(@YakmoDataset[0]));
      yakmo_train_on_data(Yakmo, @YakmoClusters[0]);
      yakmo_get_centroids(Yakmo, PPDouble(@YakmoCentroids[0]));
    finally
      yakmo_destroy(Yakmo);
    end;

    // store centroid tiles

    if Assigned(IntraReducedTiles) then
      TTile.Array1DDispose(IntraReducedTiles);
    IntraReducedTiles := TTile.Array1DNew(nbTiles, True, False);
    SetLength(IntraReducedTileIndexes, Encoder.FTileMapHeight, Encoder.FTileMapWidth);

    for iCluster := 0 to High(YakmoCentroids) do
    begin
      Tile := IntraReducedTiles[iCluster];

      Tile^.Active := True;
      for iDS := 0 to High(YakmoClusters) do
        if YakmoClusters[iDS] = iCluster then
          Inc(Tile^.UseCount);

      for iDCT := 0 to cTileDCTSize - 1 do
        YakmoCentroids[iCluster, iDCT] := NanDef(YakmoCentroids[iCluster, iDCT], 0.0);

      Encoder.ComputeInvTilePsyVisFeatures(@YakmoCentroids[iCluster, 0], pvsWeightedDCT, False, cColorCpns, Tile^);
    end;

    // update tilemap / tile indexes

    iDS := 0;
    for sy := 0 to Encoder.FTileMapHeight - 1 do
      for sx := 0 to Encoder.FTileMapWidth - 1 do
      begin
        TMI := @TileMap[sy, sx];
        iCluster := YakmoClusters[iDS];

        IntraReducedTileIndexes[sy, sx] := iCluster;

        TMI^.IsPredicted := False;

        Inc(iDS);
      end;

    WriteLn('KF: ', Index:8, ' TileCount: ', Length(IntraReducedTiles):8);
  finally
    ReleaseFrameTiles;
  end;
end;

procedure TFrame.DirectBlit(const ABuffer: TIntegerDynArray2);

  procedure DoBlit(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    dx, dy, sx, yx: Integer;
    FrameTile: PTile;
  begin
    if not InRange(AIndex, 0, Encoder.FTileMapHeight - 1) then
      Exit;

    dy := AIndex shl cTileWidthBits;
    yx := AIndex * Encoder.FTileMapWidth;

    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      dx := sx shl cTileWidthBits;

      FrameTile := FrameTiles[yx];
      FrameTile^.BlitRGBPixels(ABuffer, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, dy, dx);

      Inc(yx);
    end;
  end;

begin
  ProcThreadPool.DoParallelLocalProc(@DoBlit, 0, Encoder.FTileMapHeight - 1);
end;

function TFrame.PrepareInterFrameData: TFloatDynArray;
var
  i, sy, sx, ty, tx, sz, di: Integer;
  rr, gg, bb: Integer;
  lll, aaa, bbb, invSize: TFloat;
  pat: PInteger;
begin
  Result := nil;
  sz := Encoder.FTileMapSize;

  SetLength(Result, sz * cColorCpns);

  invSize := 1 / Sqr(cTileWidth);
  di := 0;
  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      i := sy * Encoder.FTileMapWidth + sx;
      pat := PInteger(@FrameTiles[i]^.GetRGBPixelsPtr^[0, 0]);

      for ty := 0 to cTileWidth - 1 do
        for tx := 0 to cTileWidth - 1 do
        begin
          FromRGB(pat^, rr, gg, bb);
          Inc(pat);
          RGBToLAB(rr, gg, bb, lll, aaa, bbb);
          Result[di + 0] += lll;
          Result[di + 1] += aaa;
          Result[di + 2] += bbb;
        end;

      Result[di + 0] *= invSize;
      Result[di + 1] *= invSize;
      Result[di + 2] *= invSize;

      Inc(di, 3);
    end;
  Assert(di = sz * cColorCpns);
end;

procedure TFrame.AsyncLoadFromImage;
var
  i: Integer;
  HMirror, VMirror: Boolean;
  Tile: PTile;
  TMI: PTileMapItem;
  prevFrameICD: TFloatDynArray;
begin
  // compute inter-frame correlations

  InterframeCorrelationData := PrepareInterFrameData;
  SetEvent(InterframeCorrelationEvent);

  if Index > 0 then
  begin
    // wait prev frame InterframeCorrelationData
    WaitForSingleObject(Encoder.FFrames[Index - 1].InterframeCorrelationEvent, INFINITE);

    prevFrameICD := Encoder.FFrames[Index - 1].InterframeCorrelationData;
    InterframeCorrelation := Encoder.PearsonCorrelation(prevFrameICD, InterframeCorrelationData);
  end;

  // also handle tilemap H/V mirrors

  for i := 0 to Encoder.FTileMapSize - 1 do
  begin
    Tile := FrameTiles[i];
    TMI := @TileMap[i div Encoder.FTileMapWidth, i mod Encoder.FTileMapWidth];

    Encoder.GetTileHVMirrorHeuristics(Tile^, False, HMirror, VMirror);

    Tile^.Active := True;
    Tile^.UseCount := 1;
    Tile^.TmpIndex := -1;
    Tile^.HMirror_Initial := HMirror;
    Tile^.VMirror_Initial := VMirror;

    TMI^.HMirror := HMirror;
    TMI^.VMirror := VMirror;

    if HMirror then Encoder.HMirrorTile(Tile^);
    if VMirror then Encoder.VMirrorTile(Tile^);
  end;

  // compress frame tiles to save memory

  CompressFrameTiles;

  Write(Index + 1:8, ' / ', Length(Encoder.FFrames):8, #13);

  // done

  SetEvent(LoadFromImageFinishedEvent);

  // wait until the next frame has finished to free InterframeCorrelationData

  if Index < High(Encoder.FFrames) then
    WaitForSingleObject(Encoder.FFrames[Index + 1].LoadFromImageFinishedEvent, INFINITE);
  SetLength(InterframeCorrelationData, 0);
end;

procedure TFrame.Reconstruct(ARadius: Integer; AFrameBuffer: TFrameBuffer);
const
  cEpuKnnK = 64;
  cPSNREpsilon = 0.1;
var
  DS: PTilingDataset;

  procedure DoXY(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    sx, sy, dx, dy, ty, tx, tileEpuIdx, palEpuIdx, prevTileIdx, prevPalIdx: Integer;
    knnErr, err: Cardinal;
    knnPSNR, mpPSNR: Double;

    FrameTile, Tile: PTile;
    TMI: PTileMapItem;

    FrontBuf, BackBuf, M1Buf, M2Buf: TIntegerDynArray2;
    FTDCT, CurDCT: TDCT;
    FTCpnPixels, CurCpnPixels: TCpnPixels;
    EpuErrs: array[0 .. cEpuKnnK - 1] of Cardinal;
    EpuTileIdxs: array[0 .. cEpuKnnK - 1] of Integer;
    EpuPalIdxs: array[0 .. cEpuKnnK - 1] of Integer;
  begin
    if not InRange(AIndex, 0, Encoder.FTileMapSize - 1) then
      Exit;

    DivMod(AIndex, Encoder.FTileMapWidth, sy, sx);

    TMI := @TileMap[sy, sx];

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    FrameTile := FrameTiles[AIndex];
    Encoder.ConvertToCpnPixels(FrameTile^, False, False, False, False, nil, FTCpnPixels);
    Encoder.ComputeCpnPixelsPsyVisFeatures(FTCpnPixels, pvsWeightedDCT, cColorCpns, FTDCT);

    // redo motion prediction (account for palette)

    mpPSNR := -Infinity;
    if (Index <> PKeyFrame.StartFrame) and (ARadius >= 0) then
      mpPSNR := EuclideanToPSNR(TMI^.Error);

    // use the KNN dataset to predict a tile with its associated palette

    knnErr := High(Cardinal);
    TMI^.TileIdx := ann_kdtree_short_search(DS^.ANN, @FTDCT[0], 0, @knnErr);
    if InRange(TMI^.TileIdx, 0, DS^.KNNSize - 1) then
    begin
      knnPSNR := EuclideanToPSNR(knnErr);
    end
    else
    begin
      TMI^.TileIdx := -1;
      knnPSNR := -Infinity;
    end;

    // devise which is best

    case CompareValue(knnPSNR, mpPSNR, cPSNREpsilon) of
      GreaterThanValue:
      begin
        // KNN is best

        TMI^.Error := knnErr;
        TMI^.IsPredicted := False;
      end;
      EqualsValue, // motion prediction has priority in case of ties (less bitrate)
      LessThanValue:
      begin
        // motion prediction is best

        TMI^.IsPredicted := True;
        TMI^.TileIdx := -1;
      end;
    end;

    if TMI^.IsPredicted then
    begin
      // draw fb (motion predicted tile)

      FrontBuf := AFrameBuffer.GetBuffer;
      if TMI^.IsBlended then
      begin
        M1Buf := AFrameBuffer.GetBuffer(-1);
        M2Buf := AFrameBuffer.GetBuffer(-2);
        for ty := 0 to cTileWidth - 1 do
        begin
          for tx := 0 to cTileWidth - 1 do
          begin
            FrontBuf[dy, dx] := BlendRGB(M1Buf[dy, dx], M2Buf[dy, dx], TMI^.Attrs.BlendAlpha, TMI^.Attrs.BlendWeight, CGTMBlendAlphaShift, CGTMBlendWeightBaseShift);
            Inc(dx);
          end;
          Dec(dx, cTileWidth);
          Inc(dy);
        end;
      end
      else
      begin
        BackBuf := AFrameBuffer.GetBuffer(-TMI^.Attrs.MotionBackBufferOffset);
        for ty := 0 to cTileWidth - 1 do
        begin
          Move(BackBuf[dy + TMI^.Attrs.MotionY, dx + TMI^.Attrs.MotionX], FrontBuf[dy, dx], cTileWidth * SizeOf(Integer));
          Inc(dy);
        end;
      end;
      Dec(dy, cTileWidth);
    end
    else
    begin
      // draw fb (pal tile)

      Tile := Encoder.FTiles[TMI^.TileIdx];
      Tile^.BlitPalPixels(AFrameBuffer.GetBuffer, Encoder.FPalettes[Tile^.PalIdx].PaletteRGB, TMI^.VMirror, TMI^.HMirror, dy, dx);
    end;

    SpinEnter(@PKeyFrame.ReconstructLock);
    PKeyFrame.ReconstructErrCml += TMI^.Error;
    SpinLeave(@PKeyFrame.ReconstructLock);
  end;

begin
  DS := Encoder.FTilingDataset;
  if DS^.KNNSize <= 0 then
    Exit;

  Dec(ARadius);

  ProcThreadPool.DoParallelLocalProc(@DoXY, 0, Encoder.FTileMapSize - 1);

  PKeyFrame.LogPSNR;
end;

{ TTilingEncoder }

procedure TTilingEncoder.InitLuts;
var
  g, i, v, u, y, x: Int64;
begin
  // gamma

  for g := -1 to High(FGamma) do
    for i := 0 to High(Byte) do
      if g >= 0 then
        FGammaCorLut[g, i] := power(i / 255.0, FGamma[g])
      else
        FGammaCorLut[g, i] := i / 255.0;

  // inverse

  for i := 0 to High(FVecInv) do
    FVecInv[i] := iDivDef(1 shl cVecInvWidth, i shr 2, 0);

  // DCT

  i := 0;
  for v := 0 to cTileWidth - 1 do
    for u := 0 to cTileWidth - 1 do
      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
        begin
          FDCTLutDouble[False, i] := cos((x + 0.5) * u * PI / (cTileWidth)) * cos((y + 0.5) * v * PI / (cTileWidth)) * cDCTUVRatio[Min(v, 7), Min(u, 7)];
          FDCTLutDouble[True, i] := cos((x + 0.5) * u * PI / (cTileWidth * 2)) * cos((y + 0.5) * v * PI / (cTileWidth * 2)) * cDCTUVRatio[Min(v, 7), Min(u, 7)];
          FDCTLut[False, i] := FDCTLutDouble[False, i];
          FDCTLut[True, i] := FDCTLutDouble[True, i];
          Inc(i);
        end;

  // inverse DCT

  i := 0;
  for v := 0 to cTileWidth - 1 do
    for u := 0 to cTileWidth - 1 do
      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
        begin
          FInvDCTLutDouble[i] := cos((u + 0.5) * x * PI / (cTileWidth)) * cos((v + 0.5) * y * PI / (cTileWidth)) * cDCTUVRatio[Min(y, 7), Min(x, 7)] * 2 / (cTileWidth) * 2 / (cTileWidth);
          Inc(i);
        end;
end;

function TTilingEncoder.GammaCorrect(lut: Integer; x: Byte): TFloat;
begin
  Result := FGammaCorLut[lut, x];
end;

function TTilingEncoder.GammaUncorrect(lut: Integer; x: TFloat): Byte;
begin
  if lut >= 0 then
    x := power(Max(0, x), 1 / FGamma[lut]);
  Result := EnsureRange(Round(x * 255.0), 0, 255);
end;

procedure TTilingEncoder.Load;
var
  frmIdx, frmCnt, eqtc, startFrmIdx: Integer;
  fn: String;
  bmp: TPicture;
  wasAutoQ, manualKeyFrames: Boolean;
  qbTC: TFloat;
  FFMPEG: TFFMPEG;
begin
  eqtc := EqualQualityTileCount(FrameCount * FTileMapSize);
  wasAutoQ := (Length(FFrames) > 0) and (FGlobalTilingTileCount = round(FGlobalTilingQualityBasedTileCount * eqtc));

  ProgressRedraw(-1, '', esAll);

  FLoadedInputPath := '';
  ClearAll(False);

  ProgressRedraw(0, '', esLoad);

  // init Gamma LUTs

  InitLuts;

  // load video

  frmCnt := FFrameCountSetting;
  manualKeyFrames := False;
  FLoadedInputPath := FInputFileName;

  if FileExists(FLoadedInputPath) then
  begin
    FFMPEG := FFMPEG_Open(FLoadedInputPath, FScaling, False);
    try

      FFramesPerSecond := FFMPEG.FramesPerSecond;
      ReframeUI((FFMPEG.DstWidth - 1) div cTileWidth + 1, (FFMPEG.DstHeight - 1) div cTileWidth + 1);

      frmCnt := FFMPEG.FrameCount;
      if frmCnt > 0 then
        frmCnt -= FStartFrame;
      if FrameCountSetting > 0 then
        frmCnt := FrameCountSetting;

      WriteLn(frmCnt:8, ' frames, ', FFMPEG.DstWidth:4, ' x ', FFMPEG.DstHeight:4, ' @ ', FFramesPerSecond:6:3, ' fps');
    finally
      FFMPEG_Close(FFMPEG);
    end;
  end
  else
  begin
    FFramesPerSecond := 24.0;
    startFrmIdx := FStartFrame;
    manualKeyFrames := True;

    // automaticaly count frames if needed

    if frmCnt <= 0 then
    begin
      frmIdx := 0;
      repeat
        fn := Format(FLoadedInputPath, [frmIdx + startFrmIdx]);
        Inc(frmIdx);
      until not FileExists(fn);

      frmCnt := frmIdx - 1;
    end;

    // load frames bitmap data

    bmp := TPicture.Create;
    try
      bmp.Bitmap.PixelFormat:=pf32bit;
      bmp.LoadFromFile(Format(FLoadedInputPath, [startFrmIdx]));
      ReframeUI((bmp.Width - 1) div cTileWidth + 1, (bmp.Height - 1) div cTileWidth + 1);
    finally
      bmp.Free;
    end;
  end;

  ProgressRedraw(2, 'ProbeInputVideo');

  InitFrames(frmCnt);
  LoadInputVideo;

  ProgressRedraw(3, 'LoadInputVideo');

  FindKeyFrames(manualKeyFrames);

  if wasAutoQ or (FGlobalTilingTileCount <= 0) then
  begin
    qbTC := FGlobalTilingQualityBasedTileCount;
    SetGlobalTilingQualityBasedTileCount(0.0);
    SetGlobalTilingQualityBasedTileCount(qbTC);
  end;

  ProgressRedraw(4, 'FindKeyFrames');

  WriteLn(GetSettings);

  ProgressRedraw(5, 'PrintSettings');
end;

procedure TTilingEncoder.PreparePalettes;

  procedure DoQuant(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  begin
    if not InRange(AIndex, 0, High(FPalettes)) then
      Exit;

    DoQuantization(AIndex);
  end;

begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esPreparePalettes);

  DoPalettization;

  ProgressRedraw(1, 'Palettization');

  yakmo_set_num_threads(1);
  ProcThreadPool.DoParallelLocalProc(@DoQuant, 0, High(FPalettes));

  ProgressRedraw(2, 'Quantization');

  OptimizePalettes;

  ProgressRedraw(3, 'OptimizePalettes');
end;

procedure TTilingEncoder.Dither;

  procedure DoDither(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    Tile: PTile;
  begin
    if not InRange(AIndex, 0, High(FTiles)) then
      Exit;

    Tile := FTiles[AIndex];

    if not Tile^.Active then
      Exit;

    DitherTile(Tile^, FPalettes[Tile^.PalIdx].MixingPlan);
  end;

var
  palIdx: Integer;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esDither);

  // build ditherers
  for palIdx := 0 to High(FPalettes) do
    PreparePlan(FPalettes[palIdx].MixingPlan, FPalettes[palIdx].PaletteRGB);

  ProgressRedraw(1, 'BuildDitherers');

  ProcThreadPool.DoParallelLocalProc(@DoDither, 0, High(FTiles));

  ProgressRedraw(2, 'Dither');
end;

procedure TTilingEncoder.Reduce;
var
  kfIdx, tileCount: Integer;
  KF: TKeyFrame;
  Frame: TFrame;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esReduce);

  if FGlobalTilingUseTargetPSNR then
    SolveAvgPSNR(FGlobalTilingTargetPSNR)
  else
    SolveTileCount(FGlobalTilingTileCount);

  ProgressRedraw(1, 'Solve');

  for kfIdx := 0 to High(FKeyFrames) do
  begin
    KF := FKeyFrames[kfIdx];
    Frame := FFrames[KF.StartFrame];

    Frame.IntraReduce(max(2, Frame.GetUnpredictedTileCount));

    Write(kfIdx + 1:8, ' / ', Length(FKeyFrames):8, #13);
  end;

  ProgressRedraw(2, 'KeyFrameFirstFrameReduce');

  TransferTiles;
  MakeTilesUnique(True);
  ReindexTiles(True);

  ProgressRedraw(3, 'TransferTiles');
end;

procedure TTilingEncoder.PredictMotion;
var
  frmIdx, frmRelIdx, iBuf: Integer;
  isKFFF: Boolean;
  Frame: TFrame;
  FrameBuffer: TFrameBuffer;
  DCTBuffer: TDCTBuffer;
begin
  if (Length(FFrames) = 0) or (FMotionPredictRadius <= 0) then
    Exit;

  ProgressRedraw(0, '', esPredict);

  FrameBuffer := TFrameBuffer.Create(FMotionPredictMaxBufferedFrames + 1, FScreenHeight, FScreenWidth);
  DCTBuffer := TDCTBuffer.Create(FMotionPredictMaxBufferedFrames, (FScreenHeight - cTileWidth + 1) * (FScreenWidth - cTileWidth + 1));
  try
    for frmIdx := 0 to High(FFrames) do
    begin
      Frame := FFrames[frmIdx];

      isKFFF := Frame.Index = Frame.PKeyFrame.StartFrame;
      frmRelIdx := Frame.Index - Frame.PKeyFrame.StartFrame;

      Frame.AcquireFrameTiles;
      try
        Frame.DirectBlit(FrameBuffer.GetBuffer);

        if isKFFF then
        begin
          Frame.PrepareDCTs(DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
          Frame.Predict(FMotionPredictRadius, 0, DCTBuffer, FrameBuffer)
        end
        else
        begin
          for iBuf := 1 to Min(FMotionPredictMaxBufferedFrames, frmRelIdx) do
            Frame.Predict(FMotionPredictRadius, iBuf, DCTBuffer, FrameBuffer);
          Frame.PrepareDCTs(DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
        end;
      finally
        Frame.ReleaseFrameTiles;
      end;

      DCTBuffer.AdvanceFrame;
      FrameBuffer.AdvanceFrame;

      Write(frmIdx + 1:8, ' / ', Length(FFrames):8, #13);
    end;

    ProgressRedraw(1, 'PredictMotion');
  finally
    DCTBuffer.Free;
    FrameBuffer.Free;
  end;
end;

procedure TTilingEncoder.Reconstruct;
var
  frmIdx, frmRelIdx, iBuf: Integer;
  isKFFF: Boolean;
  Frame: TFrame;
  FrameBuffer: TFrameBuffer;
  DCTBuffer: TDCTBuffer;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esReconstruct);

  FKeyFramesLeft := Length(FKeyFrames);

  PrepareReconstruct;
  ProgressRedraw(1, 'PrepareReconstruct', esReconstruct);

  FrameBuffer := TFrameBuffer.Create(FMotionPredictMaxBufferedFrames + 1, FScreenHeight, FScreenWidth);
  DCTBuffer := TDCTBuffer.Create(FMotionPredictMaxBufferedFrames, (FScreenHeight - cTileWidth + 1) * (FScreenWidth - cTileWidth + 1));
  try
    for frmIdx := 0 to High(FFrames) do
    begin
      Frame := FFrames[frmIdx];

      isKFFF := Frame.Index = Frame.PKeyFrame.StartFrame;
      frmRelIdx := Frame.Index - Frame.PKeyFrame.StartFrame;

      Frame.AcquireFrameTiles;
      try
        Frame.ResetTileMap(True);

        if not isKFFF then
          for iBuf := 1 to Min(FMotionPredictMaxBufferedFrames, frmRelIdx) do
            Frame.Predict(FMotionPredictRadius, iBuf, DCTBuffer, FrameBuffer);

        Frame.Reconstruct(FMotionPredictRadius, FrameBuffer);
        Frame.PrepareDCTs(DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
      finally
        Frame.ReleaseFrameTiles;
      end;

      DCTBuffer.AdvanceFrame;
      FrameBuffer.AdvanceFrame;

      Write(frmIdx + 1:8, ' / ', Length(FFrames):8, #13);
    end;
  finally
    DCTBuffer.Free;
    FrameBuffer.Free;
    FinishReconstruct;
  end;

  ProgressRedraw(2, 'Reconstruct', esReconstruct);
end;

procedure TTilingEncoder.Reindex(AStep: TEncoderStep);

  procedure HandleTileIndex(ATileIndex: Integer);
  begin
    if ATileIndex >= 0 then
    begin
      Inc(Tiles[ATileIndex]^.UseCount);
      Tiles[ATileIndex]^.Active := True;
    end;
  end;

var
  frmIdx, sx, sy: Integer;
  tidx: Int64;
  TMI: PTileMapItem;
begin
  if FrameCount = 0 then
    Exit;

  ProgressRedraw(0, '', AStep);

  MakeTilesUnique(False);

  ProgressRedraw(1, 'MakeTilesUnique');

  for tidx := 0 to High(Tiles) do
  begin
    Tiles[tidx]^.UseCount := 0;
    Tiles[tidx]^.Active := False;
  end;

  for frmIdx := 0 to High(FFrames) do
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        TMI := @FFrames[frmIdx].TileMap[sy, sx];

        HandleTileIndex(TMI^.TileIdx);
      end;

  ProgressRedraw(2, 'UseCount');

  ReindexTiles(False);

  ProgressRedraw(3, 'Sort');
end;

procedure TTilingEncoder.Save;
var
  fs: TBufferedFileStream;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esSave);

  fs := TBufferedFileStream.Create(FOutputFileName, fmCreate or fmShareDenyWrite);
  try
    SaveStream(fs);
  finally
    fs.Free;
  end;

  ProgressRedraw(1, '');
end;

procedure TTilingEncoder.ReloadGTM(AFileName: String);
var
  fs: TBufferedFileStream;
begin
  ProgressRedraw(0, '', esLoad);

  fs := TBufferedFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    LoadStream(fs);
  finally
    fs.Free;
  end;

  ProgressRedraw(3, 'ReloadGTM');
end;

procedure TTilingEncoder.GeneratePNGs(AInput: Boolean);
var
  palPict: TPortableNetworkGraphic;
  frmIdx, palIdx, colIdx : Integer;
  page: TRenderPage;
  palData: TStringList;
  BMP: TBitmap;
begin
  palPict := TFastPortableNetworkGraphic.Create;

  palPict.Width := FScreenWidth;
  palPict.Height := FScreenHeight;
  palPict.PixelFormat := pf24bit;

  palData := TStringList.Create;
  try
    page := rpOutput;
    BMP := FOutputBitmap;
    if AInput then
    begin
      page := rpInput;
      BMP := FInputBitmap;
    end;

    palData.Clear;
    for palIdx := 0 to High(FPalettes) do
      for colIdx := 0 to FPaletteSize - 1 do
        palData.Add(IntToHex($ff000000 or FPalettes[palIdx].PaletteRGB[colIdx], 8));
    palData.SaveToFile(ChangeFileExt(FOutputFileName, '.txt'));

    for frmIdx := 0 to High(FFrames) do
    begin
      RenderFrame(frmIdx, page);

      palPict.Canvas.Draw(0, 0, BMP);
      palPict.SaveToFile(Format('%s_%.4d.png', [ChangeFileExt(FOutputFileName, ''), frmIdx]));
    end;
  finally
    palPict.Free;
    palData.Free;

    Render;
  end;
end;

procedure TTilingEncoder.GenerateY4M(AFileName: String; AInput: Boolean);
var
  fx, fy, frmIdx: Integer;
  page: TRenderPage;
  fs: TBufferedFileStream;
  Header, FrameHeader: String;
  ptr: PByte;
  yf, uf, vf: TFloat;
  r, g, b: Byte;
  py, pu, pv: PByte;
  FrameData: TByteDynArray;
  BMP: TBitmap;
begin
  fs := TBufferedFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  try
    Header := Format('YUV4MPEG2 W%d H%d F%d:1000000 Ip C444 XCOLORRANGE=LIMITED'#10, [FTileMapWidth * cTileWidth, FTileMapHeight * cTileWidth, round(FFramesPerSecond * 1000000)]);
    fs.Write(Header[1], length(Header));

    SetLength(FrameData, FTileMapWidth * cTileWidth * FTileMapHeight * cTileWidth * cColorCpns);

    page := rpOutput;
    BMP := FOutputBitmap;
    if AInput then
    begin
      page := rpInput;
      BMP := FInputBitmap;
    end;

    for frmIdx := 0 to High(FFrames) do
    begin
      FrameHeader := 'FRAME '#10;
      fs.Write(FrameHeader[1], Length(FrameHeader));

      RenderFrame(frmIdx, page);

      py := @FrameData[0 * Length(FrameData) div cColorCpns];
      pu := @FrameData[1 * Length(FrameData) div cColorCpns];
      pv := @FrameData[2 * Length(FrameData) div cColorCpns];

      BMP.BeginUpdate;
      try
        for fy := 0 to BMP.Height - 1 do
        begin
          ptr := PByte(BMP.ScanLine[fy]);
          for fx := 0 to BMP.Width - 1 do
          begin
            b := ptr^; Inc(ptr);
            g := ptr^; Inc(ptr);
            r := ptr^; Inc(ptr);
            Inc(ptr); // alpha

            RGBToYUV(r, g, b, yf, uf, vf, 1.0);

            py^ := EnsureRange(Round(yf), 0, High(Byte)); Inc(py);
            pu^ := EnsureRange(Round(uf), 0, High(Byte)); Inc(pu);
            pv^ := EnsureRange(Round(vf), 0, High(Byte)); Inc(pv);
          end;
        end;
      finally
        BMP.EndUpdate;
      end;

      fs.Write(FrameData[0], Length(FrameData));
    end;
  finally
    fs.Free;

    Render;
  end;
end;

function TTilingEncoder.PearsonCorrelation(const x: TFloatDynArray; const y: TFloatDynArray): TFloat;
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

function TTilingEncoder.GetKeyFrameCount: Integer;
begin
  Result := Length(FKeyFrames);
end;

function TTilingEncoder.GetMaxThreadCount: Integer;
begin
 Result := ProcThreadPool.MaxThreadCount;
end;

function TTilingEncoder.GetTiles: PTileDynArray;
begin
  Result := FTiles;
end;

function TTilingEncoder.GetFrameCount: Integer;
begin
  Result := Length(FFrames);
end;

function TTilingEncoder.GetRenderGammaValue: Double;
begin
  Result := FGamma[1];
end;

function TTilingEncoder.GetSettings: AnsiString;
var
  tmpFN: String;
begin
  tmpFN := GetTempFileName;
  try
    SaveSettings(tmpFN);
    Result := ReadFileToString(tmpFN);
  finally
    DeleteFile(tmpFN);
  end;
end;

procedure TTilingEncoder.SetSettings(ASettings: AnsiString);
var
  tmpFN: String;
  fs: TFileStream;
begin
  tmpFN := GetTempFileName;
  try
    fs := TFileStream.Create(tmpFN, fmCreate or fmShareDenyWrite);
    try
      fs.WriteAnsiString(ASettings);
    finally
      fs.Free;
    end;
    LoadSettings(tmpFN);
  finally
    DeleteFile(tmpFN);
  end;
end;

procedure TTilingEncoder.PreparePlan(var Plan: TMixingPlan; const pal: array of Integer);
var
  i, cnt, r, g, b: Integer;
begin
  FillChar(Plan, SizeOf(Plan), 0);

  Plan.Y2MixedColors := FDitheringYliluoma2MixedColors;
  SetLength(Plan.LumaPal, length(pal));
  SetLength(Plan.Y2Palette, length(pal));
  SetLength(Plan.Remap, length(pal));

  cnt := 0;
  for i := 0 to High(pal) do
  begin
    if pal[i] = cDitheringNullColor then
      Continue;

    FromRGB(pal[i], r, g, b);

    Plan.LumaPal[cnt] := r*cRedMul + g*cGreenMul + b*cBlueMul;

    Plan.Y2Palette[cnt][0] := r;
    Plan.Y2Palette[cnt][1] := g;
    Plan.Y2Palette[cnt][2] := b;
    Plan.Y2Palette[cnt][3] := Plan.LumaPal[cnt] div cLumaDiv;

    Plan.Remap[cnt] := i;
    Inc(cnt);
  end;

  SetLength(Plan.LumaPal, cnt);
  SetLength(Plan.Y2Palette, cnt);
  SetLength(Plan.Remap, cnt);
end;

procedure TTilingEncoder.TerminatePlan(var Plan: TMixingPlan);
begin
  SetLength(Plan.LumaPal, 0);
  SetLength(Plan.Y2Palette, 0);
  SetLength(Plan.Remap, 0);
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

class function TTilingEncoder.ColorCompare(r1, g1, b1, r2, g2, b2: Int64): Int64;
var
  luma1, luma2, lumadiff, diffR, diffG, diffB: Int64;
begin
  luma1 := r1 * cRedMul + g1 * cGreenMul + b1 * cBlueMul;
  luma2 := r2 * cRedMul + g2 * cGreenMul + b2 * cBlueMul;
  lumadiff := (luma1 - luma2) div cLumaDiv;
  diffR := r1 - r2;
  diffG := g1 - g2;
  diffB := b1 - b2;
  Result := (diffR * diffR) * cRGBw;
  Result += (diffG * diffG) * cRGBw;
  Result += (diffB * diffB) * cRGBw;
  Result += (lumadiff * lumadiff) shl 5;
end;

function TTilingEncoder.DeviseBestMixingPlanYliluoma(var Plan: TMixingPlan; col: Integer; var List: array of Byte): Integer;
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
    push rdx

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
    mov ecx, cLumaDiv
    xor edx, edx
    div ecx

    pinsrd xmm4, eax, 3

    mov rax, 1 or (1 shl 32)
    pinsrq xmm5, rax, 0
    pinsrq xmm5, rax, 1

    mov rax, cRGBw or (cRGBw shl 32)
    pinsrq xmm6, rax, 0
    mov rax, cRGBw or (32 shl 32)
    pinsrq xmm6, rax, 1

    pop rdx
    pop rcx
    pop rbx
    pop rax
  end;
{$endif}

  VecInv := @FVecInv[0];
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

procedure TTilingEncoder.DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: array of Byte);
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

    least_penalty := High(Int64);
    chosen := c mod length(Plan.Y2Palette);
    for index := 0 to length(Plan.Y2Palette) - 1 do
    begin
      penalty := ColorCompare(t[0], t[1], t[2], Plan.Y2Palette[index][0], Plan.Y2Palette[index][1], Plan.Y2Palette[index][2]);
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

function TTilingEncoder.GetTileCount(AActiveOnly: Boolean): Integer;
var
  tidx: Int64;
begin
  if AActiveOnly then
  begin
   Result := 0;
    for tidx := 0 to High(Tiles) do
      if Tiles[tidx]^.Active then
        Inc(Result);
  end
  else
  begin
    Result := Length(Tiles);
  end;
end;

procedure TTilingEncoder.ReframeUI(AWidth, AHeight: Integer);
begin
  FTileMapWidth := AWidth;
  FTileMapHeight := AHeight;

  FTileMapSize := FTileMapWidth * FTileMapHeight;
  FScreenWidth := FTileMapWidth * cTileWidth;
  FScreenHeight := FTileMapHeight * cTileWidth;

  FRenderFrameBuffer.Free;
  FRenderFrameBuffer := TFrameBuffer.Create(FMotionPredictMaxBufferedFrames + 1, FScreenHeight, FScreenWidth);

  FInputBitmap.Width:=FScreenWidth;
  FInputBitmap.Height:=FScreenHeight;
  FInputBitmap.PixelFormat:=pf32bit;

  FOutputBitmap.Width:=FScreenWidth;
  FOutputBitmap.Height:=FScreenHeight;
  FOutputBitmap.PixelFormat:=pf32bit;

  FTilesBitmap.Width:=FScreenWidth;
  FTilesBitmap.Height:=FScreenHeight;
  FTilesBitmap.PixelFormat:=pf32bit;

  FPaletteBitmap.Width := FPaletteSize;
  FPaletteBitmap.Height := FPaletteCount;
  FPaletteBitmap.PixelFormat:=pf32bit;
end;

procedure TTilingEncoder.InitFrames(AFrameCount: Integer);
var
  frmIdx: Integer;
begin
  SetLength(FFrames, AFrameCount);
  for frmIdx := 0 to High(FFrames) do
    FFrames[frmIdx] := TFrame.Create(Self, frmIdx);
end;

procedure TTilingEncoder.DitherTile(var ATile: TTile; var Plan: TMixingPlan);
var
  x, y: Integer;
  count, map_value: Integer;
  TKList: array[0 .. cDitheringLen - 1] of Byte;
  YilList: array[0 .. cDitheringListLen - 1] of Byte;
begin
  // put tile back in its natural mirrors for ordered dithering to work properly
  if ATile.HMirror_Initial then HMirrorTile(ATile);
  if ATile.VMirror_Initial then VMirrorTile(ATile);
  try
    if FDitheringUseThomasKnoll then
    begin
      for y := 0 to (cTileWidth - 1) do
        for x := 0 to (cTileWidth - 1) do
        begin
          map_value := cDitheringMap[((y and 7) shl 3) or (x and 7)];
          DeviseBestMixingPlanThomasKnoll(Plan, ATile.RGBPixels[y, x], TKList);
          ATile.PalPixels[y, x] := Plan.Remap[TKList[map_value]];
        end;
    end
    else
    begin
      for y := 0 to (cTileWidth - 1) do
        for x := 0 to (cTileWidth - 1) do
        begin
          map_value := cDitheringMap[((y and 7) shl 3) or (x and 7)];
          count := DeviseBestMixingPlanYliluoma(Plan, ATile.RGBPixels[y, x], YilList);
          map_value := (map_value * count) shr 6;
          ATile.PalPixels[y, x] := Plan.Remap[YilList[map_value]];
        end;
    end;
  finally
    if ATile.HMirror_Initial then HMirrorTile(ATile);
    if ATile.VMirror_Initial then VMirrorTile(ATile);
  end;
end;

// from https://lists.freepascal.org/pipermail/fpc-announce/2006-September/000508.html
generic procedure TTilingEncoder.WaveletGS<T, PT>(Data: PT; Output: PT; dx, dy, depth: cardinal);
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

generic procedure TTilingEncoder.DeWaveletGS<T, PT>(wl: PT; pic: PT; dx, dy, depth: longint);
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

procedure TTilingEncoder.SetDitheringYliluoma2MixedColors(AValue: Integer);
begin
  if FDitheringYliluoma2MixedColors = AValue then Exit;
  FDitheringYliluoma2MixedColors := EnsureRange(AValue, 1, 16);
end;

procedure TTilingEncoder.SetFrameCountSetting(AValue: Integer);
begin
  if FFrameCountSetting = AValue then Exit;
  FFrameCountSetting := Max(0, AValue);
end;

procedure TTilingEncoder.SetFramesPerSecond(AValue: Double);
begin
  if FFramesPerSecond = AValue then Exit;
  FFramesPerSecond := Max(0.0, AValue);
end;

procedure TTilingEncoder.SetGlobalTilingQualityBasedTileCount(AValue: Double);
var
  eqtc, RawTileCount: Int64;
begin
  if FGlobalTilingQualityBasedTileCount = AValue then Exit;
  FGlobalTilingQualityBasedTileCount := AValue;

  eqtc := EqualQualityTileCount(FrameCount * FTileMapSize);

  RawTileCount := Length(FFrames) * FTileMapSize;
  FGlobalTilingTileCount := min(round(AValue * eqtc), RawTileCount);
end;

procedure TTilingEncoder.SetMaxThreadCount(AValue: Integer);
begin
 if ProcThreadPool.MaxThreadCount = AValue then Exit;
 ProcThreadPool.MaxThreadCount := max(1, AValue);
end;

procedure TTilingEncoder.SetPaletteCount(AValue: Integer);
begin
  if FPaletteCount = AValue then Exit;
  FPaletteCount := EnsureRange(AValue, 1, 65536);
end;

procedure TTilingEncoder.SetPaletteSize(AValue: Integer);
begin
  if FPaletteSize = AValue then Exit;
  FPaletteSize := EnsureRange(AValue, 2, 64);
end;

procedure TTilingEncoder.SetGlobalTilingTargetPSNR(AValue: Double);
begin
  if FGlobalTilingTargetPSNR = AValue then Exit;
  FGlobalTilingTargetPSNR := EnsureRange(AValue, 0, cBestPSNR);
end;

procedure TTilingEncoder.SetGlobalTilingTileCount(AValue: Integer);
var
  RawTileCount: Integer;
begin
  if FGlobalTilingTileCount = AValue then Exit;
  FGlobalTilingTileCount := AValue;

  RawTileCount := Length(FFrames) * FTileMapSize;
  if RawTileCount <> 0 then
    FGlobalTilingTileCount := EnsureRange(FGlobalTilingTileCount, 0, RawTileCount)
  else
    FGlobalTilingTileCount := max(FGlobalTilingTileCount, 0);
end;

procedure TTilingEncoder.SetScaling(AValue: Double);
begin
  if FScaling = AValue then Exit;
  FScaling := Max(0.01, AValue);
end;

procedure TTilingEncoder.SetShotTransCorrelLoThres(AValue: Double);
begin
 if FShotTransCorrelLoThres = AValue then Exit;
 FShotTransCorrelLoThres := EnsureRange(AValue, -1.0, 1.0);
end;

procedure TTilingEncoder.SetShotTransMaxSecondsPerKF(AValue: Double);
begin
 if FShotTransMaxSecondsPerKF = AValue then Exit;
 FShotTransMaxSecondsPerKF := max(0.0, AValue);
end;

procedure TTilingEncoder.SetShotTransMinSecondsPerKF(AValue: Double);
begin
 if FShotTransMinSecondsPerKF = AValue then Exit;
 FShotTransMinSecondsPerKF := max(0.0, AValue);
end;

procedure TTilingEncoder.SetStartFrame(AValue: Integer);
begin
  if FStartFrame = AValue then Exit;
  FStartFrame := Max(0, AValue);
end;

procedure TTilingEncoder.SetRenderFrameIndex(AValue: Integer);
begin
  if FRenderFrameIndex = AValue then Exit;
  FRenderFrameIndex := EnsureRange(AValue, 0, High(FFrames));
end;

procedure TTilingEncoder.SetRenderGammaValue(AValue: Double);
begin
  if FGamma[1] = AValue then Exit;
  FGamma[1] := Max(0.0, AValue);
  InitLuts;
end;

procedure TTilingEncoder.SetRenderPaletteIndex(AValue: Integer);
begin
  if FRenderPaletteIndex = AValue then Exit;
  FRenderPaletteIndex := EnsureRange(AValue, -1, FPaletteCount - 1);
end;

procedure TTilingEncoder.SetRenderTilePage(AValue: Integer);
begin
  if FRenderTilePage = AValue then Exit;
  FRenderTilePage := Max(0, AValue);
end;

procedure TTilingEncoder.SetMotionPredictRadius(AValue: Integer);
begin
  if FMotionPredictRadius = AValue then Exit;
  FMotionPredictRadius := EnsureRange(AValue, 0, -Low(ShortInt));
end;

procedure TTilingEncoder.SetMotionPredictMaxBufferedFrames(AValue: Integer);
begin
  if FMotionPredictMaxBufferedFrames = AValue then Exit;
  FMotionPredictMaxBufferedFrames := EnsureRange(AValue, 1, 3);
end;

procedure TTilingEncoder.ConvertToCpnPixels(const ATile: TTile; FromPal, UseLAB, VMirror, HMirror: Boolean; const APalette: TIntegerDynArray; out ACpnPixel: TCpnPixels);

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
      RGBToYUV(r, g, b, yy, uu, vv, cYUVScale);
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

procedure TTilingEncoder.ComputeCpnPixelsPsyVisFeatures(const ACpnPixel: TCpnPixels; Mode: TPsyVisMode; ColorCpns: Integer; ADCT: PDCTScalar);
var
  u, v, cpn: Integer;
  z: Double;
  pLut: PSingle;
  pDCT: PSmallInt;
  pSnake: PByte;
begin
  Assert(not (Mode in [pvsWavelets]), 'Wavelets on SmallInt vector unimplemented!');

  for cpn := 0 to ColorCpns - 1 do
  begin
    pDCT := @ADCT[cpn * sqr(cTileWidth)];
    pLut := @FDCTLut[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
    pSnake := @cDCTSnake[0];
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
  		  z := DCTInner_asm(@ACpnPixel[cpn, 0, 0], pLut);

        if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
           z *= cDCTWeights[cpn, v, u];

        pDCT[pSnake^] := Round(z);
        Inc(pLut, Sqr(cTileWidth));
        Inc(pSnake);
      end;
  end;
end;

procedure TTilingEncoder.ComputeTilePsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; FromPal, UseLAB, VMirror,
  HMirror: Boolean; ColorCpns: Integer; const APalette: TIntegerDynArray; ADCT: PDouble);
var
  i, u, v, cpn: Integer;
  z: Double;
  CpnPixels: TCpnPixels;
  CpnPixelsDouble: TCpnPixelsDouble;
  pDCT, pLut: PDouble;
  LocalDCT: array[0..cTileDCTSize - 1] of Double;
begin
  ConvertToCpnPixels(ATile, FromPal, UseLAB, VMirror, HMirror, APalette, CpnPixels);

  for cpn := 0 to ColorCpns - 1 do
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
        CpnPixelsDouble[cpn, v, u] := CpnPixels[cpn, v, u];

  if Mode = pvsWavelets then
  begin
   for cpn := 0 to ColorCpns - 1 do
   begin
     pDCT := @LocalDCT[cpn * sqr(cTileWidth)];
     specialize WaveletGS<Double, PDouble>(@CpnPixelsDouble[cpn, 0, 0], pDCT, cTileWidth, cTileWidth, 2);
   end;
  end
  else
  begin
    for cpn := 0 to ColorCpns - 1 do
    begin
      pDCT := @LocalDCT[cpn * sqr(cTileWidth)];
      pLut := @FDCTLutDouble[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
      for v := 0 to cTileWidth - 1 do
        for u := 0 to cTileWidth - 1 do
        begin
          z := specialize DCTInner<PDouble>(@CpnPixelsDouble[cpn, 0, 0], pLut, 1);

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

procedure TTilingEncoder.ComputeInvTilePsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; UseLAB: Boolean; ColorCpns: Integer;
 var ATile: TTile);
var
  i, u, v, x, y, cpn: Integer;
  CpnPixels: TCpnPixelsDouble;
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
      Result := YUVToRGB(yy, uu, vv, cYUVScale);
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
      pLut := @FInvDCTLutDouble[0];

      for y := 0 to cTileWidth - 1 do
        for x := 0 to cTileWidth - 1 do
        begin
          pCpn^ := specialize DCTInner<PDouble>(@LocalDCT[cpn * sqr(cTileWidth)], pLut, 1);
          Inc(pCpn);
          Inc(pLut, Sqr(cTileWidth));
        end;
    end;
  end;

  for y := 0 to (cTileWidth - 1) do
    for x := 0 to (cTileWidth - 1) do
      ATile.RGBPixels[y, x] := FromCpn(x, y);
end;

class procedure TTilingEncoder.VMirrorTile(var ATile: TTile; APalOnly: Boolean);
var
  j, i: Integer;
  v, sv: Integer;
begin
  // hardcode vertical mirror into the tile

  for j := 0 to cTileWidth div 2 - 1  do
    for i := 0 to cTileWidth - 1 do
    begin
      if ATile.HasPalPixels then
      begin
        v := ATile.PalPixels[j, i];
        sv := ATile.PalPixels[cTileWidth - 1 - j, i];
        ATile.PalPixels[j, i] := sv;
        ATile.PalPixels[cTileWidth - 1 - j, i] := v;
      end;

      if ATile.HasRGBPixels and not APalOnly then
      begin
        v := ATile.RGBPixels[j, i];
        sv := ATile.RGBPixels[cTileWidth - 1 - j, i];
        ATile.RGBPixels[j, i] := sv;
        ATile.RGBPixels[cTileWidth - 1 - j, i] := v;
      end;
    end;
end;

class procedure TTilingEncoder.HMirrorTile(var ATile: TTile; APalOnly: Boolean);
var
  i, j: Integer;
  v, sv: Integer;
begin
  // hardcode horizontal mirror into the tile

  for j := 0 to cTileWidth - 1 do
    for i := 0 to cTileWidth div 2 - 1  do
    begin
      if ATile.HasPalPixels then
      begin
        v := ATile.PalPixels[j, i];
        sv := ATile.PalPixels[j, cTileWidth - 1 - i];
        ATile.PalPixels[j, i] := sv;
        ATile.PalPixels[j, cTileWidth - 1 - i] := v;
      end;

      if ATile.HasRGBPixels and not APalOnly then
      begin
        v := ATile.RGBPixels[j, i];
        sv := ATile.RGBPixels[j, cTileWidth - 1 - i];
        ATile.RGBPixels[j, i] := sv;
        ATile.RGBPixels[j, cTileWidth - 1 - i] := v;
      end;
    end;
end;

procedure DoLoadFFMPEGFrame(AIndex, AWidth, AHeight:Integer; AFrameData: PInteger; AUserParameter: Pointer);
var
  Encoder: TTilingEncoder;
  frmIdx: Integer;
begin
  Encoder := TTilingEncoder(AUserParameter);
  frmIdx := AIndex - Encoder.FStartFrame;

  Encoder.FFrames[frmIdx].LoadFromImage(AWidth, AHeight, AFrameData);
end;

procedure TTilingEncoder.LoadInputVideo;
var
  i: Integer;
  FFMPEG: TFFMPEG;
  PNG: TPortableNetworkGraphic;
  frmIdx: Integer;
begin
  if FileExists(FLoadedInputPath) then
  begin
    FFMPEG := FFMPEG_Open(FLoadedInputPath, FScaling, True);
    try
      FFMPEG_LoadFrames(FFMPEG, FStartFrame, Length(FFrames), @DoLoadFFMPEGFrame, Self);
    finally
      FFMPEG_Close(FFMPEG);
    end;
  end
  else
  begin
    PNG := TPortableNetworkGraphic.Create;
    try
      PNG.PixelFormat:=pf32bit;
      for frmIdx := 0 to High(FFrames) do
      begin
        PNG.LoadFromFile(Format(FLoadedInputPath, [frmIdx + FStartFrame]));
        FFrames[frmIdx].LoadFromImage(PNG.RawImage.Description.Width, PNG.RawImage.Description.Height, PInteger(PNG.RawImage.Data));
      end;
    finally
      PNG.Free;
    end;
  end;

  // wait LoadFromImageFinishedEvent (ensures all frames processed) (MaxThreadCount concurent threads is already ensured)

  for i := max(0, Length(FFrames) - MaxThreadCount) to High(FFrames) do
    WaitForSingleObject(FFrames[i].LoadFromImageFinishedEvent, INFINITE);
end;

procedure TTilingEncoder.FindKeyFrames(AManualMode: Boolean);
var
  frmIdx, kfIdx, lastKFIdx: Integer;
  correl: TFloat;
  kfReason: TKeyFrameReason;
  sfr, efr: Integer;
begin
  // find keyframes

  SetLength(FKeyFrames, Length(FFrames));
  kfIdx := 0;
  lastKFIdx := Low(Integer);
  for frmIdx := 0 to High(FFrames) do
  begin
    correl := FFrames[frmIdx].InterframeCorrelation;

    //writeln(frmIdx:8,correl:8:3,dist:12:3);

    kfReason := kfrNone;
    if AManualMode then
    begin
      if FileExists(Format(ChangeFileExt(FLoadedInputPath, '.kf'), [frmIdx + StartFrame])) or (frmIdx = 0) then
        kfReason := kfrManual;
    end
    else
    begin
      if (kfReason = kfrNone) and (frmIdx = 0) then
        kfReason := kfrManual;

      if (kfReason = kfrNone) and (correl < FShotTransCorrelLoThres) then
        kfReason := kfrDecorrelation;

      if (kfReason = kfrNone) and ((frmIdx - lastKFIdx) >= (FShotTransMaxSecondsPerKF * FFramesPerSecond)) then
        kfReason := kfrLength;

      if (frmIdx - lastKFIdx) < (FShotTransMinSecondsPerKF * FFramesPerSecond) then
        kfReason := kfrNone;
    end;

    if kfReason <> kfrNone then
    begin
      FKeyFrames[kfIdx] := TKeyFrame.Create(Self, kfIdx, 0, 0);
      FKeyFrames[kfIdx].Reason := kfReason;

      Inc(kfIdx);

      lastKFIdx := frmIdx;
    end;

    FFrames[frmIdx].PKeyFrame := FKeyFrames[kfIdx - 1];
  end;

  SetLength(FKeyFrames, kfIdx);

  for kfIdx := 0 to High(FKeyFrames) do
  begin
    sfr := High(Integer);
    efr := Low(Integer);

    for frmIdx := 0 to High(FFrames) do
      if FFrames[frmIdx].PKeyFrame = FKeyFrames[kfIdx] then
      begin
        sfr := Min(sfr, frmIdx);
        efr := Max(efr, frmIdx);
      end;

    FKeyFrames[kfIdx].StartFrame := sfr;
    FKeyFrames[kfIdx].EndFrame := efr;
    FKeyFrames[kfIdx].FrameCount := efr - sfr + 1;

    WriteLn('KF: ', FKeyFrames[kfIdx].StartFrame:8, ' (', kfIdx:3, ') FCnt: ', FKeyFrames[kfIdx].FrameCount:3, ' Reason: ', Copy(GetEnumName(TypeInfo(TKeyFrameReason), Ord(FKeyFrames[kfIdx].Reason)), 4));
  end;
end;

procedure TTilingEncoder.ClearAll(AKeepFrames: Boolean);
var
  i: Integer;
begin
  if not AKeepFrames then
  begin
    for i := 0 to High(FFrames) do
      FFrames[i].Free;
    SetLength(FFrames, 0);
  end;

  for i := 0 to High(FKeyFrames) do
    FKeyFrames[i].Free;
  SetLength(FKeyFrames, 0);

  FreeAndNil(FRenderFrameBuffer);

  TTile.Array1DDispose(FTiles);
end;

procedure TTilingEncoder.RenderFrame(AFrameIndex: Integer; APage: TRenderPage);

  procedure DrawTile(const ABuffer: TIntegerDynArray2; const APal: TIntegerDynArray; ATilePtr: PTile; ASY, ASX: Integer; AHmirror, AVmirror, AForceActive: Boolean); inline;
  var
    col, tx, ty, txm, tym: Integer;
    psl: PInteger;
  begin
    for ty := 0 to cTileWidth - 1 do
    begin
      psl := @ABuffer[(ASY shl cTileWidthBits) + ty, ASX shl cTileWidthBits];

      tym := ty;
      if AVmirror then tym := cTileWidth - 1 - tym;

      for tx := 0 to cTileWidth - 1 do
      begin
        txm := tx;
        if AHmirror then txm := cTileWidth - 1 - txm;

        col := $ff00ff;
        if ATilePtr^.Active or AForceActive then
        begin
          if Assigned(APal) then
          begin
            if ATilePtr^.HasPalPixels then
              col := APal[ATilePtr^.PalPixels[tym, txm]];
          end
          else
          begin
            if ATilePtr^.HasRGBPixels then
              col := ATilePtr^.RGBPixels[tym, txm];
          end;
        end;

        psl^ := col;
        Inc(psl);
      end;
    end;
  end;

  procedure DrawDummyTile(const ABuffer: TIntegerDynArray2; ASY, ASX: Integer; AColor: Integer = $303030);
  const
    cTileData: array[0..7] of Byte = ($81, $42, $24, $18, $18, $24, $42, $81);
  var
    d: Byte;
    tx, ty: Integer;
    psl: PInteger;
  begin
    for ty := 0 to cTileWidth - 1 do
    begin
      psl := @ABuffer[(ASY shl cTileWidthBits) + ty, ASX shl cTileWidthBits];
      d := cTileData[ty];

      for tx := 0 to cTileWidth - 1 do
      begin
        psl^ := IfThen(d and 1 <> 0, AColor, $000000);
        Inc(psl);
        d := d shr 1;
      end;
    end;
  end;

  procedure BlitBuffer(const ABuffer: TIntegerDynArray2; ABitmap: PInteger; ASY, ASX, ABitmapStride: Integer); inline;
  var
    by, bx, col: Integer;
    r, g, b: Byte;
    pi, po: PInteger;
  begin
    for by := 0 to High(ABuffer) do
    begin
      pi := @ABuffer[by, 0];
      po := @ABitmap[((ASY shl cTileWidthBits) + by) * ABitmapStride + (ASX shl cTileWidthBits)];

      if FRenderUseGamma then
      begin
        for bx := 0 to High(ABuffer[0]) do
        begin
          col := pi^;

          FromRGB(col, r, g, b);
          r := round(GammaCorrect(1, r) * 255.0);
          g := round(GammaCorrect(1, g) * 255.0);
          b := round(GammaCorrect(1, b) * 255.0);
          col := ToRGB(b, g, r);

          po^ := col;
          Inc(pi);
          Inc(po);
        end;
      end
      else
      begin
        for bx := 0 to High(ABuffer[0]) do
        begin
          po^ := SwapRB(pi^);
          Inc(pi);
          Inc(po);
        end;
      end;
    end;
  end;

var
  i, j, sx, sy, globalTileCount, col, off, siz: Integer;
  hmir, vmir: Boolean;
  tidx: Int64;
  errCml: UInt64;
  pFB: PInteger;
  TempTile, tilePtr: PTile;
  TempBuf: TIntegerDynArray2;
  TMI: PTileMapItem;
  Frame: TFrame;
  pal: TIntegerDynArray;
  canvas: TCanvas;
begin
  if Length(FFrames) <= 0 then
    Exit;

  Frame := FFrames[AFrameIndex];

  if not Assigned(Frame) or not Assigned(Frame.PKeyFrame) then
    Exit;

  TempTile := TTile.New(True, False);
  SetLength(TempBuf, cTileWidth, cTileWidth);
  try

    // Global

    globalTileCount := GetTileCount(False);

    FRenderTitleText := 'Global: ' + IntToStr(globalTileCount) + ' / Frame #' + IntToStr(Frame.Index) + IfThen(Frame.PKeyFrame.StartFrame = Frame.Index, ' [KF]', '     ') + ' : ' + IntToStr(Frame.GetUsedTileCount);

    // "Input" tab

    if APage = rpInput then
    begin
      FInputBitmap.Canvas.Brush.Color := clBlack;
      FInputBitmap.Canvas.Brush.Style := bsSolid;
      FInputBitmap.Canvas.FillRect(FInputBitmap.Canvas.ClipRect);
      FInputBitmap.Canvas.Brush.Color := $202020;
      FInputBitmap.Canvas.Brush.Style := bsDiagCross;
      FInputBitmap.Canvas.FillRect(FInputBitmap.Canvas.ClipRect);

      FInputBitmap.BeginUpdate;
      Frame.AcquireFrameTiles;
      try
        pFB := PInteger(FInputBitmap.RawImage.Data);

        for sy := 0 to FTileMapHeight - 1 do
          for sx := 0 to FTileMapWidth - 1 do
          begin
            tilePtr := Frame.FrameTiles[sy * FTileMapWidth + sx];

            hmir := tilePtr^.HMirror_Initial;
            vmir := tilePtr^.VMirror_Initial;

            if not FRenderMirrored then
            begin
              hmir := False;
              vmir := False;
            end;

            DrawTile(TempBuf, nil, tilePtr, 0, 0, hmir, vmir, True);

            BlitBuffer(TempBuf, pFB, sy, sx, FInputBitmap.Width);
          end;
      finally
        FInputBitmap.EndUpdate;
        Frame.ReleaseFrameTiles;
      end;
    end;

    // "Output" tab

    if APage = rpOutput then
    begin
      if Frame.Index <> FRenderPrevFrameIndex then
        FRenderFrameBuffer.AdvanceFrame;

      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMI := @Frame.TileMap[sy, sx];

          if TMI^.IsPredicted and FRenderPredicted then
          begin
            if TMI^.IsBlended then
              TempTile^.BlendRGBPixels(
                FRenderFrameBuffer.GetBuffer(-1), FRenderFrameBuffer.GetBuffer(-2),
                sy shl cTileWidthBits, sx shl cTileWidthBits,
                TMI^.Attrs.BlendAlpha, TMI^.Attrs.BlendWeight)
            else
              TempTile^.CopyRGBPixels(
                FRenderFrameBuffer.GetBuffer(-TMI^.Attrs.MotionBackBufferOffset),
                (sy shl cTileWidthBits) + TMI^.Attrs.MotionY,
                (sx shl cTileWidthBits) + TMI^.Attrs.MotionX);
            DrawTile(FRenderFrameBuffer.GetBuffer, nil, TempTile, sy, sx, False, False, True)
          end
          else if InRange(TMI^.TileIdx, 0, High(Tiles)) then
          begin
            tilePtr := FTiles[TMI^.TileIdx];

            pal := nil;
            if FRenderOutputDithered then
              if FRenderPaletteIndex < 0 then
              begin
                if not InRange(tilePtr^.PalIdx, 0, High(FPalettes)) then
                begin
                  DrawDummyTile(FRenderFrameBuffer.GetBuffer, sy, sx);
                  Continue;
                end;
                pal := FPalettes[tilePtr^.PalIdx].PaletteRGB;
              end
              else
              begin
                if FRenderPaletteIndex <> tilePtr^.PalIdx then
                begin
                  DrawDummyTile(FRenderFrameBuffer.GetBuffer, sy, sx);
                  Continue;
                end;
                pal := FPalettes[FRenderPaletteIndex].PaletteRGB;
              end;

            hmir := TMI^.HMirror;
            vmir := TMI^.VMirror;

            if not FRenderMirrored then
            begin
              hmir := False;
              vmir := False;
            end;

            DrawTile(FRenderFrameBuffer.GetBuffer, pal, tilePtr, sy, sx, hmir, vmir, False);
          end
          else
          begin
            DrawDummyTile(FRenderFrameBuffer.GetBuffer, sy, sx);
          end;
        end;

      FOutputBitmap.BeginUpdate;
      try
        pFB := PInteger(FOutputBitmap.RawImage.Data);

        BlitBuffer(FRenderFrameBuffer.GetBuffer, pFB, 0, 0, FOutputBitmap.Width);
      finally
        FOutputBitmap.EndUpdate;
      end;

      if not FRenderPredicted then
      begin
        canvas := FOutputBitmap.Canvas;

        canvas.Pen.Style := psSolid;
        canvas.Brush.Style := bsSolid;

        off := cTileWidth div 2;

        for sy := 0 to FTileMapHeight - 1 do
          for sx := 0 to FTileMapWidth - 1 do
          begin
            TMI := @Frame.TileMap[sy, sx];

            if TMI^.IsPredicted then
            begin
              if TMI^.IsBlended then
              begin
                siz := 0;
                col := $ff - (TMI^.Attrs.BlendAlpha * 3 + Abs(TMI^.Attrs.BlendWeight) * 2);
                col := ToRGB(col, $ff, col);

                canvas.Brush.Color := col;
                canvas.FillRect(
                  (sx shl cTileWidthBits) - 2 + off, (sy shl cTileWidthBits) - 2 + off,
                  (sx shl cTileWidthBits) + 2 + off, (sy shl cTileWidthBits) + 2 + off);
              end
              else
              begin
                siz := Abs(TMI^.Attrs.MotionX) + Abs(TMI^.Attrs.MotionY);

                if TMI^.Attrs.MotionBackBufferOffset > 1 then
                begin
                  col := Max(0, $c0 - siz);
                  col := ToRGB(col, col, $ff);
                end
                else
                begin
                  col := Max(0, $ff - siz);
                  col := ToRGB($ff, col, col);
                end;

                if siz = 0 then
                begin
                  canvas.Brush.Color := col;
                  canvas.FillRect(
                    (sx shl cTileWidthBits) - 1 + off, (sy shl cTileWidthBits) - 1 + off,
                    (sx shl cTileWidthBits) + 1 + off, (sy shl cTileWidthBits) + 1 + off);
                end
                else
                begin
                  canvas.Pen.Color := col;
                  canvas.Line(
                    (sx shl cTileWidthBits) + off, (sy shl cTileWidthBits) + off,
                    (sx shl cTileWidthBits) + TMI^.Attrs.MotionX + off, (sy shl cTileWidthBits) + TMI^.Attrs.MotionY + off);
                end;
              end;

            end;
          end;
      end;
    end;

    // "FPalettes / Tiles" tab

    if APage = rpTilesPalette then
    begin
      FPaletteBitmap.BeginUpdate;
      try
        for j := 0 to FPaletteBitmap.Height - 1 do
        begin
          pFB := FPaletteBitmap.ScanLine[j];
          for i := 0 to FPaletteBitmap.Width - 1 do
          begin
            if Assigned(FPalettes) and Assigned(FPalettes[j].PaletteRGB) then
              pFB^ := SwapRB(FPalettes[j].PaletteRGB[i])
            else
              pFB^ := clFuchsia;

            Inc(pFB);
          end;
        end;
      finally
        FPaletteBitmap.EndUpdate;
      end;

      FTilesBitmap.Canvas.Brush.Color := clAqua;
      FTilesBitmap.Canvas.Brush.Style := bsSolid;
      FTilesBitmap.Canvas.FillRect(FTilesBitmap.Canvas.ClipRect);

      FTilesBitmap.BeginUpdate;
      try
        pFB := PInteger(FTilesBitmap.RawImage.Data);

        for sy := 0 to FTileMapHeight - 1 do
          for sx := 0 to FTileMapWidth - 1 do
          begin
            tidx := FTileMapWidth * sy + sx + FTileMapSize * FRenderTilePage;

            if InRange(tidx, 0, High(Tiles)) then
            begin
              tilePtr := Tiles[tidx];
              pal := nil;
              if FRenderOutputDithered and (Length(FPalettes) > 0) then
                pal := FPalettes[IfThen(FRenderPaletteIndex < 0, Max(0, tilePtr^.PalIdx), FRenderPaletteIndex)].PaletteRGB;

              hmir := tilePtr^.HMirror_Initial;
              vmir := tilePtr^.VMirror_Initial;

              if not FRenderMirrored then
              begin
                hmir := False;
                vmir := False;
              end;

              DrawTile(TempBuf, pal, tilePtr, 0, 0, hmir, vmir, False);

              BlitBuffer(TempBuf, pFB, sy, sx, FTilesBitmap.Width);
            end;
          end;
      finally
        FTilesBitmap.EndUpdate;
      end;
    end;

    // PSNR indicator

    errCml := 0;
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        TMI := @Frame.TileMap[sy, sx];
        errCml += TMI^.Error;
      end;
    errCml := errCml div FTileMapSize;

    FRenderPsychoVisualQuality := EuclideanToPSNR(errCml);

  finally
    FRenderPrevFrameIndex := Frame.Index;
    TTile.Dispose(TempTile);
  end;
end;

procedure TTilingEncoder.Render;
var
  frmIdx: Integer;
begin
  if (FRenderFrameIndex = FRenderPrevFrameIndex + 1) or (FRenderPage <> rpOutput) then
  begin
    RenderFrame(FRenderFrameIndex, FRenderPage)
  end
  else
  begin
    frmIdx := EnsureRange(FRenderFrameIndex, 0, High(FFrames));
    for frmIdx := FFrames[frmIdx].PKeyFrame.StartFrame to frmIdx do
      RenderFrame(frmIdx, rpOutput);
  end;
end;


procedure TTilingEncoder.SaveSettings(ASettingsFileName: String);
var
  ini: TMemIniFile;
begin
  ini := TMemIniFile.Create(ASettingsFileName, []);
  try

    ini.WriteString('Load', 'InputFileName', InputFileName);
    ini.WriteString('Load', 'OutputFileName', OutputFileName);
    ini.WriteInteger('Load', 'StartFrame', StartFrame);
    ini.WriteInteger('Load', 'FrameCount', FrameCountSetting);
    ini.WriteFloat('Load', 'Scaling', Scaling);

    ini.WriteInteger('MotionPredict', 'MotionPredictRadius', MotionPredictRadius);
    ini.WriteInteger('MotionPredict', 'MotionPredictMaxBufferedFrames', MotionPredictMaxBufferedFrames);

    ini.WriteBool('GlobalTiling', 'GlobalTilingUseTargetPSNR', GlobalTilingUseTargetPSNR);
    ini.WriteFloat('GlobalTiling', 'GlobalTilingTargetPSNR', GlobalTilingTargetPSNR);
    ini.WriteFloat('GlobalTiling', 'GlobalTilingQualityBasedTileCount', GlobalTilingQualityBasedTileCount);
    ini.WriteInteger('GlobalTiling', 'GlobalTilingTileCount', GlobalTilingTileCount);

    ini.WriteInteger('Dither', 'PaletteSize', PaletteSize);
    ini.WriteInteger('Dither', 'PaletteCount', PaletteCount);
    ini.WriteInteger('Dither', 'DitheringMode', Ord(DitheringMode));
    ini.WriteBool('Dither', 'DitheringUseThomasKnoll', DitheringUseThomasKnoll);
    ini.WriteInteger('Dither', 'DitheringYliluoma2MixedColors', DitheringYliluoma2MixedColors);

    ini.WriteInteger('Misc', 'MaxThreadCount', MaxThreadCount);

    ini.WriteFloat('Load', 'ShotTransMaxSecondsPerKF', ShotTransMaxSecondsPerKF);
    ini.WriteFloat('Load', 'ShotTransMinSecondsPerKF', ShotTransMinSecondsPerKF);
    ini.WriteFloat('Load', 'ShotTransCorrelLoThres', ShotTransCorrelLoThres);

  finally
    ini.Free;
  end;
end;

procedure TTilingEncoder.LoadSettings(ASettingsFileName: String);
var
  ini: TMemIniFile;
begin
  ini := TMemIniFile.Create(ASettingsFileName, []);
  try
    LoadDefaultSettings;

    InputFileName := ini.ReadString('Load', 'InputFileName', InputFileName);
    OutputFileName := ini.ReadString('Load', 'OutputFileName', OutputFileName);
    StartFrame := ini.ReadInteger('Load', 'StartFrame', StartFrame);
    FrameCountSetting := ini.ReadInteger('Load', 'FrameCount', FrameCountSetting);
    Scaling := ini.ReadFloat('Load', 'Scaling', Scaling);

    MotionPredictRadius := ini.ReadInteger('MotionPredict', 'MotionPredictRadius', MotionPredictRadius);
    MotionPredictMaxBufferedFrames := ini.ReadInteger('MotionPredict', 'MotionPredictMaxBufferedFrames', MotionPredictMaxBufferedFrames);

    GlobalTilingUseTargetPSNR := ini.ReadBool('GlobalTiling', 'GlobalTilingUseTargetPSNR', GlobalTilingUseTargetPSNR);
    GlobalTilingTargetPSNR := ini.ReadFloat('GlobalTiling', 'GlobalTilingTargetPSNR', GlobalTilingTargetPSNR);
    GlobalTilingQualityBasedTileCount := ini.ReadFloat('GlobalTiling', 'GlobalTilingQualityBasedTileCount', GlobalTilingQualityBasedTileCount);
    GlobalTilingTileCount := ini.ReadInteger('GlobalTiling', 'GlobalTilingTileCount', GlobalTilingTileCount); // after GlobalTilingQualityBasedTileCount because has priority

    PaletteSize := ini.ReadInteger('Dither', 'PaletteSize', PaletteSize);
    PaletteCount := ini.ReadInteger('Dither', 'PaletteCount', PaletteCount);
    DitheringMode := TPsyVisMode(EnsureRange(ini.ReadInteger('Dither', 'DitheringMode', Ord(DitheringMode)), Ord(Low(TPsyVisMode)), Ord(High(TPsyVisMode))));
    DitheringUseThomasKnoll := ini.ReadBool('Dither', 'DitheringUseThomasKnoll', DitheringUseThomasKnoll);
    DitheringYliluoma2MixedColors := ini.ReadInteger('Dither', 'DitheringYliluoma2MixedColors', DitheringYliluoma2MixedColors);

    MaxThreadCount := ini.ReadInteger('Misc', 'MaxThreadCount', MaxThreadCount);

    ShotTransMaxSecondsPerKF := ini.ReadFloat('Load', 'ShotTransMaxSecondsPerKF', ShotTransMaxSecondsPerKF);
    ShotTransMinSecondsPerKF := ini.ReadFloat('Load', 'ShotTransMinSecondsPerKF', ShotTransMinSecondsPerKF);
    ShotTransCorrelLoThres := ini.ReadFloat('Load', 'ShotTransCorrelLoThres', ShotTransCorrelLoThres);

  finally
    ini.Free;
  end;
end;

procedure TTilingEncoder.LoadDefaultSettings;
begin
  InputFileName := '';
  OutputFileName := '';
  StartFrame := 0;
  FrameCountSetting := 0;
  Scaling := 1.0;

{$ifdef DEBUG}
  MaxThreadCount := 1;
{$else}
  SetPriorityClass(GetCurrentProcess(), IDLE_PRIORITY_CLASS);
  MaxThreadCount := NumberOfProcessors;
{$endif}

  PaletteSize := 16;
  PaletteCount := 1024;

  MotionPredictRadius := 32;
  MotionPredictMaxBufferedFrames := 3;

  GlobalTilingUseTargetPSNR := True;
  GlobalTilingTargetPSNR := 24.0;
  GlobalTilingQualityBasedTileCount := 3.0;
  GlobalTilingTileCount := 0; // after GlobalTilingQualityBasedTileCount because has priority

  DitheringMode := pvsWeightedSpeDCT;
  DitheringUseThomasKnoll := True;
  DitheringYliluoma2MixedColors := 4;

  ShotTransMaxSecondsPerKF := 15.0;  // maximum seconds between keyframes
  ShotTransMinSecondsPerKF := 1.0;  // minimum seconds between keyframes
  ShotTransCorrelLoThres := 0.8;   // interframe pearson correlation low limit
end;

procedure TTilingEncoder.Test;
var
  i, j, rng: Integer;
  rr, gg, bb: Byte;
  l, a, b, y, u, v: TFloat;
  DCT: array [0..cTileDCTSize-1] of Double;
  T, T2: PTile;
begin
  InitLuts;

  for i := 0 to 10000 do
  begin
    rng := RandomRange(0, (1 shl 24) - 1);
    FromRGB(rng, rr, gg, bb);

    RGBToLAB(rr, gg, bb, l, a, b);
    assert(rng = LABToRGB(l, a ,b), 'RGBToLAB/LABToRGB mismatch');

    RGBToYUV(rr, gg, bb, y, u, v, 1.0);
    assert(rng = YUVToRGB(y, u, v, 1.0), 'RGBToYUV/YUVToRGB mismatch');

    RGBToYUV(rr, gg, bb, y, u, v, 2.0);
    assert(rng = YUVToRGB(y, u, v, 2.0), 'RGBToYUV/YUVToRGB mismatch');

    RGBToYUV(rr, gg, bb, y, u, v, 1.0);
    RGBToYUV(rr, gg, bb, l, a, b, 2.0);
    assert((l <> y) or (a <> u) or (b <> v), 'RGBToYUV scale failure');

    if (rr <> 0) and (gg <> 0) and (bb <> 0) then
    begin
      RGBToYUV(rr, gg, bb, y, u, v, 1.0);
      assert(YUVToRGB(y, u, v, 1.0) <> YUVToRGB(y, u, v, 2.0), 'YUVToRGB scale failure');
    end;

    assert(SameValue(i, PSNRToEuclidean(EuclideanToPSNR(i)), PSNRToEuclidean(cBestPSNR - cPsyVEpsilon)), 'EuclideanToPSNR/PSNRToEuclidean mismatch');
  end;

  T := TTile.New(True, False);
  T2 := TTile.New(True, False);

  for i := 0 to cTileWidth - 1 do
    for j := 0 to cTileWidth - 1 do
      T^.RGBPixels[i, j] := ToRGB(i*8, j * 32, i * j);

  ComputeTilePsyVisFeatures(T^, pvsDCT, False, False, False, False, cColorCpns, nil, @DCT[0]);
  ComputeInvTilePsyVisFeatures(@DCT[0], pvsDCT, False, cColorCpns, T2^);

  //for i := 0 to 7 do
  //  for j := 0 to 7 do
  //    write(IntToHex(T^.RGBPixels[i, j], 6), '  ');
  //WriteLn();
  //for i := 0 to 7 do
  //  for j := 0 to 7 do
  //    write(IntToHex(T2^.RGBPixels[i, j], 6), '  ');
  //WriteLn();

  Assert(CompareMem(T^.GetRGBPixelsPtr, T2^.GetRGBPixelsPtr, SizeOf(TRGBPixels)), 'DCT/InvDCT mismatch');

  ComputeTilePsyVisFeatures(T^, pvsWeightedDCT, False, False, False, False, cColorCpns, nil, @DCT[0]);
  ComputeInvTilePsyVisFeatures(@DCT[0], pvsWeightedDCT, False, cColorCpns, T2^);

  Assert(CompareMem(T^.GetRGBPixelsPtr, T2^.GetRGBPixelsPtr, SizeOf(TRGBPixels)), 'QWeighted DCT/InvDCT mismatch');

  ComputeTilePsyVisFeatures(T^, pvsWavelets, False, False, False, False, cColorCpns, nil, @DCT[0]);
  ComputeInvTilePsyVisFeatures(@DCT[0], pvsWavelets, False, cColorCpns, T2^);

  Assert(CompareMem(T^.GetRGBPixelsPtr, T2^.GetRGBPixelsPtr, SizeOf(TRGBPixels)), 'WL/InvWL mismatch');

  TTile.Dispose(T);
  TTile.Dispose(T2);
end;

procedure TTilingEncoder.ProgressRedraw(ASubStepIdx: Integer; AReason: String; AProgressStep: TEncoderStep;
 AThread: TThread);

  function GetStepLen: Integer;
  begin
    Result := cEncoderStepLen[FProgressStep];

    if Result < 0 then
      Result *= -Length(FFrames);
  end;

const
  cProgressMul = 100;
var
  curTime: Int64;
  ProgressPosition, ProgressStepPosition, ProgressMax: Integer;
  ProgressHourGlass: Boolean;
begin
  if not Assigned(AThread) then
    scalable_allocation_command(TBBMALLOC_CLEAN_ALL_BUFFERS, nil); // force the mem allocator to release unused memory

  curTime := GetTickCount64;

  if (ASubStepIdx < 0) and (AProgressStep = esAll) then // reset
  begin
    FProgressStep := esAll;
    FProgressPrevTime := curTime;
    FProgressAllStartTime := curTime;
    FProgressProcessStartTime := curTime;
  end
  else if AProgressStep <> esAll then // new step?
  begin
    if ASubStepIdx = 0 then
    begin
      FProgressAllStartTime += curTime - FProgressPrevTime;
      FProgressProcessStartTime := curTime;
    end;
    FProgressStep := AProgressStep;
  end;

  ProgressMax := (Ord(High(TEncoderStep)) + 1) * cProgressMul;
  ProgressPosition := Ord(FProgressStep) * cProgressMul;

  ProgressStepPosition := 0;
  if ASubStepIdx >= 0 then
    ProgressStepPosition := iDivDef(ASubStepIdx * cProgressMul, GetStepLen, ProgressStepPosition);

  ProgressHourGlass := (AProgressStep <> esAll) and (ASubStepIdx < GetStepLen);

  if ASubStepIdx >= 0 then
  begin
    WriteLn('Step: ', Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(FProgressStep)), 3), ' / ', ProgressStepPosition,
      #9'Time: ', FormatFloat('0.000', (curTime - FProgressProcessStartTime) / 1000),
      #9'All: ', FormatFloat('0.000', (curTime - FProgressAllStartTime) / 1000),
      IfThen(AReason <> '', ', Reason: '), AReason);
  end;
  FProgressPrevTime := curTime;

  // reset time for "named" substeps (ie. not by frame)
  if cEncoderStepLen[FProgressStep] >= 0 then
    FProgressProcessStartTime := curTime;

  EnterCriticalSection(FCS);
  try
    FProgressSyncPos := ProgressPosition + ProgressStepPosition;
    FProgressSyncMax := ProgressMax;
    FProgressSyncHG := ProgressHourGlass;

    if Assigned(AThread) then
      TThread.Queue(AThread, @SyncProgress)
    else
      SyncProgress;
  finally
    LeaveCriticalSection(FCS);
  end;
end;

procedure TTilingEncoder.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, FProgressSyncPos, FProgressSyncMax, FProgressSyncHG);
end;

type
  TGRPSNRData = record
    OnTileCount: Boolean;
    MeanPSNR: Double;
    UnpredictedTileCount: Integer;
  end;

  PGRPSNRData = ^TGRPSNRData;

function TTilingEncoder.GRPSNR(x: Double; Data: Pointer): Double;
var
  GRData: PGRPSNRData absolute Data;
  frmIdx, sy, sx: Integer;
  errThres: Cardinal;
  meanErr: UInt64;
  Frame: TFrame;
  TMI: PTileMapItem;
begin
  errThres := PSNRToEuclidean(x);

  meanErr := 0;
  GRData^.MeanPSNR := 0.0;
  GRData^.UnpredictedTileCount := 0;

  for frmIdx := 0 to High(FFrames) do
  begin
    Frame := FFrames[frmIdx];

    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        TMI := @Frame.TileMap[sy, sx];

        // trim high (unfit) Errors
        TMI^.IsPredicted := TMI^.Error < errThres;

        meanErr += IfThen(TMI^.IsPredicted, TMI^.Error);
        Inc(GRData^.UnpredictedTileCount, Ord(not TMI^.IsPredicted));
      end;
  end;

  meanErr := iDivDef(meanErr, Length(FFrames) * FTileMapSize - GRData^.UnpredictedTileCount, 0);
  GRData^.MeanPSNR := EuclideanToPSNR(meanErr);

  WriteLn('Threshold: ', x:9:3, ', Mean PSNR: ', GRData^.MeanPSNR:9:3, ', TileCount: ', GRData^.UnpredictedTileCount:8);

  if GRData^.OnTileCount then
    Result := GRData^.UnpredictedTileCount
  else
    Result := GRData^.MeanPSNR;
end;

function TTilingEncoder.SolveTileCount(ATileCount: Integer): Integer;
var
  GRData: TGRPSNRData;
begin
  GRData.OnTileCount := True;
  GRData.MeanPSNR := 0;
  GRData.UnpredictedTileCount := 0;
  GoldenRatioSearch(@GRPSNR, 0.0, cBestPSNR, ATileCount, cPsyVEpsilon, 0.5, @GRData);
  Result := GRData.UnpredictedTileCount;
end;

function TTilingEncoder.SolveAvgPSNR(AAvgPSNR: Double): Integer;
var
  GRData: TGRPSNRData;
begin
  GRData.OnTileCount := False;
  GRData.MeanPSNR := 0;
  GRData.UnpredictedTileCount := 0;
  GoldenRatioSearch(@GRPSNR, 0.0, cBestPSNR, AAvgPSNR, cPsyVEpsilon, 0.01, @GRData);
  Result := GRData.UnpredictedTileCount;
end;

procedure TTilingEncoder.TransferTiles;
var
  doneFrameCount: Integer;
  newTIdx: Integer;

  procedure DoTransfer(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    tIdx, sx, sy, irBaseTIdx: Integer;
    Frame: TFrame;
    Tile: PTile;
    TMI: PTileMapItem;
  begin
    if not InRange(AIndex, 0, High(FFrames)) then
      Exit;

    Frame := FFrames[AIndex];

    if Assigned(Frame.IntraReducedTiles) then
    begin
      irBaseTIdx := InterLockedExchangeAdd(newTIdx, Length(Frame.IntraReducedTiles));

      for tIdx := 0 to High(Frame.IntraReducedTiles) do
      begin
        Tile := Tiles[tIdx + irBaseTIdx];
        Tile^.CopyFrom(Frame.IntraReducedTiles[tIdx]^);
      end;

      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMI := @Frame.TileMap[sy, sx];

          TMI^.TileIdx := Frame.IntraReducedTileIndexes[sy, sx] + irBaseTIdx;
        end;
    end
    else
    begin
      Frame.AcquireFrameTiles;
      try
        for sy := 0 to FTileMapHeight - 1 do
          for sx := 0 to FTileMapWidth - 1 do
          begin
            TMI := @Frame.TileMap[sy, sx];

            if not TMI^.IsPredicted then
            begin
              tIdx := InterLockedExchangeAdd(newTIdx, 1);

              Tile := Tiles[tIdx];
              Tile^.CopyFrom(Frame.FrameTiles[sy * FTileMapWidth + sx]^);

              TMI^.TileIdx := tIdx;
            end
            else
            begin
              TMI^.TileIdx := -1;
            end;
          end;

        Write(InterLockedIncrement(doneFrameCount):8, ' / ', Length(FFrames):8, #13);

      finally
        Frame.ReleaseFrameTiles;
      end;
    end;
  end;

var
  frmIdx, tileCount: Integer;
  Frame: TFrame;
begin
  tileCount := 0;
  for frmIdx := 0 to High(FFrames) do
  begin
    Frame := FFrames[frmIdx];

    if Length(Frame.IntraReducedTiles) <> 0 then
      tileCount += Length(Frame.IntraReducedTiles)
    else
      tileCount += Frame.GetUnpredictedTileCount;
  end;

  TTile.Array1DDispose(FTiles);
  FTiles := TTile.Array1DNew(tileCount, True, True);

  doneFrameCount := 0;
  newTIdx := 0;

  ProcThreadPool.DoParallelLocalProc(@DoTransfer, 0, High(FFrames));

  Assert(newTIdx = tileCount);
end;

procedure TTilingEncoder.DoPalettization;
var
  YakmoDataset: TDoubleDynArray2;
  YakmoWeights: TCardinalDynArray;

  procedure DoDCT(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    Tile: PTile;
  begin
    if not InRange(AIndex, 0, High(FTiles)) then
      Exit;

    Tile := FTiles[AIndex];
    Assert(Tile^.Active);

    ComputeTilePsyVisFeatures(Tile^, DitheringMode, False, True, False, False, cColorCpns, nil, @YakmoDataset[AIndex, 0]);
    YakmoWeights[AIndex] := Tile^.UseCount;
  end;

var
  DSLen, tIdx, di, palIdx: Integer;

  Tile: PTile;

  Yakmo: PYakmo;

  YakmoClusters: TIntegerDynArray;
  PalIdxLUT: TIntegerDynArray;
begin
  DSLen := Length(FTiles);

  // cluster by palette index

  SetLength(YakmoWeights, DSLen);
  SetLength(YakmoClusters, DSLen);

  if DSLen > FPaletteCount then
  begin
    SetLength(YakmoDataset, DSLen, cTileDCTSize);

    ProcThreadPool.DoParallelLocalProc(@DoDCT, 0, DSLen - 1);

    if FPaletteCount > 1 then
    begin
      Yakmo := yakmo_create(FPaletteCount, 1, cYakmoMaxIterations, 1, 0, 0, 1);
      try
        yakmo_set_num_threads(MaxThreadCount);

        yakmo_load_train_data_weighted(Yakmo, Length(YakmoDataset), cTileDCTSize, PPDouble(@YakmoDataset[0]), @YakmoWeights[0]);
        SetLength(YakmoDataset, 0); // free up some memmory
        yakmo_train_on_data(Yakmo, @YakmoClusters[0]);
      finally
        yakmo_destroy(Yakmo);
      end;
    end;
  end
  else
  begin
    for di := 0 to High(YakmoClusters) do
    begin
      YakmoWeights[di] := FTiles[di]^.UseCount;
      YakmoClusters[di] := di;
    end;
  end;

  // sort entire palettes by use count

  SetLength(FPalettes, FPaletteCount);
  SetLength(PalIdxLUT, FPaletteCount);

  for palIdx := 0 to FPaletteCount - 1 do
    FPalettes[palIdx].PalIdx_Initial := palIdx;

  for di := 0 to High(YakmoClusters) do
    Inc(FPalettes[YakmoClusters[di]].UseCount, YakmoWeights[di]);

  QuickSort(FPalettes[0], 0, FPaletteCount - 1, SizeOf(FPalettes[0]), @ComparePaletteUseCount, Self);
  for palIdx := 0 to FPaletteCount - 1 do
    PalIdxLUT[FPalettes[palIdx].PalIdx_Initial] := palIdx;

  // assign final palette indexes

  for tIdx := 0 to High(FTiles) do
  begin
    Tile := FTiles[tIdx];
    Assert(Tile^.Active);

    Tile^.PalIdx := PalIdxLUT[YakmoClusters[tIdx]];
  end;
end;

type
  TMinimizeOPData = record
    Encoder: TTilingEncoder;
    CurPalIdx: Integer;
    MeanR, MeanG, MeanB: Int64;
    PalR, PalG, PalB: array[0 .. Sqr(cTileWidth) - 1] of Int64;
    InnerPerm: TIndexWeightList;
    NewPal: TIntegerDynArray2;
  end;


function ComparePerms(const Item1,Item2:PIndexWeight):Integer;
begin
  Result := CompareValue(Item1^.Weight * 1000.0 + Item1^.Index, Item2^.Weight * 1000.0 + Item2^.Index);
end;

function TTilingEncoder.MinimizeOP(const x: TDoubleDynArray; data: Pointer): Double;
var
  PData: ^TMinimizeOPData absolute data;
  StdDevR, StdDevG, StdDevB: UInt64;
  colIdx, col: Integer;
  r, g, b: Byte;
begin
  // from rank to palette

  PData^.InnerPerm[0]^.Index := 0;
  PData^.InnerPerm[0]^.Weight := 0.0;
  for colIdx := 1 to PData^.Encoder.FPaletteSize - 1 do
  begin
    PData^.InnerPerm[colIdx]^.Index := colIdx;
    PData^.InnerPerm[colIdx]^.Weight := x[colIdx - 1];
  end;

  PData^.InnerPerm.Sort(@ComparePerms);

  // try to maximize accumulated palette standard deviation
  // rationale: the less samey it is, the better the colors pair with each other across palette

  StdDevR := 0;
  StdDevG := 0;
  StdDevB := 0;
  for colIdx := 0 to PData^.Encoder.FPaletteSize - 1 do
  begin
    col := PData^.Encoder.FPalettes[PData^.CurPalIdx].PaletteRGB[PData^.InnerPerm[colIdx]^.Index];
    FromRGB(col, r, g, b);

    PData^.NewPal[PData^.CurPalIdx, colIdx] := col;

    StdDevR += Sqr(PData^.PalR[colIdx] + r - PData^.MeanR);
    StdDevG += Sqr(PData^.PalG[colIdx] + g - PData^.MeanG);
    StdDevB += Sqr(PData^.PalB[colIdx] + b - PData^.MeanB);
  end;

  Result := (cRedMul * Sqrt(StdDevR / PData^.Encoder.FPaletteSize) +
             cGreenMul * Sqrt(StdDevG / PData^.Encoder.FPaletteSize) +
             cBlueMul * Sqrt(StdDevB / PData^.Encoder.FPaletteSize)) / cLumaDiv;

  Result := -Result;
end;

procedure TTilingEncoder.OptimizePalettes;
var
  f: TDoubleDynArray;
  MeanR, MeanG, MeanB: UInt64;
  NewPal: TIntegerDynArray2;

  procedure DoPal(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    Data: TMinimizeOPData;
    x: TDoubleDynArray;
    palIdx, colIdx: Integer;
    iw: PIndexWeight;
    r, g, b: Byte;
  begin
    if not InRange(AIndex, 0, FPaletteCount - 1) then
      Exit;

    SetLength(x, FPaletteSize - 1);
    for colIdx := 1 to FPaletteSize - 1 do
      x[colIdx - 1] := colIdx;

    Data.Encoder := Self;
    Data.CurPalIdx := AIndex;
    Data.MeanR := MeanR;
    Data.MeanG := MeanG;
    Data.MeanB := MeanB;
    Data.NewPal := NewPal;

    Data.InnerPerm := TIndexWeightList.Create;
    for colIdx := 0 to FPaletteSize - 1 do
    begin
      New(iw);
      Data.InnerPerm.Add(iw);
    end;
    try

    // accumulate the whole palette except the one that will be permutated

    FillQWord(Data.PalR[0], FPaletteSize, 0);
    FillQWord(Data.PalG[0], FPaletteSize, 0);
    FillQWord(Data.PalB[0], FPaletteSize, 0);

    for palIdx := 0 to FPaletteCount - 1 do
      if palIdx <> AIndex then
      begin
        for colIdx := 0 to FPaletteSize - 1 do
        begin
          FromRGB(FPalettes[palIdx].PaletteRGB[colIdx], r, g, b);

          Data.PalR[colIdx] += r;
          Data.PalG[colIdx] += g;
          Data.PalB[colIdx] += b;
        end;
      end;

    // use Powell's method to try permutations in the current palette

    PowellMinimize(@MinimizeOP, x, FPaletteSize * cInvPhi, 0.0, 0.0, MaxInt, @Data);

    f[AIndex] := -MinimizeOP(x, @Data);

    finally
      for colIdx := 0 to FPaletteSize - 1 do
        Dispose(Data.InnerPerm[colIdx]);
      Data.InnerPerm.Free;
    end;
  end;

var
  palIdx, colIdx, iteration: Integer;
  fSum, prevFSum: Double;
  r, g, b: Byte;
begin
  SetLength(f, FPaletteCount);
  SetLength(NewPal, FPaletteCount, FPaletteSize);

  // mean of all palette colors

  MeanR := 0;
  MeanG := 0;
  MeanB := 0;

  for palIdx := 0 to FPaletteCount - 1 do
    for colIdx := 0 to FPaletteSize - 1 do
    begin
      FromRGB(FPalettes[palIdx].PaletteRGB[colIdx], r, g, b);

      MeanR += r;
      MeanG += g;
      MeanB += b;
    end;

  MeanR := MeanR div FPaletteSize;
  MeanG := MeanG div FPaletteSize;
  MeanB := MeanB div FPaletteSize;

  iteration := 0;
  prevFSum := 0;
  fSum := 0;

  // stepwise algorithm (each palette being optimized alone, needs iterations to attain global optimum)

  repeat
    prevFSum := max(fSum, prevFSum);
    Inc(iteration);

    ProcThreadPool.DoParallelLocalProc(@DoPal, 0, FPaletteCount - 1);

    fSum := 0;
    for palIdx := 0 to FPaletteCount - 1 do
    begin
      fSum += f[palIdx];

      for colIdx := 0 to FPaletteSize - 1 do
        FPalettes[palIdx].PaletteRGB[colIdx] := NewPal[palIdx, colIdx];
    end;
    fSum /= FPaletteCount;

    //WriteLn(iteration:4,fSum:16:3);

  until fSum <= prevFSum;

  WriteLn('OptimizePalettes: ', iteration, ' iterations');
end;

procedure TTilingEncoder.QuantizeUsingYakmo(APalIdx, AColorCount, APosterize: Integer);
const
  cFeatureCount = 3;
var
  i, j, di, ty, tx, tIdx, DSLen: Integer;
  rr, gg, bb: Byte;
  Tile: PTile;
  Dataset, Centroids: TDoubleDynArray2;
  Clusters: TIntegerDynArray;
  Yakmo: PYakmo;
  CMPal: TCountIndexList;
  CMItem: PCountIndex;
begin
  CMPal := FPalettes[APalIdx].CMPal;

  for i := 0 to CMPal.Count - 1 do
    Dispose(CMPal[i]);
  CMPal.Clear;

  DSLen := 0;
  for tIdx := 0 to High(FTiles) do
    Inc(DSLen, sqr(cTileWidth) * Ord(FTiles[tIdx]^.PalIdx = APalIdx));

  if DSLen <= 0 then
    Exit;

  SetLength(Dataset, DSLen, cFeatureCount);
  SetLength(Clusters, DSLen);
  SetLength(Centroids, AColorCount, cFeatureCount);

  AColorCount := Min(AColorCount, DSLen);

  // build a dataset of RGB pixels

  di := 0;
  for tIdx := 0 to High(FTiles) do
  begin
    Tile := FTiles[tIdx];

    if Tile^.Active and (Tile^.PalIdx = APalIdx) then
      for ty := 0 to cTileWidth - 1 do
        for tx := 0 to cTileWidth - 1 do
        begin
          FromRGB(Tile^.RGBPixels[ty, tx], rr, gg, bb);
          Dataset[di, 0] := GammaCorrect(0, rr);
          Dataset[di, 1] := GammaCorrect(0, gg);
          Dataset[di, 2] := GammaCorrect(0, bb);
          Inc(di);
        end;
  end;
  Assert(di = Length(Dataset));

  // use KMeans to quantize to AColorCount elements

  if AColorCount > 1 then
  begin
    Yakmo := yakmo_create(AColorCount, 1, cYakmoMaxIterations, 1, 0, 0, 0);
    try
      yakmo_load_train_data(Yakmo, DSLen, cFeatureCount, PPDouble(@Dataset[0]));
      SetLength(Dataset, 0); // free up some memory
      yakmo_train_on_data(Yakmo, @Clusters[0]);
      yakmo_get_centroids(Yakmo, PPDouble(@Centroids[0]));
    finally
      yakmo_destroy(Yakmo);
    end;
  end
  else
  begin
    for j := 0 to DSLen - 1 do
      for i := 0 to cFeatureCount - 1 do
        Centroids[0, i] += Dataset[j, i];
    for i := 0 to cFeatureCount - 1 do
      Centroids[0, i] /= di;
  end;

  // retrieve palette data

  for i := 0 to AColorCount - 1 do
  begin
    New(CMItem);

    CMItem^.R := 0;
    CMItem^.G := 0;
    CMItem^.B := 0;

    if not IsNan(Centroids[i, 0]) and not IsNan(Centroids[i, 1]) and not IsNan(Centroids[i, 2]) then
    begin
      CMItem^.R := Posterize(GammaUncorrect(0, Centroids[i, 0]), APosterize);
      CMItem^.G := Posterize(GammaUncorrect(0, Centroids[i, 1]), APosterize);
      CMItem^.B := Posterize(GammaUncorrect(0, Centroids[i, 2]), APosterize);
    end;

    CMItem^.Count := 0;
    RGBToHSV(CMItem^.R, CMItem^.G, CMItem^.B, CMItem^.Hue, CMItem^.Sat, CMItem^.Val);
    CMPal.Add(CMItem);
  end;
end;

procedure TTilingEncoder.DoQuantization(APalIdx: Integer);
var
  CMPal: TCountIndexList;
  i: Integer;
begin
  CMPal := TCountIndexList.Create;
  FPalettes[APalIdx].CMPal := CMPal;
  try
    // do quantize

    QuantizeUsingYakmo(APalIdx, FPaletteSize, (1 shl cBitsPerComp) - 1);

    // split most used colors into tile palettes

    CMPal.Sort(@CompareCountIndexVSH);

    SetLength(FPalettes[APalIdx].PaletteRGB, FPaletteSize);
    for i := 0 to CMPal.Count - 1 do
    begin
      FPalettes[APalIdx].PaletteRGB[i] := ToRGB(CMPal[i]^.R, CMPal[i]^.G, CMPal[i]^.B);
      Dispose(CMPal[i]);
    end;

    for i := CMPal.Count to FPaletteSize - 1 do
      FPalettes[APalIdx].PaletteRGB[i] := cDitheringNullColor;

  finally
    CMPal.Free;
    FPalettes[APalIdx].CMPal := nil;
  end;
end;

procedure TTilingEncoder.PrepareReconstruct;
var
  DS: PTilingDataset;

  procedure DoPsyV(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    T: PTile;
    CpnPixels: TCpnPixels;
  begin
    if not InRange(AIndex, 0, High(FTiles)) then
      Exit;

    T := Tiles[AIndex];
    Assert(T^.Active);

    ConvertToCpnPixels(T^, True, False, False, False, FPalettes[T^.PalIdx].PaletteRGB, CpnPixels);
    ComputeCpnPixelsPsyVisFeatures(CpnPixels, pvsWeightedDCT, cColorCpns, @DS^.Dataset[AIndex, 0]);
  end;

var
  kfIdx: Integer;
begin
  // Compute psycho visual model for all tiles in all palettes

  DS := New(PTilingDataset);
  FillChar(DS^, SizeOf(TTilingDataset), 0);

  DS^.KNNSize := Length(FTiles);
  SetLength(DS^.Dataset, DS^.KNNSize, cTileDCTSize);

  ProcThreadPool.DoParallelLocalProc(@DoPsyV, 0, High(FTiles));

  // Build KNN

  DS^.ANN := ann_kdtree_short_create(PPSmallint(@DS^.Dataset[0]), DS^.KNNSize, cTileDCTSize, 32, ANN_KD_STD);

  // Dataset is ready

  FTilingDataset := DS;

  // init for LogPSNR

  for kfIdx := 0 to High(FKeyFrames) do
  begin
    FKeyFrames[kfIdx].ReconstructErrCml := 0;
    FKeyFrames[kfIdx].ReconstructFramesLeft := FKeyFrames[kfIdx].FrameCount;
  end;
end;

procedure TTilingEncoder.FinishReconstruct;
begin
  if Length(FTilingDataset^.Dataset) > 0 then
    ann_kdtree_short_destroy(FTilingDataset^.ANN);
  FTilingDataset^.ANN := nil;
  SetLength(FTilingDataset^.Dataset, 0);
  Dispose(FTilingDataset);

  FTilingDataset := nil;
end;

procedure TTilingEncoder.ReindexTiles(OnRGBPixels: Boolean);
var
  IdxMap: TInt64DynArray;
  Frame: TFrame;

  procedure Remap(var ATidx: Integer);
  var
    tidx: Integer;
  begin
    tidx := ATidx;
    if tidx >= 0 then
    begin
      tidx := IdxMap[tidx];
      ATidx := tidx;
    end;
  end;

var
  frmIdx, sx, sy: Integer;
  pos, cnt, tidx: Int64;
  LocTiles: PTileDynArray;
  TMI: PTileMapItem;
begin
  cnt := 0;
  for tidx := 0 to High(Tiles) do
  begin
    Tiles[tidx]^.TmpIndex := tidx;
    if (Tiles[tidx]^.Active) and (Tiles[tidx]^.UseCount > 0) then
      Inc(cnt);
  end;

  if cnt <= 0 then
    Exit;

  // pack the global Tiles, removing inactive ones

  LocTiles := TTile.Array1DNew(cnt, True, True);
  pos := 0;
  for tidx := 0 to High(Tiles) do
    if (Tiles[tidx]^.Active) and (Tiles[tidx]^.UseCount > 0) then
    begin
      LocTiles[pos]^.CopyFrom(Tiles[tidx]^);
      Inc(pos);
    end;

  SetLength(IdxMap, Length(Tiles));
  FillQWord(IdxMap[0], Length(Tiles), QWord(-1));

  TTile.Array1DDispose(FTiles);
  FTiles := LocTiles;
  LocTiles := nil;

  // sort tiles

  QuickSort(Tiles[0], 0, High(Tiles), SizeOf(PTile), @CompareTileUseCountRev, Pointer(Ord(OnRGBPixels)));

  for tidx := 0 to High(Tiles) do
    IdxMap[Tiles[tidx]^.TmpIndex] := tidx;

  // point tilemap items on new tiles indexes

  for frmIdx := 0 to High(FFrames) do
  begin
    Frame := FFrames[frmIdx];
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        TMI := @Frame.TileMap[sy, sx];

        Remap(TMI^.TileIdx);
      end;
  end;

  // cleanup

  for tIdx := 0 to High(FTiles) do
    FTiles[tIdx]^.TmpIndex := -1;

  WriteLn('ReindexTiles: ', Length(Tiles):12, ' / ', Length(FFrames) * FTileMapSize:12,  ' final tiles, (', Length(Tiles) * 100.0 / (Length(FFrames) * FTileMapSize):4:3, '%)');
end;

function CompareTilePalPixels(Item1, Item2:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PTile(Item1);
  t2 := PTile(Item2);
  Result := t1^.ComparePalPixelsTo(t2^);
end;

function CompareTileRGBPixels(Item1, Item2:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PTile(Item1);
  t2 := PTile(Item2);
  Result := t1^.CompareRGBPixelsTo(t2^);
end;

procedure TTilingEncoder.MakeTilesUnique(OnRGBPixels: Boolean);
var
  sortIdx, pos, firstSameIdx: Int64;
  sortList: TFPList;
  sameIdx: array of Int64;

  procedure DoOneMerge;
  var
    j: Int64;
  begin
    if sortIdx - firstSameIdx >= 2 then
    begin
      for j := firstSameIdx to sortIdx - 1 do
        sameIdx[j - firstSameIdx] := PTile(sortList[j])^.TmpIndex;
      MergeTiles(sameIdx, sortIdx - firstSameIdx, sameIdx[0], nil, nil);
    end;
    firstSameIdx := sortIdx;
  end;

var
  tIdx: Integer;
  PixelLSC: TListSortCompare;
begin
  PixelLSC := @CompareTilePalPixels;
  if OnRGBPixels then
    PixelLSC := @CompareTileRGBPixels;

  InitMergeTiles;
  sortList := TFPList.Create;
  try

    // sort global tiles by palette indexes (L to R, T to B)

    SetLength(sameIdx, Length(FTiles));

    sortList.Count := Length(FTiles);
    pos := 0;
    for tIdx := 0 to High(FTiles) do
      if FTiles[tIdx]^.Active then
      begin
        sortList[pos] := FTiles[tIdx];
        PTile(sortList[pos])^.TmpIndex := tIdx;
        Inc(pos);
      end;
    sortList.Count := pos;

    sortList.Sort(PixelLSC);

    // merge exactly similar tiles (so, consecutive after prev code)

    firstSameIdx := 0;
    for sortIdx := 1 to sortList.Count - 1 do
      if PixelLSC(sortList[sortIdx - 1], sortList[sortIdx]) <> 0 then
        DoOneMerge;

    sortIdx := sortList.Count;
    DoOneMerge;

    // cleanup

    for tIdx := 0 to High(FTiles) do
      FTiles[tIdx]^.TmpIndex := -1;

  finally
    sortList.Free;
    FinishMergeTiles;
  end;
end;

procedure TTilingEncoder.MergeTiles(const TileIndexes: array of Int64; TileCount: Integer; BestIdx: Int64;
  NewTile: PPalPixels; NewTileRGB: PRGBPixels);
var
  i: Integer;
  tidx: Int64;
begin
  if TileCount <= 0 then
    Exit;

  if Assigned(NewTile) then
    FTiles[BestIdx]^.CopyPalPixels(NewTile^);

  if Assigned(NewTileRGB) then
    FTiles[BestIdx]^.CopyRGBPixels(NewTileRGB^);

  for i := 0 to TileCount - 1 do
  begin
    tidx := TileIndexes[i];

    if tidx = BestIdx then
      Continue;

    Inc(FTiles[BestIdx]^.UseCount, FTiles[tidx]^.UseCount);

    FTiles[tidx]^.Active := False;
    FTiles[tidx]^.UseCount := 0;
    FTiles[tidx]^.MergeIndex := BestIdx;

    FTiles[tidx]^.ClearPixels;
  end;
end;

procedure TTilingEncoder.InitMergeTiles;
var
  tidx: Int64;
begin
  for tidx := 0 to High(FTiles) do
    FTiles[tidx]^.MergeIndex := -1;
end;

procedure TTilingEncoder.FinishMergeTiles;
var
  sx, sy, frmIdx: Integer;
  tidx: Int64;
begin
  for frmIdx := 0 to High(FFrames) do
    for sy := 0 to (FTileMapHeight - 1) do
      for sx := 0 to (FTileMapWidth - 1) do
      begin
        tidx := FFrames[frmIdx].TileMap[sy, sx].TileIdx;
        if tidx >= 0 then
        begin
          tidx := FTiles[tidx]^.MergeIndex;
          if tidx >= 0 then
            FFrames[frmIdx].TileMap[sy, sx].TileIdx := tidx;
        end;
      end;
end;

class function TTilingEncoder.GetTileZoneSum(const ATile: TTile; AOnPal: Boolean; x, y, w, h: Integer): Integer;
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

class procedure TTilingEncoder.GetTileHVMirrorHeuristics(const ATile: TTile; AOnPal: Boolean; out AHMirror, AVMirror: Boolean);
var
  q00, q01, q10, q11: Integer;
begin
  // enforce an heuristical 'spin' on tiles mirrors (brighter top-left corner)

  q00 := GetTileZoneSum(ATile, AOnPal, 0, 0, cTileWidth div 2, cTileWidth div 2);
  q01 := GetTileZoneSum(ATile, AOnPal, cTileWidth div 2, 0, cTileWidth div 2, cTileWidth div 2);
  q10 := GetTileZoneSum(ATile, AOnPal, 0, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);
  q11 := GetTileZoneSum(ATile, AOnPal, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);

  AHMirror := q00 + q10 < q01 + q11;
  AVMirror := q00 + q01 < q10 + q11;
end;

procedure TTilingEncoder.LoadStream(AStream: TStream);
var
  KFStream: TMemoryStream;
  frmIdx, frmCount: Integer;
  rawTileIdxToTileIdx: TIntegerDynArray;

  function ReadDWord: Cardinal;
  begin
    Result := KFStream.ReadDWord;
  end;

  function ReadWord: Word;
  begin
    Result := KFStream.ReadWord;
  end;

  function ReadByte: Byte;
  begin
    Result := KFStream.ReadByte;
  end;

  procedure ReadCmd(out Cmd: TGTMCommand; out Data: Word);
  var
    d: Word;
  begin
    d := ReadWord;
    Cmd := TGTMCommand(d and ((1 shl CGTMCommandCodeBits) - 1));
    Data := d shr CGTMCommandCodeBits;
  end;

  procedure ReadSettings;
  var
    settings: AnsiString;
  begin
    settings := KFStream.ReadAnsiString;
  end;

  procedure ReadTiles(PaletteSize: Integer);
  var
    iRawTile, rawStartIdx, rawEndIdx, baseTileIdx, tileIdx, tileCnt: Integer;
  begin
    rawStartIdx := ReadDWord; // start tile
    rawEndIdx := ReadDWord; // end tile

    baseTileIdx := Length(FTiles);
    tileCnt := rawEndIdx - rawStartIdx + 1;

    if baseTileIdx > 0 then
      TTile.Array1DRealloc(FTiles, Length(FTiles) + tileCnt)
    else
      FTiles := TTile.Array1DNew(tileCnt, True, True);

    for iRawTile := rawStartIdx to rawEndIdx do
    begin
      tileIdx := baseTileIdx + iRawTile - rawStartIdx;

      KFStream.Read(FTiles[tileIdx]^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
      FTiles[tileIdx]^.Active := True;
      rawTileIdxToTileIdx[iRawTile] := tileIdx;
    end;

    FPaletteSize := PaletteSize;
  end;

  procedure ReadDimensions;
  var
    w, h, frmLen, tileCount: Integer;
  begin
    w := ReadWord; // frame tilemap width
    h := ReadWord; // frame tilemap height
    ReframeUI(w, h);

    frmLen := ReadDWord; // frame length in nanoseconds
    FFramesPerSecond := 1000*1000*1000 / frmLen;

    tileCount := ReadDWord; // tile count
    SetLength(rawTileIdxToTileIdx, tileCount);
  end;

  procedure ReadPalette;
  var
    i, palIdx: Integer;
  begin
    palIdx := ReadWord;

    if Length(FPalettes) <= palIdx then
    begin
      SetLength(FPalettes, palIdx + 1);
      for i := 0 to palIdx do
        SetLength(FPalettes[i].PaletteRGB, FPaletteSize);

      FPaletteCount := Length(FPalettes);
    end;

    for i := 0 to FPaletteSize - 1 do
      FPalettes[palIdx].PaletteRGB[i] := ReadDWord and $ffffff;
  end;

  procedure SetTMI(tileIdx: Integer; attrs: Integer; var TMI: TTileMapItem);
  begin
    TMI.TileIdx := tileIdx;
    TMI.HMirror := attrs and 1 <> 0;
    TMI.VMirror := attrs and 2 <> 0;

    TMI.IsPredicted := False;

    if InRange(tileIdx, 0, High(FTiles)) then
      Inc(FTiles[tileIdx]^.UseCount);

    //if InRange(palIdx, 0, High(FPalettes)) then
    //  Inc(FPalettes[palIdx].UseCount);
  end;

  function NextFrame(KF: TKeyFrame): TFrame;
  begin
    Inc(frmIdx);
    Result := TFrame.Create(Self, frmIdx);
    Result.PKeyFrame := kf;

    Result.FrameTiles := TTile.Array1DNew(FTileMapSize, True, False);
    Result.CompressFrameTiles;

    SetLength(FFrames, frmIdx + 1);
    FFrames[frmIdx] := Result;

    Write(Length(FFrames):8, ' / ', frmCount:8, #13);
  end;

  procedure SkipBlock(frm: TFrame; SkipCount: Integer; var tmPos: Integer);
  var
    i: Integer;
    sx, sy: Integer;
  begin
    Assert(frm.Index > 0);
    for i := tmPos to tmPos + SkipCount - 1 do
    begin
      DivMod(i, FTileMapWidth, sy, sx);
      frm.TileMap[sy, sx].IsPredicted := True;
      frm.TileMap[sy, sx].Attrs.MotionX := 0;
      frm.TileMap[sy, sx].Attrs.MotionY := 0;
    end;
    tmPos += SkipCount;
  end;

var
  Header: TGTMHeader;
  Command, prevCommand: TGTMCommand;
  CommandData: Word;
  loadedFrmCount, tmPos: Integer;
  tileIdx: Cardinal;
  palIdx: Word;
  frm: TFrame;
  kf: TKeyFrame;
  TMI: PTileMapItem;
begin
  FillChar(Header, SizeOf(Header), 0);

  AStream.ReadBuffer(Header, SizeOf(Header.FourCC));
  AStream.Seek(0, soBeginning);

  frmCount := -1;
  if Header.FourCC = 'GTMv' then
  begin
    AStream.ReadBuffer(Header, SizeOf(Header));
    AStream.Seek(Header.WholeHeaderSize, soBeginning);
    frmCount := Header.FrameCount;
  end;

  ClearAll(True);

  frm := nil;
  frmIdx := -1;
  loadedFrmCount := 0;
  KFStream := TMemoryStream.Create;
  try
    repeat
      KFStream.Clear;
      LZDecompress(AStream, KFStream);
      KFStream.Seek(0,soBeginning);

      // add a keyframe
      SetLength(FKeyFrames, Length(FKeyFrames) + 1);
      kf := TKeyFrame.Create(Self, High(FKeyFrames), loadedFrmCount, -1);
      FKeyFrames[High(FKeyFrames)] := kf;

      prevCommand := gtExtendedCommand;
      tmPos := 0;
      repeat
        ReadCmd(Command, CommandData);

        case Command of
          gtExtendedCommand:
          begin
            if CommandData = 0 then
              ReadSettings
            else
              KFStream.Seek(ReadDWord, soCurrent);
          end;
          gtSetDimensions:
          begin
            ReadDimensions;
          end;
          gtTileSet:
          begin
            ReadTiles(CommandData);
          end;
          gtLoadPalette:
          begin
            ReadPalette;
          end;
          gtFrameEnd:
          begin
            Assert(tmPos = FTileMapSize, 'Incomplete tilemap');

            // will load to create a new frame
            frm := nil;
            tmPos := 0;
            Inc(loadedFrmCount);

            if (CommandData and 1) <> 0 then // keyframe end?
              Break;
          end;
          //gtSkipBlock:
          //begin
          //  // next frame if needed
          //  if frm = nil then
          //    frm := NextFrame(kf);
          //
          //  SkipBlock(frm, CommandData + 1, tmPos);
          //end;
          //gtShortTileIdxShortPalIdx, gtLongTileIdxShortPalIdx, gtLongTileIdxLongPalIdx:
          //begin
          //  if Command in [gtLongTileIdxLongPalIdx] then
          //    palIdx := ReadWord
          //  else
          //    palIdx := (CommandData shr 2) and ((1 shl (CGTMCommandBits - 2)) - 1);
          //
          //  if Command in [gtShortTileIdxShortPalIdx] then
          //    tileIdx := ReadWord
          //  else
          //    tileIdx := ReadDWord;
          //
          //  // next frame if needed
          //  if frm = nil then
          //    frm := NextFrame(kf);
          //
          //  tileIdx := rawTileIdxToTileIdx[tileIdx];
          //
          //  SetTMI(tileIdx, palIdx, CommandData, frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth]);
          //  Inc(tmPos);
          //end;
          //gtPredictedTileShortOffsets:
          //begin
          //  // next frame if needed
          //  if frm = nil then
          //    frm := NextFrame(kf);
          //
          //  TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];
          //
          //  TMI^.Attrs.MotionX := (CommandData and 31) - (CommandData and 32);
          //  TMI^.Attrs.MotionY := ((CommandData shr 6) and 31) - ((CommandData shr 6) and 32);
          //  TMI^.Attrs.MotionBackBufferOffset := 1;
          //  TMI^.IsPredicted := True;
          //
          //  Inc(tmPos);
          //end;
          //gtPredictedTileLongOffsets:
          //begin
          //  // next frame if needed
          //  if frm = nil then
          //    frm := NextFrame(kf);
          //
          //  TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];
          //
          //  TMI^.Attrs.MotionX := ShortInt(ReadByte);
          //  TMI^.Attrs.MotionY := ShortInt(ReadByte);
          //  TMI^.Attrs.MotionBackBufferOffset := CommandData + 1;
          //  TMI^.IsPredicted := True;
          //
          //  Inc(tmPos);
          //end;
          //gtIntraTile:
          //begin
          //  palIdx := ReadWord;
          //
          //  tileIdx := Length(FTiles);
          //  TTile.Array1DRealloc(FTiles, tileIdx + 1);
          //
          //  KFStream.Read(FTiles[tileIdx]^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
          //  FTiles[tileIdx]^.Active := True;
          //
          //  // next frame if needed
          //  if frm = nil then
          //    frm := NextFrame(kf);
          //
          //  SetTMI(tileIdx, palIdx, CommandData, frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth]);
          //  Inc(tmPos);
          //end

          else
            Assert(False, 'Unknown command: ' + IntToStr(Ord(Command)) + ', commandData: ' + IntToStr(CommandData) + ', prevCommand: '+ IntToStr(Ord(prevCommand)));
        end;

        prevCommand := Command;

      until False;

      kf.EndFrame := loadedFrmCount - 1;
      kf.FrameCount := kf.EndFrame - kf.StartFrame + 1;

    until AStream.Position >= AStream.Size;
  finally
    KFStream.Free;
  end;

  ReframeUI(FTileMapWidth, FTileMapHeight); // for FPaletteBitmap
end;

procedure TTilingEncoder.SaveStream(AStream: TStream);
const
  CMinBlkSkipCount = 4;
  CMaxBlkSkipCount = 1 shl CGTMCommandBits;
var
  ZStream: TMemoryStream;
  perKfTiles: TIntegerDynArray2;
  globalTiles: TIntegerDynArray;

  procedure DoDWord(v: Cardinal);
  begin
    ZStream.WriteDWord(v);
  end;

  procedure DoWord(v: Word);
  begin
    ZStream.WriteWord(v);
  end;

  procedure DoByte(v: Byte);
  begin
    ZStream.WriteByte(v);
  end;

  procedure DoCmd(Cmd: TGTMCommand; Data: Cardinal);
  begin
    assert(Data < (1 shl CGTMCommandBits));
    assert(Ord(Cmd) < CGTMCommandsCount);

    DoWord((Data shl CGTMCommandCodeBits) or Ord(Cmd));
  end;

  procedure DoAltCmd(Cmd: TGTMCommand; AltCmd: TGTMCommand; IsAlt: Boolean; Data: Cardinal);
  begin
    if IsAlt then
      DoCmd(AltCmd, Data)
    else
      DoCmd(Cmd, Data);
  end;

  procedure DoTMI(const TMI: TTileMapItem);
  var
    tileIdx, finalTileIdx: Integer;
    attrs: Word;
    isKeyFrameTile, isTile16, isTile32, isLongOffsets: Boolean;
  begin
    if TMI.IsPredicted then
    begin
      if TMI.IsBlended then
      begin
        DoCmd(gtPredictedFm1Fm2Blend6x6, ((PByte(@TMI.Attrs.BlendWeight)^ and ((1 shl (CGTMCommandBits - CGTMBlendAlphaShift)) - 1)) shl CGTMBlendAlphaShift) or TMI.Attrs.BlendAlpha);
      end
      else
      begin
        isLongOffsets := not InRange(TMI.Attrs.MotionX, -32, 31) or not InRange(TMI.Attrs.MotionY, -32, 31) or (TMI.Attrs.MotionBackBufferOffset > 1);

        if isLongOffsets then
        begin
          DoCmd(gtPredictedTileOffsets8x8, TMI.Attrs.MotionBackBufferOffset - 1);
          DoByte(PByte(@TMI.Attrs.MotionY)^);
          DoByte(PByte(@TMI.Attrs.MotionX)^);
        end
        else
        begin
          attrs := ((PByte(@TMI.Attrs.MotionY)^ and 63) shl 6) or (PByte(@TMI.Attrs.MotionX)^ and 63);

          DoCmd(gtPredictedTileOffsets6x6, attrs);
        end;
      end;
    end
    else
    begin
      tileIdx := Max(0, TMI.TileIdx);
      finalTileIdx := Max(0, FTiles[tileIdx]^.TmpIndex);

      isKeyFrameTile := finalTileIdx >= Length(globalTiles);
      isTile16 := InRange(finalTileIdx, 1 shl (CGTMCommandBits - 2), High(Word));
      isTile32 := finalTileIdx > High(Word);

      attrs := (Ord(TMI.VMirror) shl 1) or Ord(TMI.HMirror);

      if isKeyFrameTile then
      begin
        finalTileIdx -= Length(globalTiles);
        Assert(finalTileIdx >= 0);
      end;

      if not isTile32 and not isTile16 then
      begin
        DoAltCmd(gtGlobalTile10, gtKeyFrmTile10, isKeyFrameTile, attrs or (finalTileIdx shl 2));
      end
      else if not isTile32 then
      begin
        DoAltCmd(gtGlobalTile16, gtKeyFrmTile16, isKeyFrameTile, attrs);
        DoWord(finalTileIdx);
      end
      else
      begin
        DoAltCmd(gtGlobalTile32, gtKeyFrmTile32, isKeyFrameTile, attrs);
        DoDWord(finalTileIdx);
      end;
    end;
  end;

  procedure WritePalettes;
  var
    colIdx, palIdx, col: Integer;
  begin
    for palIdx := 0 to FPaletteCount - 1 do
    begin
      DoCmd(gtLoadPalette, (0 shl 6) or (FPaletteSize - 1));
      DoWord(palIdx);
      for colIdx := 0 to FPaletteSize - 1 do
      begin
        col := 0;
        if InRange(palIdx, 0, High(FPalettes)) and InRange(colIdx, 0, High(FPalettes[palIdx].PaletteRGB)) then
          col := FPalettes[palIdx].PaletteRGB[colIdx];

        if col = cDitheringNullColor then
          col := $ffffff;

        DoDWord(col or $ff000000);
      end;
    end;
  end;

  procedure WriteTiles(const AList: TIntegerDynArray; IsKF: Boolean; AStart: Integer = 0);
  var
    tlIdx: Integer;
  begin
    if Length(AList) > 0 then
    begin
      DoCmd(gtTileSet, Ord(IsKF));
      DoDWord(AStart); // start tile
      DoDWord(AStart + High(AList)); // end tile

      for tlIdx := 0 to High(AList) do
        DoWord(Tiles[AList[tlIdx]]^.PalIdx);

      for tlIdx := 0 to High(AList) do
        ZStream.Write(Tiles[AList[tlIdx]]^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
    end;
  end;

  procedure WriteDimensions;
  var
    kfIdx, maxTileCount: Integer;
  begin
    maxTileCount := 0;
    for kfIdx := 0 to High(perKfTiles) do
      maxTileCount := max(maxTileCount, Length(perKfTiles[kfIdx]));

    DoCmd(gtSetDimensions, 0);
    DoDWord(FTileMapWidth); // frame tilemap width
    DoDWord(FTileMapHeight); // frame tilemap height
    DoDWord(round(1000*1000*1000 / FFramesPerSecond)); // frame length in nanoseconds
    DoDWord(Length(globalTiles)); // global tile count
    DoDWord(maxTileCount); // maximum keyframe tile count
  end;

  procedure WriteSettings;
  begin
    DoCmd(gtExtendedCommand, 0);
    ZStream.WriteAnsiString(GetSettings);
  end;

  procedure MapTiles;
  var
    tIdx, frmIdx, sy, sx, kfIdx: Integer;
    perKFPos: TIntegerDynArray;
    globalPos: Integer;
    TMI: PTileMapItem;
    tile: PTile;
  begin
    // init

    for tIdx := 0 to High(FTiles) do
      FTiles[tIdx]^.TmpIndex := -1;

    // tag tiles with unique KF index

    for frmIdx := 0 to High(FFrames) do
      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMI := @FFrames[frmIdx].TileMap[sy, sx];

          tIdx := TMI^.TileIdx;
          if tIdx < 0 then
            Continue;

          tile := FTiles[tIdx];
          kfIdx := FFrames[frmIdx].PKeyFrame.Index;

          if tile^.TmpIndex < 0 then
            tile^.TmpIndex := kfIdx
          else if tile^.TmpIndex <> kfIdx then
            tile^.TmpIndex := High(Integer);
        end;

    // count tiles

    SetLength(perKFPos, Length(FKeyFrames));
    globalPos := 0;
    for tIdx := 0 to High(FTiles) do
    begin
      tile := FTiles[tIdx];
      kfIdx := tile^.TmpIndex;

      if kfIdx >= 0 then
      begin
        if kfIdx < High(Integer) then
          Inc(perKFPos[kfIdx])
        else
          Inc(globalPos);
      end;
    end;

    // dim arrays & log TileCount

    SetLength(globalTiles, globalPos);
    globalPos := 0;
    WriteLn('Global      , TileCount: ', Length(globalTiles):8);
    SetLength(perKfTiles, Length(FKeyFrames));
    for kfIdx := 0 to High(perKfTiles) do
    begin
      SetLength(perKfTiles[kfIdx], perKFPos[kfIdx]);
      perKFPos[kfIdx] := 0;
      WriteLn('KF: ', FKeyFrames[kfIdx].StartFrame:8,', TileCount: ', Length(perKfTiles[kfIdx]):8);
    end;

    // fill arrays with tile indexes

    for tIdx := 0 to High(FTiles) do
    begin
      tile := FTiles[tIdx];
      kfIdx := tile^.TmpIndex;

      if kfIdx >= 0 then
      begin
        if kfIdx < High(Integer) then
        begin
          tile^.TmpIndex := Length(globalTiles) + perKFPos[kfIdx];

          perKfTiles[kfIdx, perKFPos[kfIdx]] := tIdx;
          Inc(perKFPos[kfIdx]);
        end
        else
        begin
          tile^.TmpIndex := globalPos;

          globalTiles[globalPos] := tIdx;
          Inc(globalPos);
        end;
      end;
    end;
  end;

var
  StartPos, StreamSize, LastKF, KFFrmCnt, KFSize, BlkSkipCount: Integer;
  kfIdx, frmIdx, yx, yxs, cs, sx, sy: Integer;
  bpsAcc: UInt64;
  IsKF: Boolean;
  KeyFrame: TKeyFrame;
  Frame: TFrame;
  Header: TGTMHeader;
  KFInfo: array of TGTMKeyFrameInfo;
begin
  StartPos := AStream.Size;

  FillChar(Header, SizeOf(Header), 0);
  Header.FourCC := 'GTMv';
  Header.RIFFSize := SizeOf(Header) - SizeOf(Header.FourCC) - SizeOf(Header.RIFFSize);
  Header.EncoderVersion := 5; // 2 -> fixed blending extents; 3 -> *AddlBlendTileIdx; 4 -> PredictMotion; 5 -> Blend,Glob/KF,TilePalIdxs
  Header.FramePixelWidth := FScreenWidth;
  Header.FramePixelHeight := FScreenHeight;
  Header.KFCount := Length(FKeyFrames);
  Header.FrameCount := Length(FFrames);
  Header.AverageBytesPerSec := 0;
  Header.KFMaxBytesPerSec := 0;
  Header.PSNRHVS := Round(FReconstructPSNR * 1000.0 * 1000.0);
  AStream.Write(Header, SizeOf(Header));

  SetLength(KFInfo, Length(FKeyFrames));
  for kfIdx := 0 to High(FKeyFrames) do
  begin
    FillChar(KFInfo[kfIdx], SizeOf(KFInfo[0]), 0);
    KFInfo[kfIdx].FourCC := 'GTMk';
    KFInfo[kfIdx].RIFFSize := SizeOf(KFInfo[0]) - SizeOf(KFInfo[0].FourCC) - SizeOf(KFInfo[0].RIFFSize);
    KFInfo[kfIdx].KFIndex := kfIdx;
    KFInfo[kfIdx].FrameIndex := FKeyFrames[kfIdx].StartFrame;
    KFInfo[kfIdx].TimeCodeMillisecond := Round(1000.0 * FKeyFrames[kfIdx].StartFrame / FFramesPerSecond);
    KFInfo[kfIdx].PSNRHVS := Round(FKeyFrames[kfIdx].ReconstructPSNR * 1000.0 * 1000.0);
    AStream.Write(KFInfo[kfIdx], SizeOf(KFInfo[0]));
  end;

  Header.WholeHeaderSize := AStream.Size - StartPos;

  StartPos := AStream.Size;

  ZStream := TMemoryStream.Create;
  try
    MapTiles;

    WriteSettings;
    WriteDimensions;
    WritePalettes;
    WriteTiles(globalTiles, False);

    bpsAcc := 0;
    LastKF := 0;
    for kfIdx := 0 to High(FKeyFrames) do
    begin
      KeyFrame := FKeyFrames[kfIdx];

      WriteTiles(perKfTiles[kfIdx], True);

      for frmIdx := KeyFrame.StartFrame to KeyFrame.EndFrame do
      begin
        Frame := FFrames[frmIdx];

        cs := 0;
        BlkSkipCount := 0;
        for yx := 0 to FTileMapSize - 1 do
        begin
          if BlkSkipCount > 0 then
          begin
            // handle an ongoing block skip

            Dec(BlkSkipCount);
          end
          else
          begin
            // find a potential new skip

            BlkSkipCount := 0;
            for yxs := yx to FTileMapSize - 1 do
            begin
              DivMod(yxs, FTileMapWidth, sy, sx);
              if not Frame.TileMap[sy, sx].IsSmoothed then
                Break;
              Inc(BlkSkipCount);
            end;
            BlkSkipCount := min(CMaxBlkSkipCount, BlkSkipCount);

            // filter using heuristics to avoid unbeneficial skips

            if BlkSkipCount >= CMinBlkSkipCount then
            begin
              //writeln('blk ', BlkSkipCount);

              DoCmd(gtPredictedOffsetBlock0x0, BlkSkipCount - 1);
              Inc(cs, BlkSkipCount);
              Dec(BlkSkipCount);
            end
            else
            begin
              // standard case: emit tilemap item

              BlkSkipCount := 0;

              DivMod(yx, FTileMapWidth, sy, sx);
              DoTMI(Frame.TileMap[sy, sx]);
              Inc(cs);
            end;
          end;
        end;
        Assert(cs = FTileMapSize, 'incomplete TM');
        Assert(BlkSkipCount = 0, 'pending skips');

        IsKF := (frmIdx = KeyFrame.EndFrame);

        DoCmd(gtFrameEnd, Ord(IsKF));

        if IsKF then
        begin
          KFFrmCnt := KeyFrame.EndFrame - LastKF + 1;
          LastKF := KeyFrame.EndFrame + 1;

          AStream.Position := AStream.Size;
          KFSize := AStream.Position;
          LZCompress(ZStream, AStream);

          KFSize := AStream.Size - KFSize;

          KFInfo[kfIdx].RawSize := ZStream.Size;
          KFInfo[kfIdx].CompressedSize := KFSize;
          Header.KFMaxBytesPerSec := max(Header.KFMaxBytesPerSec, round(KFSize * FFramesPerSecond / KFFrmCnt));
          bpsAcc += KFSize;

          WriteLn('KF: ', KeyFrame.StartFrame:8, ', FCnt: ', KFFrmCnt:4, ', Raw: ', KFInfo[kfIdx].RawSize / 1024:10:3, ' KB', ', Written: ', KFSize / 1024:10:3, ' KB', ', Bitrate: ', (KFSize / 1024.0 * 8.0 / KFFrmCnt):8:2, ' kbpf   (', (KFSize / 1024.0 * 8.0 / KFFrmCnt * FFramesPerSecond):8:2, ' kbps)');

          ZStream.Clear;
        end;
      end;
    end;
  finally
    ZStream.Free;
  end;

  Header.AverageBytesPerSec := round(bpsAcc * FFramesPerSecond / Length(FFrames));
  AStream.Position := 0;
  AStream.Write(Header, SizeOf(Header));
  for kfIdx := 0 to High(FKeyFrames) do
    AStream.Write(KFInfo[kfIdx], SizeOf(KFInfo[0]));
  AStream.Position := AStream.Size;

  StreamSize := AStream.Size - StartPos;

  WriteLn('Written: ', StreamSize / 1024:10:3, ' KBytes', ', Bitrate: ', (StreamSize / 1024.0 * 8.0 / Length(FFrames)):8:2, ' kbpf  (', (StreamSize / 1024.0 * 8.0 / Length(FFrames) * FFramesPerSecond):8:2, ' kbps)');
end;

constructor TTilingEncoder.Create;
begin
  FormatSettings.DecimalSeparator := '.';
  InitializeCriticalSection(FCS);

  FGamma[0] := 1.0;
  FGamma[1] := 0.6;

  FInputBitmap := TBitmap.Create;
  FOutputBitmap := TBitmap.Create;
  FTilesBitmap := TBitmap.Create;
  FPaletteBitmap := TBitmap.Create;

  FRenderPrevFrameIndex := -1;
  FRenderPredicted := True;
  FRenderMirrored := True;
  FRenderOutputDithered := True;

  FRenderPage := rpOutput;
  ReframeUI(80, 45);
  FFramesPerSecond := 24.0;

  LoadDefaultSettings;
end;

destructor TTilingEncoder.Destroy;
begin
  ClearAll(False);

  DeleteCriticalSection(FCS);

  FInputBitmap.Free;
  FOutputBitmap.Free;
  FTilesBitmap.Free;
  FPaletteBitmap.Free;
end;

procedure TTilingEncoder.Run(AStep: TEncoderStep);
var
  step: TEncoderStep;
begin
  case AStep of
    esAll:
      for step := Succ(esAll) to High(step) do
        Run(step);
    esLoad:
      Load;
    esReduce:
      Reduce;
    esPreparePalettes:
      PreparePalettes;
    esDither:
      Dither;
    esReconstruct:
      Reconstruct;
    esPredict:
      PredictMotion;
    esReindex1,
    esReindex2:
      Reindex(AStep);
    esSave:
      Save;
  end;
end;

procedure TTilingEncoder.RunRange(AStartStep, AEndStep: TEncoderStep);
var
  step: TEncoderStep;
begin
  for step := AStartStep to AEndStep do
    Run(step);
end;

end.

