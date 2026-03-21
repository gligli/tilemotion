unit tilingencoder;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$TYPEDADDRESS ON}
{$CODEALIGN LOCALMIN=16}
{$PACKSET 1}

interface

uses
  windows, Classes, SysUtils, strutils, types, Math, FileUtil, typinfo, zstream, IniFiles, Graphics,
  IntfGraphics, FPimage, FPCanvas, FPWritePNG, GraphType, fgl, bufstream,
  tbbmalloc, extern, utils, powell, mtpool;
type
  TEncoderStep = (esAll = -1, esLoad = 0, esPredict, esReduce, esPreparePalettes, esDither, esReindex1, esReconstruct, esReindex2, esSave);
  TKeyFrameReason = (kfrNone, kfrManual, kfrLength, kfrDecorrelation, kfrEuclidean);
  TRenderPage = (rpNone, rpInput, rpOutput, rpTilesPalette);
  TPsyVisMode = (pvsDCT, pvsWeightedDCT, pvsSpeDCT, pvsWeightedSpeDCT, pvsPSNRHVS);

const
  cEncoderStepLen: array[TEncoderStep] of Integer = ({esAll} -1, {esLoad} 5, {esPredict} 1, {esReduce} 3, {esPreparePalettes} 3, {esDither} 2, {esReindex1} 3, {esReconstruct} 2, {esReindex2} 3, {esSave} 1);

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
  // PredictedTileShortOffsets:        data -> none; commandBits -> y offset (6 bits); x offset (6 bits)
  // PredictedTileLongOffsets:         data -> x offset (8 bits); y offset (8 bits); commandBits -> none (10 bits); backbuffer offset - 1 (2 bits)
  // ShortTileIdxShortPalIdx:          data -> tile index (16 bits); commandBits -> palette index (10 bits); V mirror (1 bit); H mirror (1 bit)
  // LongTileIdxShortPalIdx:           data -> tile index (32 bits); commandBits -> palette index (10 bits); V mirror (1 bit); H mirror (1 bit)
  // LongTileIdxLongPalIdx:            data -> palette index (16 bits); tile index (32 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // IntraTile:                        data -> palette index (16 bits); indexes per pixel (64 bytes); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // SkipBlock:                        data -> none; commandBits -> skip count - 1 (12 bits)
  // PredictedWeight:                  data -> none; commandBits -> alpha additive weight (1024 + w) (10 bits); backbuffer offset - 1 (2 bits)
  //
  // (insert new commands here...)
  //
  // FrameEnd:                         data -> none; commandBits -> none (11 bits); keyframe end (1 bit)
  // LoadPalette:                      data -> palette index (16 bits); { RGBA bytes (32bits) } * indexes count; commandBits -> palette format (0: RGBA32) (12 bits)
  // TileSet:                          data -> start tile (32 bits); end tile (32 bits); { indexes per pixel (64 bytes) } * count; commandBits -> indexes count per palette
  // SetDimensions:                    data -> width in tiles (16 bits); height in tiles (16 bits); frame length in nanoseconds (32 bits) (2^32-1: still frame); maximum tile count (32 bits); commandBits -> none
  // ExtendedCommand:                  data -> following bytes count (32 bits); custom commands, proprietary extensions, ...; commandBits -> extended command index (12 bits)

  TGTMCommand = (
    gtPredictedTileShortOffsets = 0,
    gtPredictedTileLongOffsets = 1,
    gtShortTileIdxShortPalIdx = 2,
    gtLongTileIdxShortPalIdx = 3,
    gtLongTileIdxLongPalIdx = 4,
    gtIntraTile = 5,
    gtSkipBlock = 6,
    gtPredictedWeight = 7,

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
    PalIdx_Initial: Integer;
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
    procedure WeightRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer; AWeight: Integer);
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
    PalIdx: Integer; // 4
    Error: Cardinal; // 4
    Attrs: record case Boolean of // 3 * 1
      False: (MotionX, MotionY: ShortInt; MotionBackBufferOffset: Byte);
      True: (Weight: SmallInt; WeightBackBufferOffset: Byte);
    end;
    Flags: set of (tmfHMirror, tmfVMirror, tmfPredicted, tmfWeighted); // 1
  end;

{$if SizeOf(TTileMapItem) <> 16}
  {$error misaligned SizeOf(TTileMapItem) !}
{$endif}

  PTileMapItem = ^TTileMapItem;

  TTileMapItems = array of TTileMapItem;
  TTileMapItems2 = array of TTileMapItems;

  { TTileMapItemHelper }

  TTileMapItemHelper = record helper for TTileMapItem
  private
    function GetHMirror: Boolean;
    function GetIsWeighted: Boolean;
    function GetIsSmoothed: Boolean;
    function GetVMirror: Boolean;
    procedure SetHMirror(AValue: Boolean);
    procedure SetIsWeighted(AValue: Boolean);
    procedure SetVMirror(AValue: Boolean);
    function GetIsPredicted: Boolean;
    procedure SetIsPredicted(AValue: Boolean);
  public
    procedure Reset(AKeepMirrors: Boolean);

    property IsPredicted: Boolean read GetIsPredicted write SetIsPredicted;
    property IsWeighted: Boolean read GetIsWeighted write SetIsWeighted;
    property IsSmoothed: Boolean read GetIsSmoothed;
    property HMirror: Boolean read GetHMirror write SetHMirror;
    property VMirror: Boolean read GetVMirror write SetVMirror;
  end;

  { TTilingDataset }

  TTilingDataset = record
  type
    TDSTilePalIdx = packed record
      TileIdx: Integer;
      PalIdx: Integer;
    end;
  public

    KNNSize: Integer;
    Dataset: TSmallIntDynArray;
    DatasetPtrs: array of PDCTScalar;
    DSToTilePalIdx: array of TDSTilePalIdx;
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

    function PowellWeight(const x: TVector; data: Pointer): TScalar;
    procedure GetPredictExtents(ARadius, ADY, ADX: Integer; out oxmn, oxmx, oymn, oymx: Integer);

    function PredictTileWeight(ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ABuffer: TIntegerDynArray2): Cardinal;
    function PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray; const APenaltyLUT: TCardinalDynArray): Cardinal;
    function PredictTileIntra(ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Cardinal;

    // processes

    procedure LoadFromImage(AImageWidth, AImageHeight: Integer; AImage: PInteger);
    procedure PrepareDCTs(AMTPool: TMTPool;const ADCTs: TDCTDynArray; const ABuffer: TIntegerDynArray2);
    procedure IntraReduce(ATargetTileCount: Integer);
    procedure Predict(AMTPool: TMTPool;ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer; AFrameBuffer: TFrameBuffer);
    procedure Reconstruct(AMTPool: TMTPool;ARadius: Integer; AFrameBuffer: TFrameBuffer);
    procedure DirectBlit(AMTPool: TMTPool; const ABuffer: TIntegerDynArray2);
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
    FDCTLut:array[TPsyVisMode, 0..cUnrolledDCTSize - 1] of TFloat;
    FInvDCTLutDouble:array[TPsyVisMode, 0..cUnrolledDCTSize - 1] of Double;
    FDCTSnake: array[0 .. cTileDCTSize - 1] of Integer;

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
    FReconstructReuseMultiplier: Double;
    FMaxThreadCount: Integer;
    FShotTransMaxSecondsPerKF: Double;
    FShotTransMinSecondsPerKF: Double;
    FShotTransCorrelLoThres: Double;

    // GUI state variables

    FRenderPredicted: Boolean;
    FRenderFrameIndex: Integer;
    FRenderOuptutFrameIndex: Integer;
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
    FRenderOutputDirty: Boolean;

    FProgressSyncPos, FProgressSyncMax: Integer;
    FProgressSyncHG: Boolean;

    function GetFrameCount: Integer;
    function GetKeyFrameCount: Integer;
    function GetTiles: PTileDynArray;
    function GetRenderGammaValue: Double;
    procedure SetDitheringYliluoma2MixedColors(AValue: Integer);
    procedure SetFrameCountSetting(AValue: Integer);
    procedure SetFramesPerSecond(AValue: Double);
    procedure SetReconstructReuseMultiplier(AValue: Double);
    procedure SetGlobalTilingQualityBasedTileCount(AValue: Double);
    procedure SetMaxThreadCount(AValue: Integer);
    procedure SetPaletteCount(AValue: Integer);
    procedure SetPaletteSize(AValue: Integer);
    procedure SetMotionPredictRadius(AValue: Integer);
    procedure SetMotionPredictMaxBufferedFrames(AValue: Integer);
    procedure SetRenderFrameIndex(AValue: Integer);
    procedure SetRenderGammaValue(AValue: Double);
    procedure SetRenderMirrored(AValue: Boolean);
    procedure SetRenderOutputDithered(AValue: Boolean);
    procedure SetRenderPage(AValue: TRenderPage);
    procedure SetRenderPaletteIndex(AValue: Integer);
    procedure SetRenderPredicted(AValue: Boolean);
    procedure SetRenderTilePage(AValue: Integer);
    procedure SetGlobalTilingTargetPSNR(AValue: Double);
    procedure SetGlobalTilingTileCount(AValue: Integer);
    procedure SetRenderUseGamma(AValue: Boolean);
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

    procedure ConvertToCpnPixels(const ATile: TTile; FromPal, UseLAB, VMirror, HMirror: Boolean; const APalette: TIntegerDynArray; out ACpnPixels: TCpnPixels); inline;
    procedure ComputeCpnPixelsPsyVisFeatures(const ACpnPixel: TCpnPixels; Mode: TPsyVisMode; ColorCpns: Integer; ADCT: PDCTScalar); inline;

    procedure ComputeTilePsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; FromPal, UseLAB, VMirror, HMirror: Boolean;
     ColorCpns: Integer; const APalette: TIntegerDynArray; ADCT: PDouble); inline; overload;
    procedure ComputeInvTilePsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; UseLAB: Boolean; ColorCpns: Integer; var ATile: TTile);

    // Dithering algorithms ported from http://bisqwit.iki.fi/story/howto/dither/jy/

    class function ColorCompare(r1, g1, b1, r2, g2, b2: Double): Double;
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
    procedure QuantizeUsingYakmo(APalIdx, AColorCount: Integer);
    procedure DoQuantization(APalIdx: Integer);
    procedure OptimizePalettes;

    procedure PrepareReconstruct;
    procedure FinishReconstruct;

    procedure ReindexTiles(OnRGBPixels: Boolean);
    procedure MakeTilesUnique(OnRGBPixels: Boolean);
    procedure InitMergeTiles;
    procedure FinishMergeTiles;
    procedure MergeTiles(const TileIndexes: TIntegerDynArray; TileCount: Integer; BestTileIdx: Int64);

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
    property ReconstructReuseMultiplier: Double read FReconstructReuseMultiplier write SetReconstructReuseMultiplier;
    property MaxThreadCount: Integer read FMaxThreadCount write SetMaxThreadCount;
    property ShotTransMaxSecondsPerKF: Double read FShotTransMaxSecondsPerKF write SetShotTransMaxSecondsPerKF;
    property ShotTransMinSecondsPerKF: Double read FShotTransMinSecondsPerKF write SetShotTransMinSecondsPerKF;
    property ShotTransCorrelLoThres: Double read FShotTransCorrelLoThres write SetShotTransCorrelLoThres;

    // GUI state variables

    property RenderPlaying: Boolean read FRenderPlaying write FRenderPlaying;
    property RenderFrameIndex: Integer read FRenderFrameIndex write SetRenderFrameIndex;
    property RenderPredicted: Boolean read FRenderPredicted write SetRenderPredicted;
    property RenderMirrored: Boolean read FRenderMirrored write SetRenderMirrored;
    property RenderOutputDithered: Boolean read FRenderOutputDithered write SetRenderOutputDithered;
    property RenderUseGamma: Boolean read FRenderUseGamma write SetRenderUseGamma;
    property RenderPaletteIndex: Integer read FRenderPaletteIndex write SetRenderPaletteIndex;
    property RenderTilePage: Integer read FRenderTilePage write SetRenderTilePage;
    property RenderGammaValue: Double read GetRenderGammaValue write SetRenderGammaValue;
    property RenderPage: TRenderPage read FRenderPage write SetRenderPage;
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
  CGTMBlendWeightBaseShift = 10;
  CGTMBlendWeightMax = 511;
  CGTMBlendWeightMin = -CGTMBlendWeightMax - 1;

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
  PalIdx := -1;
  Error := 0;
  Attrs.MotionX := 0;
  Attrs.MotionY := 0;
  Attrs.MotionBackBufferOffset := 0;
  IsPredicted := False;
  IsWeighted := False;
  if not AKeepMirrors then
    Flags := [];
end;

function TTileMapItemHelper.GetHMirror: Boolean;
begin
  Result := tmfHMirror in Flags;
end;

function TTileMapItemHelper.GetIsWeighted: Boolean;
begin
  Result := tmfWeighted in Flags;
end;

function TTileMapItemHelper.GetIsSmoothed: Boolean;
begin
  Result := IsPredicted and
    ((not IsWeighted and (Attrs.MotionX = 0) and (Attrs.MotionY = 0) and (Attrs.MotionBackBufferOffset = 1)) or
     (IsWeighted and (Attrs.Weight = 0)));
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

procedure TTileMapItemHelper.SetIsWeighted(AValue: Boolean);
begin
  if AValue then
    Flags += [tmfWeighted]
  else
    Flags -= [tmfWeighted];
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
    PTile(data)^.PalIdx_Initial := -1;
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
    AArray[i]^.PalIdx_Initial := -1;
    Inc(data, size);
  end;
end;

class function TTileHelper.New(ARGBPixels, APalPixels: Boolean): PTile;
begin
  Result := AllocMem(SizeOf(TTile) + IfThen(APalPixels, SizeOf(TPalPixels)) + IfThen(ARGBPixels, SizeOf(TRGBPixels)));
  FillByte(Result^, SizeOf(TTile), 0);

  Result^.HasPalPixels := APalPixels;
  Result^.HasRGBPixels := ARGBPixels;
  Result^.PalIdx_Initial := -1;

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

procedure TTileHelper.WeightRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer; AWeight: Integer);
var
  ty, tx: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    for tx := 0 to cTileWidth - 1 do
    begin
      RGBPixels[ty, tx] := WeightRGB(AFrameBuffer[AY, AX], AWeight, CGTMBlendWeightBaseShift);
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
  PalIdx_Initial := ATile.PalIdx_Initial;
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
    DX, DY: Integer;
    BackBufferOffset: Integer;
    DCT: TDCT;
    FrameBuffer: TIntegerDynArray2;
  end;

  PPowellBlendData = ^TPowellBlendData;

function TFrame.PowellWeight(const x: TVector; data: Pointer): TScalar;
var
  pbData: PPowellBlendData absolute data;
  dx, dy, ty, tx, col, weight: Integer;
  BlendCpnPixels: TCpnPixels;
  BlendDCT: TDCT;
begin
  weight := EnsureRange(Round(x[0]), CGTMBlendWeightMin, CGTMBlendWeightMax);

  dx := pbData^.DX;
  dy := pbData^.DY;

  for ty := 0 to (cTileWidth - 1) do
  begin
    for tx := 0 to (cTileWidth - 1) do
    begin
      col := WeightRGB(pbData^.FrameBuffer[dy, dx], weight, CGTMBlendWeightBaseShift);
      RGBToYUV(col, BlendCpnPixels[0, ty, tx], BlendCpnPixels[1, ty, tx], BlendCpnPixels[2, ty, tx], cDCTScale);
      Inc(dx);
    end;
    Dec(dx, cTileWidth);
    Inc(dy);
  end;

  Encoder.ComputeCpnPixelsPsyVisFeatures(BlendCpnPixels, pvsPSNRHVS, cColorCpns, BlendDCT);

  Result := CompareEuclideanDCTPtr_asm(pbData^.DCT, BlendDCT);

  Result += ApplyWeightPredictionPenalty(weight, pbData^.BackBufferOffset);
end;

procedure TFrame.GetPredictExtents(ARadius, ADY, ADX: Integer; out oxmn, oxmx, oymn, oymx: Integer);
begin
  oymn := Max(0, ADY - ARadius - 1);
  oymx := Min(Encoder.FScreenHeight - cTileWidth, ADY + ARadius);
  oxmn := Max(0, ADX - ARadius - 1);
  oxmx := Min(Encoder.FScreenWidth - cTileWidth, ADX + ARadius);
end;

procedure TFrame.PrepareDCTs(AMTPool: TMTPool; const ADCTs: TDCTDynArray; const ABuffer: TIntegerDynArray2);

  procedure DoDCTs(AIndex: PtrInt; AData: Pointer);
  var
    x, yx: Integer;
    DCTTile: PTile;
    CpnPixels: TCpnPixels;
  begin
    yx := AIndex * (Encoder.FScreenWidth - cTileWidth + 1);

    DCTTile := TTile.New(True, False);
    try
      for x := 0 to Encoder.FScreenWidth - cTileWidth do
      begin
        DCTTile^.CopyRGBPixels(ABuffer, AIndex, x);

        Encoder.ConvertToCpnPixels(DCTTile^, False, False, False, False, nil, CpnPixels);
        Encoder.ComputeCpnPixelsPsyVisFeatures(CpnPixels, pvsPSNRHVS, cColorCpns, ADCTs[yx]);

        Inc(yx);
      end;
    finally
      TTile.Dispose(DCTTile);
    end;
  end;

begin
  AMTPool.DoLocalProc(@DoDCTs, 0, Encoder.FScreenHeight - cTileWidth);
end;

function TFrame.PredictTileWeight(ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT;
  const ABuffer: TIntegerDynArray2): Cardinal;
var
  bestWeight: Integer;
  pbData: TPowellBlendData;
  X: TVector;
begin
  Assert(InRange(ABackBufferOffset, 1, Encoder.MotionPredictMaxBufferedFrames));

  pbData.DX := ADX;
  pbData.DY := ADY;
  pbData.BackBufferOffset := ABackBufferOffset;
  pbData.DCT := ADCT;
  pbData.FrameBuffer := ABuffer;

  X := [0.0];

  Result := Round(PowellMinimize(@PowellWeight, X, (1 shl CGTMBlendWeightBaseShift) * 0.25, 0.5, 0.5, MaxInt, @pbData)[0]);
  bestWeight := EnsureRange(Round(x[0]), CGTMBlendWeightMin, CGTMBlendWeightMax);

  if not ATMI^.IsPredicted or (Result < ATMI^.Error) then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsWeighted := True;
    ATMI^.Error := Result;
    ATMI^.Attrs.Weight := bestWeight;
    ATMI^.Attrs.WeightBackBufferOffset := ABackBufferOffset;
  end
  else
  begin
    Result := High(Cardinal);
  end;
end;

function TFrame.PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT;
  const ADCTs: TDCTDynArray; const APenaltyLUT: TCardinalDynArray): Cardinal;
var
  oy, yx, penLutMidOff, penLutWH: Integer;
  state: TDCTCribbleState;
  PrevDCTPtr: PDCTScalar;
begin
  if ATMI^.IsPredicted then
    Result := ATMI^.Error
  else
    Result := High(Cardinal);

  state.Error := Result;
  state.Y := MaxInt;
  state.X := MaxInt;
  state.DY := ADY;
  state.DX := ADX;

  GetPredictExtents(ARadius, state.DY, state.DX, state.oxmn, state.oxmx, state.oymn, state.oymx);

  penLutMidOff := ARadius + 1;
  penLutWH := penLutMidOff shl 1;
  state.PenaltyLUT := @APenaltyLUT[(penLutMidOff + (state.oymn - ADY)) * penLutWH + penLutMidOff];
  for oy := state.oymn to state.oymx do
  begin
    yx := oy * (Encoder.FScreenWidth - cTileWidth + 1) + state.oxmn;
    PrevDCTPtr := ADCTs[yx];

    CribbleEuclideanDCTPtr_asm(ADCT, PrevDCTPtr, @state, oy);

    Inc(state.PenaltyLUT, penLutWH);
  end;

  if not ATMI^.IsPredicted or (state.Error < ATMI^.Error) then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsWeighted := False;
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
  ATMI^.IsWeighted := False;
  ATMI^.Error := PSNRToEuclidean(PSNRAcc / PSNRCnt);
  ATMI^.Attrs.MotionY := bestY - ADY;
  ATMI^.Attrs.MotionX := bestX - ADX;
end;

procedure TFrame.Predict(AMTPool: TMTPool; ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer; AFrameBuffer: TFrameBuffer);
var
  PenaltyLUT: TCardinalDynArray;

  procedure DoXY(AIndex: PtrInt; AData: Pointer);
  var
    dx, dy, sy, sx: Integer;
    TMI: PTileMapItem;
    FrameTile: PTile;
    CurCpnPixels: TCpnPixels;
    CurDCT: TDCT;
  begin
    DivMod(AIndex, Encoder.FTileMapWidth, sy, sx);

    TMI := @TileMap[sy, sx];
    FrameTile := FrameTiles[AIndex];

    Encoder.ConvertToCpnPixels(FrameTile^, False, False, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, nil, CurCpnPixels);
    Encoder.ComputeCpnPixelsPsyVisFeatures(CurCpnPixels, pvsPSNRHVS, cColorCpns, CurDCT);

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    if ABackBufferOffset = 0 then
    begin
      PredictTileIntra(dy, dx, TMI, CurDCT, ADCTBuffer.GetBuffer)
    end
    else
    begin
      PredictTileWeight(ABackBufferOffset, dy, dx, TMI, CurDCT, AFrameBuffer.GetBuffer(-ABackBufferOffset));
      PredictTileMotion(ARadius, ABackBufferOffset, dy, dx, TMI, CurDCT, ADCTBuffer.GetBuffer(-ABackBufferOffset), PenaltyLUT);
    end;
  end;

var
  x, y, penLutMidOff, penLutWH: Integer;
  pPenalty: PCardinal;
begin
  Assert(ARadius >= 0);
  Assert(ABackBufferOffset >= 0);

  if ARadius = 0 then
    Exit;

  Dec(ARadius);

  penLutMidOff := ARadius + 1;
  penLutWH := penLutMidOff shl 1;
  SetLength(PenaltyLUT, Sqr(penLutWH));
  pPenalty := @PenaltyLUT[0];
  for x := 0 to penLutWH - 1 do
    for y := 0 to penLutWH - 1 do
    begin
      pPenalty^ := ApplyMotionPredictionPenalty(x, y, penLutMidOff, penLutMidOff, ABackBufferOffset);
      Inc(pPenalty);
    end;

  AMTPool.DoLocalProc(@DoXY, 0, Encoder.FTileMapSize - 1);
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

  procedure DoDCT(AIndex: PtrInt; AData: Pointer);
  var
    Tile: PTile;
  begin
    Tile := FrameTiles[AIndex];
    Assert(Tile^.Active);

    Encoder.ComputeTilePsyVisFeatures(Tile^, pvsPSNRHVS, False, False, False, False, cColorCpns, nil, @YakmoDataset[AIndex, 0]);
  end;

var
  nbTiles, DSLen, sy, sx, iDS, iCluster, iDCT: Integer;

  Tile: PTile;
  TMI: PTileMapItem;
  Yakmo: PYakmo;

  DCTDouble: array[0 .. cTileDCTSize - 1] of Double;
  YakmoCentroids: TDoubleDynArray2;
  YakmoClusters: TIntegerDynArray;
begin
  AcquireFrameTiles;
  try
    DSLen := Encoder.FTileMapSize;

    // compute frame tiles DCT

    SetLength(YakmoDataset, DSLen, cTileDCTSize);
    TMTPool.DoStandaloneLocalProc(@DoDCT, 0, DSLen - 1, Encoder.MaxThreadCount);

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
        DCTDouble[iDCT] := NanDef(YakmoCentroids[iCluster, iDCT], 0.0);

      Encoder.ComputeInvTilePsyVisFeatures(DCTDouble, pvsPSNRHVS, False, cColorCpns, Tile^);
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

procedure TFrame.DirectBlit(AMTPool: TMTPool; const ABuffer: TIntegerDynArray2);

  procedure DoBlit(AIndex: PtrInt; AData: Pointer);
  var
    dx, dy, sx, yx: Integer;
    FrameTile: PTile;
  begin
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
  AMTPool.DoLocalProc(@DoBlit, 0, Encoder.FTileMapHeight - 1);
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

procedure TFrame.Reconstruct(AMTPool: TMTPool; ARadius: Integer; AFrameBuffer: TFrameBuffer);
var
  DS: PTilingDataset;

  procedure DoXY(AIndex: PtrInt; AData: Pointer);
  var
    sx, sy, dx, dy, ty, tx, dsIdx: Integer;
    knnErr: Cardinal;
    knnPSNR, mpPSNR: Double;

    FrameTile, Tile: PTile;
    TMI: PTileMapItem;

    FrontBuf, BackBuf, M1Buf: TIntegerDynArray2;
    FTDCT: TDCT;
    FTCpnPixels: TCpnPixels;
  begin
    DivMod(AIndex, Encoder.FTileMapWidth, sy, sx);

    TMI := @TileMap[sy, sx];

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    FrameTile := FrameTiles[AIndex];
    Encoder.ConvertToCpnPixels(FrameTile^, False, False, False, False, nil, FTCpnPixels);
    Encoder.ComputeCpnPixelsPsyVisFeatures(FTCpnPixels, pvsPSNRHVS, cColorCpns, FTDCT);

    // redo motion prediction (account for palette)

    mpPSNR := -Infinity;
    if (Index <> PKeyFrame.StartFrame) and (ARadius >= 0) then
      mpPSNR := EuclideanToPSNR(TMI^.Error);

    // use the KNN dataset to predict a tile with its associated palette

    knnErr := High(Cardinal);
    dsIdx := ann_kdtree_short_search(DS^.ANN, @FTDCT[0], 0, @knnErr);
    if InRange(dsIdx, 0, DS^.KNNSize - 1) then
    begin
      TMI^.TileIdx := DS^.DSToTilePalIdx[dsIdx].TileIdx;
      TMI^.PalIdx := DS^.DSToTilePalIdx[dsIdx].PalIdx;
      knnPSNR := EuclideanToPSNR(knnErr);
    end
    else
    begin
      TMI^.TileIdx := -1;
		    TMI^.PalIdx := -1;
      knnPSNR := -Infinity;
    end;

    // devise which is best

    case CompareValue(knnPSNR, mpPSNR, cPSNREpsilon) of
      GreaterThanValue:
      begin
        // KNN is best

        TMI^.Error := knnErr;
        TMI^.IsPredicted := False;
        FillChar(TMI^.Attrs, SizeOf(TMI^.Attrs), 0);
      end;
      EqualsValue, // motion prediction has priority in case of ties (less bitrate)
      LessThanValue:
      begin
        // motion prediction is best

        TMI^.IsPredicted := True;
        TMI^.TileIdx := -1;
        TMI^.PalIdx := -1;
      end;
    end;

    if TMI^.IsPredicted then
    begin
      // draw fb (motion predicted tile)

      FrontBuf := AFrameBuffer.GetBuffer;
      if TMI^.IsWeighted then
      begin
        M1Buf := AFrameBuffer.GetBuffer(-TMI^.Attrs.WeightBackBufferOffset);
        for ty := 0 to cTileWidth - 1 do
        begin
          for tx := 0 to cTileWidth - 1 do
          begin
            FrontBuf[dy, dx] := WeightRGB(M1Buf[dy, dx], TMI^.Attrs.Weight, CGTMBlendWeightBaseShift);
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
      Tile^.BlitPalPixels(AFrameBuffer.GetBuffer, Encoder.FPalettes[TMI^.PalIdx].PaletteRGB, TMI^.VMirror, TMI^.HMirror, dy, dx);
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

  AMTPool.DoLocalProc(@DoXY, 0, Encoder.FTileMapSize - 1);

  PKeyFrame.LogPSNR;
end;

{ TTilingEncoder }

procedure TTilingEncoder.InitLuts;
var
  pvm: TPsyVisMode;
  c, g, i, v, u, y, x: Int64;
begin
  // gamma

  for g := -1 to High(FGamma) do
    for i := 0 to High(Byte) do
      if g >= 0 then
        FGammaCorLut[g, i] := power(i / 255.0, FGamma[g])
      else
        FGammaCorLut[g, i] := i / 255.0;

  // DCTs / inverse DCTs

  for pvm := Low(TPsyVisMode) to High(TPsyVisMode) do
  begin
    i := 0;
    for c := 0 to cColorCpns - 1 do
      for v := 0 to cTileWidth - 1 do
        for u := 0 to cTileWidth - 1 do
          for y := 0 to cTileWidth - 1 do
            for x := 0 to cTileWidth - 1 do
            begin
              case pvm of
                pvsDCT:
                begin
                  FDCTLut[pvm, i] := cos((x + 0.5) * u * PI / (cTileWidth)) * cos((y + 0.5) * v * PI / (cTileWidth)) * cDCTUVRatio[Min(v, 7), Min(u, 7)];
                  FInvDCTLutDouble[pvm, i] := cos((u + 0.5) * x * PI / (cTileWidth)) * cos((v + 0.5) * y * PI / (cTileWidth)) * cDCTUVRatio[Min(y, 7), Min(x, 7)] * 2 / (cTileWidth) * 2 / (cTileWidth);
                end;
                pvsSpeDCT:
                begin
                  FDCTLut[pvm, i] := cos((x + 0.5) * u * PI / (cTileWidth * 2)) * cos((y + 0.5) * v * PI / (cTileWidth * 2)) * cDCTUVRatio[Min(v, 7), Min(u, 7)];
                  FInvDCTLutDouble[pvm, i] := NaN;
                end;
                pvsWeightedDCT:
                begin
                  FDCTLut[pvm, i] := FDCTLut[pvsDCT, i] * cJPEGWeights[c, v, u];
                  FInvDCTLutDouble[pvm, i] := FInvDCTLutDouble[pvsDCT, i] / cJPEGWeights[c, y, x];
                end;
                pvsWeightedSpeDCT:
                begin
                  FDCTLut[pvm, i] := FDCTLut[pvsSpeDCT, i] * cJPEGWeights[c, v, u];
                  FInvDCTLutDouble[pvm, i] := NaN;
                end;
                pvsPSNRHVS:
                begin
                  FDCTLut[pvm, i] := FDCTLut[pvsDCT, i] * cPSNRWeights[c, v, u];
                  FInvDCTLutDouble[pvm, i] := FInvDCTLutDouble[pvsDCT, i] / cPSNRWeights[c, y, x];
                end
                else
                  Assert(False);
              end;

              Inc(i);
            end;
  end;

  // Snake

  for i := 0 to Sqr(cTileWidth) - 1 do
    for c := 0 to cColorCpns - 1 do
      FDCTSnake[c * Sqr(cTileWidth) + i] := cDCTSnake[i] * cColorCpns + c;
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

  procedure DoQuant(AIndex: PtrInt; AData: Pointer);
  begin
    DoQuantization(AIndex);
  end;

begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esPreparePalettes);

  DoPalettization;

  ProgressRedraw(1, 'Palettization');

  yakmo_set_num_threads(1);
  TMTPool.DoStandaloneLocalProc(@DoQuant, 0, High(FPalettes), MaxThreadCount);

  ProgressRedraw(2, 'Quantization');

  OptimizePalettes;

  ProgressRedraw(3, 'OptimizePalettes');
end;

procedure TTilingEncoder.Dither;

  procedure DoDither(AIndex: PtrInt; AData: Pointer);
  var
    Tile: PTile;
  begin
    Tile := FTiles[AIndex];

    if not Tile^.Active then
      Exit;

    DitherTile(Tile^, FPalettes[Tile^.PalIdx_Initial].MixingPlan);
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

  TMTPool.DoStandaloneLocalProc(@DoDither, 0, High(FTiles), MaxThreadCount);

  ProgressRedraw(2, 'Dither');
end;

procedure TTilingEncoder.Reduce;
var
  kfIdx: Integer;
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
  MTPool: TMTPool;
begin
  if (Length(FFrames) = 0) or (FMotionPredictRadius <= 0) then
    Exit;

  ProgressRedraw(0, '', esPredict);

  MTPool := TMTPool.Create(MaxThreadCount);
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
        Frame.DirectBlit(MTPool, FrameBuffer.GetBuffer);

        if isKFFF then
        begin
          Frame.PrepareDCTs(MTPool, DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
          Frame.Predict(MTPool, FMotionPredictRadius, 0, DCTBuffer, FrameBuffer)
        end
        else
        begin
          for iBuf := 1 to Min(FMotionPredictMaxBufferedFrames, frmRelIdx) do
            Frame.Predict(MTPool, FMotionPredictRadius, iBuf, DCTBuffer, FrameBuffer);
          Frame.PrepareDCTs(MTPool, DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
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
    MTPool.Free;
  end;
end;

procedure TTilingEncoder.Reconstruct;
var
  frmIdx, frmRelIdx, iBuf: Integer;
  isKFFF: Boolean;
  Frame: TFrame;
  FrameBuffer: TFrameBuffer;
  DCTBuffer: TDCTBuffer;
  MTPool: TMTPool;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esReconstruct);

  FKeyFramesLeft := Length(FKeyFrames);

  PrepareReconstruct;
  ProgressRedraw(1, 'PrepareReconstruct', esReconstruct);

  MTPool := TMTPool.Create(MaxThreadCount);
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
            Frame.Predict(MTPool, FMotionPredictRadius, iBuf, DCTBuffer, FrameBuffer);

        Frame.Reconstruct(MTPool, FMotionPredictRadius, FrameBuffer);
        Frame.PrepareDCTs(MTPool, DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
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
    MTPool.Free;
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

  ProgressRedraw(cEncoderStepLen[esLoad], 'ReloadGTM');
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

class function TTilingEncoder.ColorCompare(r1, g1, b1, r2, g2, b2: Double): Double;
var
  luma1, luma2, lumadiff, diffR, diffG, diffB: Double;
begin
  luma1 := (r1 * cRedMul + g1 * cGreenMul + b1 * cBlueMul) * (1.0 / (cLumaDiv * 255.0));
  luma2 := (r2 * cRedMul + g2 * cGreenMul + b2 * cBlueMul) *  (1.0 / (cLumaDiv * 255.0));
  lumadiff := luma1 - luma2;
  diffR := r1 - r2;
  diffG := g1 - g2;
  diffB := b1 - b2;
  Result := (diffR * diffR) * (cRedMul / 255.0 * 0.75);
  Result += (diffG * diffG) * (cGreenMul / 255.0 * 0.75);
  Result += (diffB * diffB) * (cBlueMul / 255.0 * 0.75);
  Result += lumadiff * lumadiff;
end;

function TTilingEncoder.DeviseBestMixingPlanYliluoma(var Plan: TMixingPlan; col: Integer; var List: array of Byte): Integer;
var
  r, g, b: Integer;
  t, index, max_test_count, plan_count, chosen_amount, chosen: Integer;
  least_penalty, penalty: Double;
  so_far, sum, add: array[0..3] of Integer;
begin
  FromRGB(col, r, g, b);

  plan_count := 0;
  so_far[0] := 0; so_far[1] := 0; so_far[2] := 0; so_far[3] := 0;

  while plan_count < Plan.Y2MixedColors do
  begin
    max_test_count := IfThen(plan_count = 0, 1, plan_count);

    chosen_amount := 1;
    chosen := 0;

    least_penalty := Infinity;

    for index := 0 to High(Plan.Y2Palette) do
    begin
      sum[0] := so_far[0]; sum[1] := so_far[1]; sum[2] := so_far[2]; sum[3] := so_far[3];
      add[0] := Plan.Y2Palette[index][0]; add[1] := Plan.Y2Palette[index][1]; add[2] := Plan.Y2Palette[index][2]; add[3] := Plan.Y2Palette[index][3];

      for t := plan_count + 1 to plan_count + max_test_count do
      begin
        sum[0] += add[0];
        sum[1] += add[1];
        sum[2] += add[2];

        add[0] += 1;
        add[1] += 1;
        add[2] += 1;

        penalty := ColorCompare(r, g, b, sum[0] / t, sum[1] / t, sum[2] / t);

        if penalty < least_penalty then
        begin
          least_penalty := penalty;
          chosen := index;
          chosen_amount := t - plan_count;
        end;
      end;
    end;

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
end;

procedure TTilingEncoder.DeviseBestMixingPlanThomasKnoll(var Plan: TMixingPlan; col: Integer; var List: array of Byte);
const
  CErrorMultiplier = 0.09;
var
  index, chosen, c: Integer;
  src : array[0..2] of Byte;
  s, t, e: array[0..2] of Double;
  least_penalty, penalty: Double;
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
    t[0] := EnsureRange(s[0] + e[0] * CErrorMultiplier, 0.0, 255.0);
    t[1] := EnsureRange(s[1] + e[1] * CErrorMultiplier, 0.0, 255.0);
    t[2] := EnsureRange(s[2] + e[2] * CErrorMultiplier, 0.0, 255.0);


    least_penalty := Infinity;
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

procedure TTilingEncoder.SetReconstructReuseMultiplier(AValue: Double);
begin
  if FReconstructReuseMultiplier = AValue then Exit;
  FReconstructReuseMultiplier := Max(1.0, AValue);
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
 if FMaxThreadCount = AValue then Exit;
 FMaxThreadCount := max(1, AValue);
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

procedure TTilingEncoder.SetRenderUseGamma(AValue: Boolean);
begin
  if FRenderUseGamma = AValue then Exit;
  FRenderUseGamma := AValue;
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
  FRenderOutputDirty := FRenderOutputDirty or not InRange(AValue, FRenderOuptutFrameIndex, FRenderOuptutFrameIndex + 1);
end;

procedure TTilingEncoder.SetRenderGammaValue(AValue: Double);
begin
  if FGamma[1] = AValue then Exit;
  FGamma[1] := Max(0.0, AValue);
  InitLuts;
end;

procedure TTilingEncoder.SetRenderMirrored(AValue: Boolean);
begin
  if FRenderMirrored = AValue then Exit;
  FRenderMirrored := AValue;
  FRenderOutputDirty := True;
end;

procedure TTilingEncoder.SetRenderOutputDithered(AValue: Boolean);
begin
  if FRenderOutputDithered = AValue then Exit;
  FRenderOutputDithered := AValue;
  FRenderOutputDirty := True;
end;

procedure TTilingEncoder.SetRenderPage(AValue: TRenderPage);
begin
  if FRenderPage = AValue then Exit;
  FRenderPage := AValue;
  FRenderOutputDirty := FRenderOutputDirty or ((AValue = rpOutput) and not InRange(FRenderFrameIndex, FRenderOuptutFrameIndex, FRenderOuptutFrameIndex + 1));
end;

procedure TTilingEncoder.SetRenderPaletteIndex(AValue: Integer);
begin
  if FRenderPaletteIndex = AValue then Exit;
  FRenderPaletteIndex := EnsureRange(AValue, -1, FPaletteCount - 1);
  FRenderOutputDirty := True;
end;

procedure TTilingEncoder.SetRenderPredicted(AValue: Boolean);
begin
  if FRenderPredicted = AValue then Exit;
  FRenderPredicted := AValue;
  FRenderOutputDirty := AValue;
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

procedure TTilingEncoder.ConvertToCpnPixels(const ATile: TTile; FromPal, UseLAB, VMirror, HMirror: Boolean; const APalette: TIntegerDynArray; out ACpnPixels: TCpnPixels);

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
      RGBToYUV(r, g, b, yy, uu, vv, cDCTScale);
    end;

    ACpnPixels[0, y, x] := yy;
    ACpnPixels[1, y, x] := uu;
    ACpnPixels[2, y, x] := vv;
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

        ToCpn(APalette[ATile.PalPixels[yy, xx]], x, y);
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

        ToCpn(ATile.RGBPixels[yy, xx], x, y);
      end;
  end;
end;

procedure TTilingEncoder.ComputeCpnPixelsPsyVisFeatures(const ACpnPixel: TCpnPixels; Mode: TPsyVisMode; ColorCpns: Integer; ADCT: PDCTScalar);
var
  u, v, cpn: Integer;
  z: Double;
  pLut: PSingle;
  pDCT: PSmallInt;
  pSnake: PInteger;
begin
  pDCT := @ADCT[0];
  pLut := @FDCTLut[Mode, 0];
  pSnake := @FDCTSnake[0];
  for cpn := 0 to ColorCpns - 1 do
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
  		  z := DCTInner_asm(@ACpnPixel[cpn, 0, 0], pLut);
        pDCT[pSnake^] := Round(z);
        Inc(pLut, Sqr(cTileWidth));
        Inc(pSnake);
      end;
end;

procedure TTilingEncoder.ComputeTilePsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; FromPal, UseLAB, VMirror,
  HMirror: Boolean; ColorCpns: Integer; const APalette: TIntegerDynArray; ADCT: PDouble);
var
  i: Integer;
  LocalCpnPixels: TCpnPixels;
  LocalDCT: TDCT;
begin
  ConvertToCpnPixels(ATile, FromPal, UseLAB, VMirror, HMirror, APalette, LocalCpnPixels);
  ComputeCpnPixelsPsyVisFeatures(LocalCpnPixels, Mode, ColorCpns, @LocalDCT[0]);
  for i := 0 to cTileDCTSize - 1 do
    ADCT[i] := LocalDCT[i];
end;

procedure TTilingEncoder.ComputeInvTilePsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; UseLAB: Boolean; ColorCpns: Integer;
 var ATile: TTile);
var
  i, u, v, x, y, cpn: Integer;
  CpnPixels: TCpnPixelsDouble;
  pCpn, pLut, pDCT: PDouble;
  pSnake: PInteger;
  LocalDCT: array[0..cTileDCTSize - 1] of Double;

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
      Result := YUVToRGB(yy, uu, vv, cDCTScale);
  end;

begin
  Assert(not (Mode in [pvsSpeDCT, pvsWeightedSpeDCT]), 'Special DCT is non-inversible');

  pDCT := @LocalDCT[0];
  pSnake := @FDCTSnake[0];
  for cpn := 0 to ColorCpns - 1 do
  begin
    i := 0;
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
        pDCT^ := DCT[pSnake^];
        Inc(pDCT);
        Inc(pSnake);
        Inc(i);
      end;
  end;

  pLut := @FInvDCTLutDouble[Mode, 0];
  for cpn := 0 to ColorCpns - 1 do
  begin
    pCpn := @CpnPixels[cpn, 0, 0];
    for y := 0 to cTileWidth - 1 do
      for x := 0 to cTileWidth - 1 do
      begin
        pCpn^ := specialize DCTInner<PDouble>(@LocalDCT[cpn * sqr(cTileWidth)], pLut, 1);
        Inc(pCpn);
        Inc(pLut, Sqr(cTileWidth));
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

  SetLength(FPalettes, 0);

  FreeAndNil(FRenderFrameBuffer);

  TTile.Array1DDispose(FTiles);
end;

procedure TTilingEncoder.RenderFrame(AFrameIndex: Integer; APage: TRenderPage);
const
  CDrawPredictBaseLuma = $ff;

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
      if Frame.Index <> FRenderOuptutFrameIndex then
        FRenderFrameBuffer.AdvanceFrame;

      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMI := @Frame.TileMap[sy, sx];

          if TMI^.IsPredicted and FRenderPredicted then
          begin
            if TMI^.IsWeighted then
              TempTile^.WeightRGBPixels(
                FRenderFrameBuffer.GetBuffer(-TMI^.Attrs.WeightBackBufferOffset),
                sy shl cTileWidthBits, sx shl cTileWidthBits,
                TMI^.Attrs.Weight)
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
                if not InRange(TMI^.PalIdx, 0, High(FPalettes)) then
                begin
                  DrawDummyTile(FRenderFrameBuffer.GetBuffer, sy, sx);
                  Continue;
                end;
                pal := FPalettes[TMI^.PalIdx].PaletteRGB;
              end
              else
              begin
                if FRenderPaletteIndex <> TMI^.PalIdx then
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
              if TMI^.IsSmoothed then
              begin
                canvas.Brush.Color := clWhite;
                canvas.FrameRect(
                  (sx shl cTileWidthBits) - 3 + off, (sy shl cTileWidthBits) - 3 + off,
                  (sx shl cTileWidthBits) + 3 + off, (sy shl cTileWidthBits) + 3 + off);
              end
              else if TMI^.IsWeighted then
              begin
                siz := 0;
                col := CDrawPredictBaseLuma - (Abs(TMI^.Attrs.Weight) shr 2);
                col := ToRGB(col, $ff, col);

                canvas.Brush.Color := col;
                canvas.FillRect(
                  (sx shl cTileWidthBits) - 2 + off, (sy shl cTileWidthBits) - 2 + off,
                  (sx shl cTileWidthBits) + 2 + off, (sy shl cTileWidthBits) + 2 + off);
              end
              else
              begin
                siz := Abs(TMI^.Attrs.MotionX) + Abs(TMI^.Attrs.MotionY);
                col := Max(0, CDrawPredictBaseLuma - siz);

                if TMI^.Attrs.MotionBackBufferOffset > 1 then
                  col := ToRGB(col, col, $ff)
                else
                  col := ToRGB($ff, col, col);

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

      FRenderOutputDirty := False;
      FRenderOuptutFrameIndex := Frame.Index;
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
                pal := FPalettes[IfThen(FRenderPaletteIndex < 0, Max(0, tilePtr^.PalIdx_Initial), FRenderPaletteIndex)].PaletteRGB;

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
    TTile.Dispose(TempTile);
  end;
end;

procedure TTilingEncoder.Render;
var
  frmIdx: Integer;
begin
  if not FRenderOutputDirty or (FRenderPage <> rpOutput) or not Assigned(FFrames) then
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

    ini.WriteFloat('Reconstruct', 'ReconstructReuseMultiplier', ReconstructReuseMultiplier);

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

    ReconstructReuseMultiplier := ini.ReadFloat('Reconstruct', 'ReconstructReuseMultiplier', ReconstructReuseMultiplier);

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

  GlobalTilingUseTargetPSNR := False;
  GlobalTilingTargetPSNR := 30.0;
  GlobalTilingQualityBasedTileCount := 7.0;
  GlobalTilingTileCount := 0; // after GlobalTilingQualityBasedTileCount because has priority

  DitheringMode := pvsWeightedSpeDCT;
  DitheringUseThomasKnoll := True;
  DitheringYliluoma2MixedColors := 4;

  ReconstructReuseMultiplier := 3.0;

  ShotTransMaxSecondsPerKF := 15.0;  // maximum seconds between keyframes
  ShotTransMinSecondsPerKF := 1.0;  // minimum seconds between keyframes
  ShotTransCorrelLoThres := 0.9;   // interframe pearson correlation low limit
end;

procedure TTilingEncoder.Test;
var
  TestVal: UInt64;

  procedure DoTest(Index: PtrInt; Data: Pointer);
  begin
    Assert(InRange(Index, 42, 1337));
    Assert(Assigned(Data));
    Assert(TestVal = CRandomSeed);
  end;

var
  i, j, rng: Integer;
  rr, gg, bb: Byte;
  l, a, b, y, u, v: TFloat;
  DCT: array [0..cTileDCTSize-1] of Double;
  T, T2: PTile;
  pool: TMTPool;
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

    assert(SameValue(i, PSNRToEuclidean(EuclideanToPSNR(i)), PSNRToEuclidean(cBestPSNR - cPSNRPrecision)), 'EuclideanToPSNR/PSNRToEuclidean mismatch');
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

  ComputeTilePsyVisFeatures(T^, pvsPSNRHVS, False, False, False, False, cColorCpns, nil, @DCT[0]);
  ComputeInvTilePsyVisFeatures(@DCT[0], pvsPSNRHVS, False, cColorCpns, T2^);

  Assert(CompareMem(T^.GetRGBPixelsPtr, T2^.GetRGBPixelsPtr, SizeOf(TRGBPixels)), 'PSNRHVS/InvPSNRHVS mismatch');

  TTile.Dispose(T);
  TTile.Dispose(T2);

  for i := 0 to 1 do
  begin
    pool := TMTPool.Create(i * 42 + 1);
    try
      TestVal := CRandomSeed;
      pool.DoLocalProc(@DoTest, 42, 1337, Pointer(True));
    finally
      pool.Free;
    end;
  end;
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
  GoldenRatioSearch(@GRPSNR, 0.0, cBestPSNR, ATileCount, cPSNRPrecision, 0.5, @GRData);
  Result := GRData.UnpredictedTileCount;
end;

function TTilingEncoder.SolveAvgPSNR(AAvgPSNR: Double): Integer;
var
  GRData: TGRPSNRData;
begin
  GRData.OnTileCount := False;
  GRData.MeanPSNR := 0;
  GRData.UnpredictedTileCount := 0;
  GoldenRatioSearch(@GRPSNR, 0.0, cBestPSNR, AAvgPSNR, cPSNRPrecision, 0.01, @GRData);
  Result := GRData.UnpredictedTileCount;
end;

procedure TTilingEncoder.TransferTiles;
var
  doneFrameCount: Integer;
  newTIdx: Integer;

  procedure DoTransfer(AIndex: PtrInt; AData: Pointer);
  var
    tIdx, sx, sy, irBaseTIdx: Integer;
    Frame: TFrame;
    Tile: PTile;
    TMI: PTileMapItem;
  begin
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

  TMTPool.DoStandaloneLocalProc(@DoTransfer, 0, High(FFrames), MaxThreadCount);

  Assert(newTIdx = tileCount);
end;

procedure TTilingEncoder.DoPalettization;
var
  YakmoDataset: TDoubleDynArray2;
  YakmoWeights: TCardinalDynArray;

  procedure DoDCT(AIndex: PtrInt; AData: Pointer);
  var
    Tile: PTile;
  begin
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

    TMTPool.DoStandaloneLocalProc(@DoDCT, 0, DSLen - 1, MaxThreadCount);

    if FPaletteCount > 1 then
    begin
      Yakmo := yakmo_create(FPaletteCount, 1, cYakmoMaxIterations, 1, 0, 0, 1);
      try
        yakmo_set_num_threads(MaxThreadCount);

        yakmo_load_train_data_weighted(Yakmo, Length(YakmoDataset), cTileDCTSize, PPDouble(@YakmoDataset[0]), @YakmoWeights[0]);
        SetLength(YakmoDataset, 0); // free up some memory
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
  begin
    FPalettes[palIdx].UseCount := 0;
    FPalettes[palIdx].PalIdx_Initial := palIdx;
  end;

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

    Tile^.PalIdx_Initial := PalIdxLUT[YakmoClusters[tIdx]];
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

  procedure DoPal(AIndex: PtrInt; AData: Pointer);
  var
    Data: TMinimizeOPData;
    x: TDoubleDynArray;
    palIdx, colIdx: Integer;
    iw: PIndexWeight;
    r, g, b: Byte;
  begin
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
  MTPool: TMTPool;
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

  MTPool := TMTPool.Create(MaxThreadCount);
  try
    repeat
      prevFSum := max(fSum, prevFSum);
      Inc(iteration);

      MTPool.DoLocalProc(@DoPal, 0, FPaletteCount - 1);

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
  finally
    MTPool.Free;
  end;

  WriteLn('OptimizePalettes: ', iteration, ' iterations');
end;

procedure TTilingEncoder.QuantizeUsingYakmo(APalIdx, AColorCount: Integer);
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
    Inc(DSLen, sqr(cTileWidth) * Ord(FTiles[tIdx]^.PalIdx_Initial = APalIdx));

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

    if Tile^.Active and (Tile^.PalIdx_Initial = APalIdx) then
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
      CMItem^.R := GammaUncorrect(0, Centroids[i, 0]);
      CMItem^.G := GammaUncorrect(0, Centroids[i, 1]);
      CMItem^.B := GammaUncorrect(0, Centroids[i, 2]);
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

    QuantizeUsingYakmo(APalIdx, FPaletteSize);

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
  dsIterator, reusableTileCount: Integer;

  procedure DoPsyV(AIndex: PtrInt; AData: Pointer);
  var
    palIdx, dsIdx: Integer;
    T: PTile;
    CpnPixels: TCpnPixels;
  begin
    T := Tiles[AIndex];
    Assert(T^.Active);

    for palIdx := 0 to FPaletteCount - 1 do
    begin
      if (palIdx = T^.PalIdx_Initial) or (AIndex < reusableTileCount) then
      begin
        ConvertToCpnPixels(T^, True, False, False, False, FPalettes[palIdx].PaletteRGB, CpnPixels);

        dsIdx := InterLockedIncrement(dsIterator);

        ComputeCpnPixelsPsyVisFeatures(CpnPixels, pvsPSNRHVS, cColorCpns, DS^.DatasetPtrs[dsIdx]);
        DS^.DSToTilePalIdx[dsIdx].TileIdx := AIndex;
        DS^.DSToTilePalIdx[dsIdx].PalIdx := palIdx;
      end;
    end;
  end;

var
  tIdx, kfIdx, dsIdx, uc: Integer;
  pDS: PDCTScalar;
begin
  // Compute psycho visual model for all tiles in their inital palettes, and some tiles in all palettes

  uc := -1;
  reusableTileCount := Min(Round((FReconstructReuseMultiplier - 1.0) * Length(FTiles) / FPaletteCount), Length(FTiles));
  if reusableTileCount > 0 then
  begin
    if reusableTileCount < Length(FTiles) then
      uc := FTiles[reusableTileCount]^.UseCount;
    for tIdx := reusableTileCount - 1 downto 0 do
      if FTiles[tIdx]^.UseCount <> uc then
      begin
        reusableTileCount := tIdx + 1;
        Break;
      end;
    uc := FTiles[reusableTileCount - 1]^.UseCount;
  end;

  DS := New(PTilingDataset);
  FillChar(DS^, SizeOf(TTilingDataset), 0);

  DS^.KNNSize := Length(FTiles) + reusableTileCount * Max(0, FPaletteCount - 1);
  SetLength(DS^.Dataset, DS^.KNNSize * cTileDCTSize);
  SetLength(DS^.DatasetPtrs, DS^.KNNSize);
  SetLength(DS^.DSToTilePalIdx, DS^.KNNSize);

  pDS := @DS^.Dataset[0];
  for dsIdx := 0 to DS^.KNNSize - 1 do
  begin
    DS^.DatasetPtrs[dsIdx] := pDS;
    Inc(pDS, cTileDCTSize);
  end;

  dsIterator := -1;
  TMTPool.DoStandaloneLocalProc(@DoPsyV, 0, High(FTiles), MaxThreadCount);
  Assert(dsIterator + 1 = DS^.KNNSize);

  WriteLn('Dataset size: ', DS^.KNNSize:8, ', (', DS^.KNNSize / Length(FTiles):4:3, 'x), lowest reusable UseCount: ', uc:8);

  // Build KNN

  DS^.ANN := ann_kdtree_short_create(@DS^.DatasetPtrs[0], DS^.KNNSize, cTileDCTSize, 32, ANN_KD_STD);

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

  QuickSort(Tiles[0], 0, High(Tiles), SizeOf(PTile), @CompareTileUseCountRev, Pointer(PtrInt(OnRGBPixels)));

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
  sameIdx: TIntegerDynArray;

  procedure DoOneMerge;
  var
    j: Int64;
  begin
    if sortIdx - firstSameIdx >= 2 then
    begin
      for j := firstSameIdx to sortIdx - 1 do
        sameIdx[j - firstSameIdx] := PTile(sortList[j])^.TmpIndex;
      MergeTiles(sameIdx, sortIdx - firstSameIdx, sameIdx[0]);
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

procedure TTilingEncoder.MergeTiles(const TileIndexes: TIntegerDynArray; TileCount: Integer; BestTileIdx: Int64);
var
  i: Integer;
  tidx: Integer;
begin
  for i := 0 to TileCount - 1 do
  begin
    tidx := TileIndexes[i];

    if tidx = BestTileIdx then
      Continue;

    Inc(FTiles[BestTileIdx]^.UseCount, FTiles[tidx]^.UseCount);

    FTiles[tidx]^.Active := False;
    FTiles[tidx]^.UseCount := 0;
    FTiles[tidx]^.MergeIndex := BestTileIdx;

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
  frmIdx, kfIdx, loadedFrmCount: Integer;
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
  begin
    KFStream.ReadAnsiString;
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

    tileCount := ReadDWord; // maximum tile count
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

  procedure SetTMI(tileIdx, palIdx: Integer; attrs: Integer; var TMI: TTileMapItem);
  begin
    TMI.TileIdx := tileIdx;
    TMI.PalIdx := palIdx;
    TMI.HMirror := attrs and 1 <> 0;
    TMI.VMirror := attrs and 2 <> 0;

    TMI.IsPredicted := False;
    TMI.IsWeighted := False;
  end;

  function NextFrame(KF: TKeyFrame): TFrame;
  begin
    Inc(frmIdx);
    Result := TFrame.Create(Self, frmIdx);
    Result.PKeyFrame := kf;

    Result.FrameTiles := TTile.Array1DNew(FTileMapSize, True, False);
    Result.CompressFrameTiles;

    if frmIdx >= Length(FFrames) then
      SetLength(FFrames, frmIdx + 1);
    FFrames[frmIdx] := Result;

    Write(frmIdx + 1:8, ' / ', Length(FFrames):8, #13);
  end;

  function NextKeyFrame: TKeyFrame;
  begin
    Inc(kfIdx);
    Result := TKeyFrame.Create(Self, kfIdx, loadedFrmCount, -1);

    if kfIdx >= Length(FKeyFrames) then
      SetLength(FKeyFrames, kfIdx + 1);
    FKeyFrames[kfIdx] := Result;
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
      frm.TileMap[sy, sx].Attrs.MotionBackBufferOffset := 1;
    end;
    tmPos += SkipCount;
  end;

var
  Header: TGTMHeader;
  Command, prevCommand: TGTMCommand;
  CommandData: Word;
  tmPos: Integer;
  tileIdx: Cardinal;
  palIdx: Word;
  frm: TFrame;
  kf: TKeyFrame;
  TMI: PTileMapItem;
begin
  FillChar(Header, SizeOf(Header), 0);

  AStream.ReadBuffer(Header, SizeOf(Header.FourCC));
  AStream.Seek(0, soBeginning);

  if Header.FourCC = 'GTMv' then
  begin
    AStream.ReadBuffer(Header, SizeOf(Header));
    AStream.Seek(Header.WholeHeaderSize, soBeginning);

    SetLength(FKeyFrames, Header.KFCount);
    SetLength(FFrames, Header.FrameCount);
  end;

  ClearAll(True);

  kf := nil;
  frm := nil;
  frmIdx := -1;
  kfIdx := -1;
  loadedFrmCount := 0;
  KFStream := TMemoryStream.Create;
  try
    repeat
      KFStream.Clear;
      LZDecompress(AStream, KFStream);
      KFStream.Seek(0,soBeginning);

      kf := NextKeyFrame;

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
          gtSkipBlock:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            SkipBlock(frm, CommandData + 1, tmPos);
          end;
          gtShortTileIdxShortPalIdx, gtLongTileIdxShortPalIdx, gtLongTileIdxLongPalIdx:
          begin
            if Command in [gtLongTileIdxLongPalIdx] then
              palIdx := ReadWord
            else
              palIdx := (CommandData shr 2) and ((1 shl (CGTMCommandBits - 2)) - 1);

            if Command in [gtShortTileIdxShortPalIdx] then
              tileIdx := ReadWord
            else
              tileIdx := ReadDWord;

            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            tileIdx := rawTileIdxToTileIdx[tileIdx];

            SetTMI(tileIdx, palIdx, CommandData, frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth]);
            Inc(tmPos);
          end;
          gtPredictedTileShortOffsets:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];

            TMI^.Attrs.MotionX := (CommandData and 31) - (CommandData and 32);
            TMI^.Attrs.MotionY := ((CommandData shr 6) and 31) - ((CommandData shr 6) and 32);
            TMI^.Attrs.MotionBackBufferOffset := 1;
            TMI^.IsPredicted := True;

            Inc(tmPos);
          end;
          gtPredictedTileLongOffsets:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];

            TMI^.Attrs.MotionX := ShortInt(ReadByte);
            TMI^.Attrs.MotionY := ShortInt(ReadByte);
            TMI^.Attrs.MotionBackBufferOffset := (CommandData and 3) + 1;
            TMI^.IsPredicted := True;

            Inc(tmPos);
          end;
          gtIntraTile:
          begin
            palIdx := ReadWord;

            tileIdx := Length(FTiles);
            TTile.Array1DRealloc(FTiles, tileIdx + 1);

            KFStream.Read(FTiles[tileIdx]^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
            FTiles[tileIdx]^.Active := True;

            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            SetTMI(tileIdx, palIdx, CommandData, frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth]);
            Inc(tmPos);
          end;
          gtPredictedWeight:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];

            TMI^.Attrs.Weight := ((CommandData shr 2) and CGTMBlendWeightMax) - ((CommandData shr 2) and -CGTMBlendWeightMin);
            TMI^.Attrs.WeightBackBufferOffset := (CommandData and 3) + 1;
            TMI^.IsPredicted := True;
            TMI^.IsWeighted := True;

            Inc(tmPos);
          end;

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

  procedure DoTMI(const TMI: TTileMapItem);
  var
    tileIdx, finalTileIdx: Cardinal;
    palIdx, attrs: Word;
    isLongTile, isLongPal, isLongOffsets: Boolean;
  begin
    if TMI.IsPredicted then
    begin
      if TMI.IsWeighted then
      begin
        DoCmd(gtPredictedWeight, ((PWORD(@TMI.Attrs.Weight)^ and ((1 shl CGTMBlendWeightBaseShift) - 1)) shl 2) or (TMI.Attrs.WeightBackBufferOffset - 1));
      end
      else
      begin
        isLongOffsets := not InRange(TMI.Attrs.MotionX, -32, 31) or not InRange(TMI.Attrs.MotionY, -32, 31) or (TMI.Attrs.MotionBackBufferOffset > 1);

        if isLongOffsets then
        begin
          DoCmd(gtPredictedTileLongOffsets, TMI.Attrs.MotionBackBufferOffset - 1);
          DoByte(PByte(@TMI.Attrs.MotionX)^);
          DoByte(PByte(@TMI.Attrs.MotionY)^);
        end
        else
        begin
          attrs := (PByte(@TMI.Attrs.MotionX)^ and 63) or ((PByte(@TMI.Attrs.MotionY)^ and 63) shl 6);

          DoCmd(gtPredictedTileShortOffsets, attrs);
        end;
      end;
    end
    else
    begin
      tileIdx := Max(0, TMI.TileIdx);
      palIdx := Max(0, TMI.PalIdx);
      finalTileIdx := Max(0, FTiles[tileIdx]^.TmpIndex);

      isLongTile := finalTileIdx > High(Word);
      isLongPal := palIdx >= (1 shl (CGTMCommandBits - 2));

      attrs := (Ord(TMI.VMirror) shl 1) or Ord(TMI.HMirror);

      if not isLongTile and not isLongPal then
      begin
        DoCmd(gtShortTileIdxShortPalIdx, attrs or (palIdx shl 2));
        DoWord(finalTileIdx);
      end
      else if not isLongPal then
      begin
        DoCmd(gtLongTileIdxShortPalIdx, attrs or (palIdx shl 2));
        DoDWord(finalTileIdx);
      end
      else
      begin
        DoCmd(gtLongTileIdxLongPalIdx, attrs);
        DoWord(palIdx);
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
      DoCmd(gtLoadPalette, 0);
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

  procedure WriteTiles(const AList: TIntegerDynArray; AStart: Integer = 0);
  var
    tlIdx: Integer;
  begin
    if Length(AList) > 0 then
    begin
      DoCmd(gtTileSet, FPaletteSize);
      DoDWord(AStart); // start tile
      DoDWord(AStart + High(AList)); // end tile

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
      maxTileCount := max(maxTileCount, Length(globalTiles) + Length(perKfTiles[kfIdx]));

    DoCmd(gtSetDimensions, 0);
    DoWord(FTileMapWidth); // frame tilemap width
    DoWord(FTileMapHeight); // frame tilemap height
    DoDWord(round(1000*1000*1000 / FFramesPerSecond)); // frame length in nanoseconds
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
  Header.EncoderVersion := 5; // 2 -> fixed blending extents; 3 -> *AddlBlendTileIdx; 4 -> PredictMotion; 5 -> Weight
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
    WriteTiles(globalTiles);

    bpsAcc := 0;
    LastKF := 0;
    for kfIdx := 0 to High(FKeyFrames) do
    begin
      KeyFrame := FKeyFrames[kfIdx];

      WriteTiles(perKfTiles[kfIdx], Length(globalTiles));

      // paletes must always be written after at least one tileset
      if kfIdx = 0 then
        WritePalettes;

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

              DoCmd(gtSkipBlock, BlkSkipCount - 1);
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

  FRenderOuptutFrameIndex := -1;
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
begin
  case AStep of
    esAll:
      RunRange(esLoad, esSave);
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

