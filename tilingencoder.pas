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
  IntfGraphics, FPimage, FPCanvas, FPWritePNG, GraphType, fgl, MTProcs, extern, tbbmalloc, bufstream, utils, kmodes;
type
  TEncoderStep = (esAll = -1, esLoad = 0, esPredictMotion, esReduce, esReconstruct, esReindex, esSave);
  TKeyFrameReason = (kfrNone, kfrManual, kfrLength, kfrDecorrelation, kfrEuclidean);
  TRenderPage = (rpNone, rpInput, rpOutput, rpTilesPalette);
  TPsyVisMode = (pvsDCT, pvsWeightedDCT, pvsWavelets, pvsSpeDCT, pvsWeightedSpeDCT);

const
  cEncoderStepLen: array[TEncoderStep] of Integer = ({esAll} -1, {esLoad} 5, {esPredictMotion} 1, {esReduce} 4, {esReconstruct} 2, {esReindex} 3, {esSave} 1);

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
  end;

  TGTMKeyFrameInfo = packed record
    FourCC: array[0..3] of AnsiChar; // ASCII "GTMk"
    RIFFSize: Cardinal;
    KFIndex: Cardinal;
    FrameIndex: Cardinal;
    RawSize: Cardinal;
    CompressedSize: Cardinal;
    TimeCodeMillisecond: Cardinal;
  end;

  // Commands Description:
  // =====================
  //
  // PredictedTileShortOffsets:        data -> none; commandBits -> y offset (6 bits); x offset (6 bits)
  // PredictedTileLongOffsets:         data -> x offset (8 bits); y offset (8 bits); commandBits -> none
  // ShortTileIdxShortPalIdx:          data -> tile index (16 bits); commandBits -> palette index (10 bits); V mirror (1 bit); H mirror (1 bit)
  // LongTileIdxShortPalIdx:           data -> tile index (32 bits); commandBits -> palette index (10 bits); V mirror (1 bit); H mirror (1 bit)
  // LongTileIdxLongPalIdx:            data -> palette index (16 bits); tile index (32 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // IntraTile:                        data -> palette index (16 bits); indexes per pixel (64 bytes); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // SkipBlock:                        data -> none; commandBits -> skip count - 1 (12 bits)
  // Blend:                            data -> none; commandBits -> frame -2 weight (6 bits); frame -1 weight (6 bits)
  //
  // (insert new commands here...)
  //
  // FrameEnd:                         data -> none; commandBits -> none (11 bits); keyframe end (1 bit)
  // LoadPalette:                      data -> palette index (16 bits); { RGBA bytes (32bits) } * indexes count; commandBits -> palette format (0: RGBA32) (12 bits)
  // TileSet:                          data -> start tile (32 bits); end tile (32 bits); { indexes per pixel (64 bytes) } * count; commandBits -> indexes count per palette
  // SetDimensions:                    data -> width in tiles (16 bits); height in tiles (16 bits); frame length in nanoseconds (32 bits) (2^32-1: still frame); tile count (32 bits); commandBits -> none
  // ExtendedCommand:                  data -> following bytes count (32 bits); custom commands, proprietary extensions, ...; commandBits -> extended command index (12 bits)

  TGTMCommand = (
    gtPredictedTileShortOffsets = 0,
    gtPredictedTileLongOffsets = 1,
    gtShortTileIdx = 2,
    gtLongTileIdx = 3,
    gtSkipBlock = 4,
    gtBlend = 5,

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
    Flags: set of (tfActive, tfHMirror_Initial, tfVMirror_Initial);
    RGBPixels: TRGBPixels;
  end;

  { TTileHelper }

  TTileHelper = record helper for TTile
  private
    function GetActive: Boolean;
    function GetHMirror_Initial: Boolean;
    function GetVMirror_Initial: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure SetHMirror_Initial(AValue: Boolean);
    procedure SetVMirror_Initial(AValue: Boolean);
  public

    class function Array1DNew(x: Integer): PTileDynArray; static;
    class procedure Array1DDispose(var AArray: PTileDynArray); static;
    class procedure Array1DRealloc(var AArray: PTileDynArray; ANewX: integer); static;
    class function New: PTile; static;
    class procedure Dispose(var ATile: PTile); static;
    procedure CopyFrom(const ATile: TTile);
    procedure CopyRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer); overload;
    procedure BlendRGBPixels(const AM1Buffer, AM2Buffer: TIntegerDynArray2; AY, AX: Integer; AM1Weight, AM2Weight: Byte);
    procedure BlitCpnPixels(const AFrameBuffer: TIntegerDynArray2; AColorCpn: Integer; AVMirror, AHMirror: Boolean; AY, AX: Integer);
    procedure BlitRGBPixels(const AFrameBuffer: TIntegerDynArray2; AVMirror, AHMirror: Boolean; AY, AX: Integer);
    procedure ClearRGBPixels;
    function CompareRGBPixelsTo(const ATile: TTile): Integer;

    property Active: Boolean read GetActive write SetActive;
    property HMirror_Initial: Boolean read GetHMirror_Initial write SetHMirror_Initial;
    property VMirror_Initial: Boolean read GetVMirror_Initial write SetVMirror_Initial;
  end;

  { TTileMapItem }

  TTileMapItem = packed record
    TileIdx: array[0 .. cColorCpns - 1] of Integer; // 4
    PSNR: TFloat; // 4
    Attrs: record case Boolean of // 3 * 1
      False: (MotionX, MotionY: ShortInt; MotionBackBufferOffset: Byte);
      True: (BlendWeightM1, BlendWeightM2, Dummy: Byte);
    end;
    Flags: set of (tmfHMirror, tmfVMirror, tmfPredicted, tmfBlended); // 1
  end;

{$if SizeOf(TTileMapItem) <> 20}
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
    procedure ResetTileIdx;
    procedure Reset(AKeepMirrors: Boolean);
    function IsValidTileIdx: Boolean;

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

    constructor Create(AParent: TTilingEncoder; AIndex: Integer);
    destructor Destroy; override;

    function PrepareInterFrameData: TFloatDynArray;
    procedure AsyncLoadFromImage;

    procedure CompressFrameTiles;
    procedure AcquireFrameTiles;
    procedure ReleaseFrameTiles;

    function GetUnpredictedTileCount: Integer;
    procedure ResetTileMap(AKeepMirrors: Boolean);

    procedure GetPredictExtents(ARadius, ADY, ADX: Integer; out oxmn, oxmx, oymn, oymx: Integer);

    procedure PrepareDCTs(const ADCTs: TDCTDynArray; const ABuffer: TIntegerDynArray2);
    function PredictTileBlending(ADY, ADX: Integer; ATMI: PTileMapItem; const  ADCT: TDCT; ADCTBuffer: TDCTBuffer): Integer;
    function PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Integer;
    function PredictTileIntra(ARadius, ADY, ADX: Integer; ATMI: PTileMapItem; const  ADCT: TDCT; const ADCTs: TDCTDynArray): Integer;

    // processes

    procedure LoadFromImage(AImageWidth, AImageHeight: Integer; AImage: PInteger);
    procedure Predict(ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer);
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
    ReconstructPSNRCml: Double;
    ReconstructLock: TSpinlock;

    procedure LogPSNR;

    function GetUnpredictedTileCount: Integer;

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
    FTileDS: PTilingDataset;

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
    FMotionPredictRadius: Integer;
    FMotionPredictMaxBufferedFrames: Integer;
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
    FRenderPlaying: Boolean;
    FRenderTilePage: Integer;
    FRenderFrameBuffer: TFrameBuffer;
    FOutputBitmap: TBitmap;
    FInputBitmap: TBitmap;
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
    procedure SetFrameCountSetting(AValue: Integer);
    procedure SetFramesPerSecond(AValue: Double);
    procedure SetGlobalTilingQualityBasedTileCount(AValue: Double);
    procedure SetMaxThreadCount(AValue: Integer);
    procedure SetMotionPredictRadius(AValue: Integer);
    procedure SetMotionPredictMaxBufferedFrames(AValue: Integer);
    procedure SetRenderFrameIndex(AValue: Integer);
    procedure SetRenderGammaValue(AValue: Double);
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

    procedure ConvertToCpnPixels(const ATile: TTile; VMirror, HMirror: Boolean; out ACpnPixel: TCpnPixels); inline;
    procedure ComputePsyVisFeatures(const ACpnPixels: TCpnPixels; Mode: TPsyVisMode; ColorCpn: Integer; ADCT: PDCTScalar); inline;

    procedure ComputeTileCpnPsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; VMirror, HMirror: Boolean; ColorCpn: Integer; ADCT: PDouble); inline;
    procedure ComputeInvTileCpnPsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; ColorCpn: Integer; var ATile: TTile);

    function GetTileCount(AActiveOnly: Boolean): Integer;
    function GetFrameTileCount(AFrame: TFrame): Integer;
    function GetUnpredictedTileCount: Integer;
    class function GetTileZoneSum(const ATile: TTile; x, y, w, h: Integer): Integer;
    class procedure GetTileHVMirrorHeuristics(const ATile: TTile; out AHMirror, AVMirror: Boolean);
    class procedure HMirrorTile(var ATile: TTile);
    class procedure VMirrorTile(var ATile: TTile);

    procedure InitLuts;
    procedure ClearAll(AKeepFrames: Boolean);
    procedure ReframeUI(AWidth, AHeight: Integer);
    procedure InitFrames(AFrameCount: Integer);
    procedure LoadInputVideo;
    procedure FindKeyFrames(AManualMode: Boolean);

    function GRTileCountFromPSNR(x: Double; Data: Pointer): Double;
    function SolveTileCount(ATileCount: Integer; AOnKFFirstFrame: Boolean): Integer;
    procedure TransferTiles(ATileCount: Integer; AOnKFFirstFrame: Boolean);
    function ReduceTiles(ATileCount: Integer): Integer;

    procedure PrepareReconstruct;
    procedure FinishReconstruct;

    procedure ReindexTiles;
    procedure MakeTilesUnique;
    procedure InitMergeTiles;
    procedure FinishMergeTiles;
    procedure MergeTiles(const TileIndexes: TIntegerDynArray; TileCount: Integer; BestIdx: Int64);

    procedure LoadStream(AStream: TStream);
    procedure SaveStream(AStream: TStream);

    // processes

    procedure Load;
    procedure PredictMotion;
    procedure Reduce;
    procedure Reconstruct;
    procedure Reindex;
    procedure Save;
  public
    // constructor / destructor

    constructor Create;
    destructor Destroy; override;

    // functions

    procedure Run(AStep: TEncoderStep = esAll);

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
    property MotionPredictRadius: Integer read FMotionPredictRadius write SetMotionPredictRadius;
    property MotionPredictMaxBufferedFrames: Integer read FMotionPredictMaxBufferedFrames write SetMotionPredictMaxBufferedFrames;
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
    property RenderUseGamma: Boolean read FRenderUseGamma write FRenderUseGamma;
    property RenderTilePage: Integer read FRenderTilePage write SetRenderTilePage;
    property RenderGammaValue: Double read GetRenderGammaValue write SetRenderGammaValue;
    property RenderPage: TRenderPage read FRenderPage write FRenderPage;
    property RenderTitleText: String read FRenderTitleText;
    property RenderPsychoVisualQuality: Double read FRenderPsychoVisualQuality;
    property OutputBitmap: TBitmap read FOutputBitmap;
    property InputBitmap: TBitmap read FInputBitmap;
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
  CGTMBlendWeightShift = CGTMCommandBits div CGTMBlendBufferCount;
  CGTMBlendWeightMax = (1 shl CGTMBlendWeightShift) - 1;

  function CompareTileUseCountRev(Item1, Item2, UserParameter:Pointer):Integer;
  var
    t1, t2: PTile;
  begin
    t1 := PPTile(Item1)^;
    t2 := PPTile(Item2)^;

    Result := CompareValue(t2^.UseCount, t1^.UseCount);
    if Result = 0 then
      Result := t1^.CompareRGBPixelsTo(t2^)
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

procedure TTileMapItemHelper.ResetTileIdx;
begin
  FillChar(TileIdx, SizeOf(TileIdx), Byte(-1));
end;

procedure TTileMapItemHelper.Reset(AKeepMirrors: Boolean);
begin
  ResetTileIdx;
  PSNR := Infinity;
  Attrs.MotionX := 0;
  Attrs.MotionY := 0;
  Attrs.MotionBackBufferOffset := 0;
  IsPredicted := False;
  IsBlended := False;
  if not AKeepMirrors then
    Flags := [];
end;

function TTileMapItemHelper.IsValidTileIdx: Boolean;
var
  iCpn: Integer;
begin
  Result := True;
  for iCpn := 0 to cColorCpns - 1 do
    Result := Result and (TileIdx[iCpn] >= 0);
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
  Result := IsPredicted and not IsBlended and (Attrs.MotionX = 0) and (Attrs.MotionY = 0);
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

class function TTileHelper.Array1DNew(x: Integer): PTileDynArray;
var
  i, size: Integer;
  data: PByte;
begin
  Result := nil;
  size := SizeOf(TTile) * x;
  data := AllocMem(size);

  FillByte(data^, size, 0);
  SetLength(Result, x);

  for i := 0 to x - 1 do
  begin
    Result[i] := PTile(data);
    Inc(data, SizeOf(TTile));
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
begin
  Assert(Length(AArray) > 0);

  // account for the array having been sorted
  smallest := AArray[0];
  for i := 1 to High(AArray) do
    if AArray[i] < smallest then
      smallest := AArray[i];

  prevLen := Length(AArray);

  size := SizeOf(TTile);
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
    Inc(data, size);
  end;
end;

class function TTileHelper.New: PTile;
begin
  Result := AllocMem(SizeOf(TTile));
  FillByte(Result^, SizeOf(TTile), 0);
end;

class procedure TTileHelper.Dispose(var ATile: PTile);
begin
  FreeMemAndNil(ATile);
end;

procedure TTileHelper.CopyRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer);
var
  ty: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    Move(AFrameBuffer[AY, AX], RGBPixels[ty, 0], cTileWidth * SizeOf(Integer));
    Inc(AY);
  end;
end;

procedure TTileHelper.BlendRGBPixels(const AM1Buffer, AM2Buffer: TIntegerDynArray2; AY, AX: Integer; AM1Weight,
  AM2Weight: Byte);
var
  ty, tx: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    for tx := 0 to cTileWidth - 1 do
    begin
      RGBPixels[ty, tx] := BlendRGB(AM1Buffer[AY, AX], AM2Buffer[AY, AX], AM1Weight, AM2Weight, CGTMBlendWeightShift);
      Inc(AX);
    end;
    Dec(AX, cTileWidth);
    Inc(AY);
  end;
end;

procedure TTileHelper.BlitCpnPixels(const AFrameBuffer: TIntegerDynArray2; AColorCpn: Integer; AVMirror, AHMirror: Boolean; AY, AX: Integer);
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

      AFrameBuffer[AY + ty, AX + tx] := InsertRGB(AFrameBuffer[AY + ty, AX + tx], RGBPixels[tym, txm], AColorCpn);
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

procedure TTileHelper.ClearRGBPixels;
begin
  FillDWord(RGBPixels[0, 0], sqr(cTileWidth), 0);
end;

function TTileHelper.CompareRGBPixelsTo(const ATile: TTile): Integer;
begin
  Result := CompareDWord(RGBPixels[0, 0], ATile.RGBPixels[0, 0], sqr(cTileWidth));
end;

procedure TTileHelper.CopyFrom(const ATile: TTile);
begin
  UseCount := ATile.UseCount;
  TmpIndex := ATile.TmpIndex;
  MergeIndex := ATile.MergeIndex;
  Active := ATile.Active;
  HMirror_Initial := ATile.HMirror_Initial;
  VMirror_Initial := ATile.VMirror_Initial;

  Move(ATile.RGBPixels, RGBPixels, SizeOf(TRGBPixels));
end;

{ TKeyFrame }

procedure TKeyFrame.LogPSNR;
var
  kfIdx: Integer;
  tileResd, errCml: Double;
begin
  InterLockedDecrement(ReconstructFramesLeft);
  if ReconstructFramesLeft <= 0 then
  begin
    tileResd := ReconstructPSNRCml / (Encoder.FTileMapSize * FrameCount);
    WriteLn('KF: ', StartFrame:8, ' PSNR-HVS: ', tileResd:12:6, ' (by tile)');

    InterLockedDecrement(Encoder.FKeyFramesLeft);
    if Encoder.FKeyFramesLeft <= 0 then
    begin
      errCml := 0.0;
      for kfIdx := 0 to High(Encoder.FKeyFrames) do
        errCml += Encoder.FKeyFrames[kfIdx].ReconstructPSNRCml;

      tileResd := errCml / (Encoder.FTileMapSize * Length(Encoder.FFrames));
      WriteLn('All:', Length(Encoder.FFrames):8, ' PSNR-HVS: ', tileResd:12:6, ' (by tile)');
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

function TKeyFrame.GetUnpredictedTileCount: Integer;
var
  frmIdx: Integer;
begin
  Result := 0;
  for frmIdx := StartFrame to EndFrame do
    Inc(Result, Encoder.FFrames[frmIdx].GetUnpredictedTileCount);
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

  inherited Destroy;
end;

procedure TFrame.CompressFrameTiles;
var
  CompStream: Tcompressionstream;
begin
  CompressedFrameTiles.Clear;
  CompStream := Tcompressionstream.create(Tcompressionlevel.cldefault, CompressedFrameTiles, True);
  try
    CompStream.WriteBuffer(FrameTiles[0]^, Length(TileMap) * Length(TileMap[0]) * SizeOf(TTile));
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
    FrameTiles := TTile.Array1DNew(Length(TileMap) * Length(TileMap[0]));

    CompStream := Tdecompressionstream.create(CompressedFrameTiles, True);
    try
      CompStream.ReadBuffer(FrameTiles[0]^, Length(TileMap) * Length(TileMap[0]) * SizeOf(TTile));
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

    DCTTile := TTile.New;
    try
      for x := 0 to Encoder.FScreenWidth - cTileWidth do
      begin
        DCTTile^.CopyRGBPixels(ABuffer, AIndex, x);

        Encoder.ConvertToCpnPixels(DCTTile^, False, False, CpnPixels);
        Encoder.ComputePsyVisFeatures(CpnPixels, pvsWeightedDCT, -1, ADCTs[yx]);

        Inc(yx);
      end;
    finally
      TTile.Dispose(DCTTile);
    end;
  end;

begin
  ProcThreadPool.DoParallelLocalProc(@DoDCTs, 0, Encoder.FScreenHeight - cTileWidth);
end;

function TFrame.PredictTileBlending(ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; ADCTBuffer: TDCTBuffer): Integer;
var
  i, bm1, bm2, yx, err, bestM1, bestM2: Integer;
  psnr: TFloat;
  prevDCTM1, prevDCTM2: TDCT;
begin
  Result := MaxInt;
  bestM1 := MaxInt;
  bestM2 := MaxInt;

  yx := ADY * (Encoder.FScreenWidth - cTileWidth + 1) + ADX;

  prevDCTM1 := ADCTBuffer.GetBuffer(-1)[yx];
  prevDCTM2 := ADCTBuffer.GetBuffer(-2)[yx];

  for bm2 := 0 to CGTMBlendWeightMax do
    for bm1 := 0 to CGTMBlendWeightMax do
    begin
      err := 0;
      for i := 0 to cTileDCTSize - 1 do
         err += Sqr(ADCT[i] - SarLongint(prevDCTM1[i] * bm1 + prevDCTM2[i] * bm2, CGTMBlendWeightShift));

      if err < Result then
      begin
        Result := err;
        bestM1 := bm1;
        bestM2 := bm2;
      end;
    end;

  psnr := EuclideanToPSNR(Result);

  if not ATMI^.IsPredicted or (psnr > ATMI^.PSNR) then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsBlended := True;
    ATMI^.PSNR := psnr;
    ATMI^.Attrs.BlendWeightM1 := bestM1;
    ATMI^.Attrs.BlendWeightM2 := bestM2;
  end
  else
  begin
    Result := MaxInt;
  end;
end;

function TFrame.PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Integer;
var
  oy, yx: Integer;
  state: TDCTCribbleState;
  PrevDCTPtr: PDCTScalar;
  psnr: TFloat;
begin
  Result := MaxInt;
  state.Error := MaxInt;
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

  psnr := EuclideanToPSNR(state.Error);

  if not ATMI^.IsPredicted or (psnr > ATMI^.PSNR) then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsBlended := False;
    ATMI^.PSNR := psnr;
    ATMI^.Attrs.MotionY := state.Y - ADY;
    ATMI^.Attrs.MotionX := state.X - ADX;
    ATMI^.Attrs.MotionBackBufferOffset := ABackBufferOffset;
    Result := state.Error;
  end;
end;

function TFrame.PredictTileIntra(ARadius, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray): Integer;
var
  oy, ox, oymn, oymx, oxmn, oxmx, yx, bestX, bestY: Integer;
  PSNRAcc: TFloat;
  PSNRIdx, PSNRCnt, err: Cardinal;
  PrevDCTPtr: PDCTScalar;
begin
  GetPredictExtents(ARadius, ADY, ADX, oxmn, oxmx, oymn, oymx);

  Result := MaxInt;
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
  ATMI^.PSNR := PSNRAcc / PSNRCnt;
  ATMI^.Attrs.MotionY := bestY - ADY;
  ATMI^.Attrs.MotionX := bestX - ADX;
end;

procedure TFrame.Predict(ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer);

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

    Encoder.ConvertToCpnPixels(FrameTile^, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, CurCpnPixels);
    Encoder.ComputePsyVisFeatures(CurCpnPixels, pvsWeightedDCT, -1, CurDCT);

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    if ABackBufferOffset = 0 then
    begin
      PredictTileIntra(ARadius, dy, dx, TMI, CurDCT, ADCTBuffer.GetBuffer)
    end
    else
    begin
      if ABackBufferOffset = CGTMBlendBufferCount then
        PredictTileBlending(dy, dx, TMI, CurDCT, ADCTBuffer);
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

  FrameTiles := TTile.Array1DNew(Encoder.FTileMapSize);

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
      pat := PInteger(@FrameTiles[i]^.RGBPixels[0, 0]);

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

    Encoder.GetTileHVMirrorHeuristics(Tile^, HMirror, VMirror);

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
  cPSNREpsilon = 1.0;
var
  DS: PTilingDataset;

  procedure DoXY(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    sx, sy, dx, dy, ty, tx, iCpn: Integer;
    knnErr: array[0 .. cColorCpns - 1] of Cardinal;
    knnPSNR, mpPSNR: TFloat;

    FrameTile: PTile;
    TMI: PTileMapItem;

    FrontBuf, BackBuf, M1Buf, M2Buf: TIntegerDynArray2;
    FTDCT: TDCT;
    FTCpnPixels: TCpnPixels;
  begin
    if not InRange(AIndex, 0, Encoder.FTileMapSize - 1) then
      Exit;

    DivMod(AIndex, Encoder.FTileMapWidth, sy, sx);

    TMI := @TileMap[sy, sx];

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    FrameTile := FrameTiles[AIndex];
    Encoder.ConvertToCpnPixels(FrameTile^, False, False, FTCpnPixels);
    Encoder.ComputePsyVisFeatures(FTCpnPixels, pvsWeightedDCT, -1, FTDCT);

    // redo motion prediction (account for palette)

    mpPSNR := -Infinity;
    if (Index <> PKeyFrame.StartFrame) and (ARadius >= 0) then
      mpPSNR := TMI^.PSNR;

    if CompareValue(mpPSNR, cBestPSNR, cPSNREpsilon) > LessThanValue  then
    begin
      // motion prediction has priority in case perfect (less bitrate)

      TMI^.ResetTileIdx;
      FillChar(knnErr, SizeOf(knnErr), Byte(-1));
    end
    else
    begin
      // use the KNN dataset to predict a tile with its associated palette

      FillChar(knnErr, SizeOf(knnErr), Byte(-1));
      for iCpn := 0 to cColorCpns - 1 do
      begin
        TMI^.TileIdx[iCpn] := ann_kdtree_short_search(DS^.ANN, @FTDCT[iCpn * Sqr(cTileWidth)], 0, @knnErr[iCpn]);
        if not InRange(TMI^.TileIdx[iCpn], 0, DS^.KNNSize - 1) then
        begin
          TMI^.TileIdx[iCpn] := -1;
          knnErr[iCpn] := High(Cardinal);
        end;
      end;
    end;

    // devise which is best

    if TMI^.IsValidTileIdx then
      knnPSNR := EuclideanToPSNR(knnErr[0] + knnErr[1] + knnErr[2])
    else
      knnPSNR := -Infinity;

    case CompareValue(knnPSNR, mpPSNR, cPSNREpsilon) of
      GreaterThanValue:
      begin
        // KNN is best

        TMI^.PSNR := knnPSNR;
        TMI^.IsPredicted := False;
      end;
      EqualsValue:
      begin
        // motion prediction has priority in case of ties (less bitrate)

        TMI^.PSNR := mpPSNR;
        TMI^.IsPredicted := True;
        TMI^.ResetTileIdx;
      end;
      LessThanValue:
      begin
        // motion prediction is best

        TMI^.PSNR := mpPSNR;
        TMI^.IsPredicted := True;
        TMI^.ResetTileIdx;
      end;
    end;

    FrontBuf := AFrameBuffer.GetBuffer;

    if TMI^.IsPredicted then
    begin
      // draw fb (motion predicted tile)

      if TMI^.IsBlended then
      begin
        M1Buf := AFrameBuffer.GetBuffer(-1);
        M2Buf := AFrameBuffer.GetBuffer(-2);
        for ty := 0 to cTileWidth - 1 do
        begin
          for tx := 0 to cTileWidth - 1 do
          begin
            FrontBuf[dy, dx] := BlendRGB(M1Buf[dy, dx], M2Buf[dy, dx], TMI^.Attrs.BlendWeightM1, TMI^.Attrs.BlendWeightM2, CGTMBlendWeightShift);
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

      for iCpn := 0 to cColorCpns - 1 do
        Encoder.FTiles[TMI^.TileIdx[iCpn]]^.BlitCpnPixels(FrontBuf, iCpn, TMI^.VMirror, TMI^.HMirror, dy, dx);
    end;

    SpinEnter(@PKeyFrame.ReconstructLock);
    PKeyFrame.ReconstructPSNRCml += TMI^.PSNR;
    SpinLeave(@PKeyFrame.ReconstructLock);
  end;

begin
  DS := Encoder.FTileDS;
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

procedure TTilingEncoder.Reduce;
var
  kfffTileCount, globalTileCount: Integer;
  OnKFFirstFrame: Boolean;
begin
  if Length(FFrames) = 0 then
    Exit;

  ProgressRedraw(0, '', esReduce);

  OnKFFirstFrame := True;
  if FGlobalTilingUseTargetPSNR then
  begin
    kfffTileCount := round(GRTileCountFromPSNR(FGlobalTilingTargetPSNR, @OnKFFirstFrame));
  end
  else
  begin
    // allocate theoretically half the tiles for key frames first frames
    kfffTileCount := FGlobalTilingTileCount;
    if Length(FFrames) > 1 then
      kfffTileCount := kfffTileCount shr 1;

    kfffTileCount := SolveTileCount(kfffTileCount, OnKFFirstFrame);
  end;

  ProgressRedraw(1, 'KFFirstFramesSolveTileCount');

  TTile.Array1DDispose(FTiles);
  TransferTiles(kfffTileCount, OnKFFirstFrame);
  kfffTileCount := ReduceTiles(kfffTileCount);
  ReindexTiles;

  ProgressRedraw(2, 'KFFirstFramesReduce');

  OnKFFirstFrame := False;
  if FGlobalTilingUseTargetPSNR then
  begin
    globalTileCount := round(GRTileCountFromPSNR(FGlobalTilingTargetPSNR, @OnKFFirstFrame));
  end
  else
  begin
    // subtract what was used for key frames first frames
    globalTileCount := FGlobalTilingTileCount - kfffTileCount;

    globalTileCount := SolveTileCount(globalTileCount, OnKFFirstFrame);
  end;

  ProgressRedraw(2, 'SolveTileCount');

  TransferTiles(globalTileCount, OnKFFirstFrame);
  ReduceTiles(kfffTileCount + globalTileCount);
  ReindexTiles;

  ProgressRedraw(3, 'Reduce');
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

  ProgressRedraw(0, '', esPredictMotion);

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
          Frame.Predict(FMotionPredictRadius, 0, DCTBuffer)
        end
        else
        begin
          for iBuf := 1 to Min(FMotionPredictMaxBufferedFrames, frmRelIdx) do
            Frame.Predict(FMotionPredictRadius, iBuf, DCTBuffer);
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
            Frame.Predict(FMotionPredictRadius, iBuf, DCTBuffer);

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

procedure TTilingEncoder.Reindex;

  procedure HandleTileIndex(ATileIndex: Integer);
  begin
    if ATileIndex >= 0 then
    begin
      Inc(Tiles[ATileIndex]^.UseCount);
      Tiles[ATileIndex]^.Active := True;
    end;
  end;

var
  frmIdx, sx, sy, iCpn: Integer;
  tidx: Int64;
  TMI: PTileMapItem;
begin
  if FrameCount = 0 then
    Exit;

  ProgressRedraw(0, '', esReindex);

  MakeTilesUnique;

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

        for iCpn := 0 to cColorCpns - 1 do
          HandleTileIndex(TMI^.TileIdx[iCpn]);
      end;

  ProgressRedraw(2, 'UseCount');

  ReindexTiles;

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
  i, palIdx, colIdx, oldRenderFrameIndex : Integer;
  oldRenderPage: TRenderPage;
  BMP: TBitmap;
begin
  palPict := TFastPortableNetworkGraphic.Create;

  palPict.Width := FScreenWidth;
  palPict.Height := FScreenHeight;
  palPict.PixelFormat := pf24bit;

  oldRenderFrameIndex := RenderFrameIndex;
  oldRenderPage := RenderPage;
  try
    RenderPage := rpOutput;
    BMP := FOutputBitmap;
    if AInput then
    begin
      RenderPage := rpInput;
      BMP := FInputBitmap;
    end;

    for i := 0 to High(FFrames) do
    begin
      RenderFrameIndex := i;
      Render;

      palPict.Canvas.Draw(0, 0, BMP);
      palPict.SaveToFile(Format('%s_%.4d.png', [ChangeFileExt(FOutputFileName, ''), i]));
    end;
  finally
    palPict.Free;

    RenderFrameIndex := oldRenderFrameIndex;
    RenderPage := oldRenderPage;
    Render;
  end;
end;

procedure TTilingEncoder.GenerateY4M(AFileName: String; AInput: Boolean);
var
  fx, fy, i, oldRenderFrameIndex : Integer;
  oldRenderPage: TRenderPage;
  fs: TBufferedFileStream;
  Header, FrameHeader: String;
  ptr: PByte;
  yf, uf, vf: TFloat;
  r, g, b: Byte;
  py, pu, pv: PByte;
  FrameData: TByteDynArray;
  BMP: TBitmap;
begin
  oldRenderFrameIndex := RenderFrameIndex;
  oldRenderPage := RenderPage;
  fs := TBufferedFileStream.Create(AFileName, fmCreate or fmShareDenyWrite);
  try
    Header := Format('YUV4MPEG2 W%d H%d F%d:1000000 Ip C444 XCOLORRANGE=LIMITED'#10, [FTileMapWidth * cTileWidth, FTileMapHeight * cTileWidth, round(FFramesPerSecond * 1000000)]);
    fs.Write(Header[1], length(Header));

    SetLength(FrameData, FTileMapWidth * cTileWidth * FTileMapHeight * cTileWidth * cColorCpns);

    RenderPage := rpOutput;
    BMP := FOutputBitmap;
    if AInput then
    begin
      RenderPage := rpInput;
      BMP := FInputBitmap;
    end;

    for i := 0 to High(FFrames) do
    begin
      FrameHeader := 'FRAME '#10;
      fs.Write(FrameHeader[1], Length(FrameHeader));

      RenderFrameIndex := i;
      Render;

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
    RenderFrameIndex := oldRenderFrameIndex;
    RenderPage := oldRenderPage;
    Render;
    fs.Free;
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
end;

procedure TTilingEncoder.InitFrames(AFrameCount: Integer);
var
  frmIdx: Integer;
begin
  SetLength(FFrames, AFrameCount);
  for frmIdx := 0 to High(FFrames) do
    FFrames[frmIdx] := TFrame.Create(Self, frmIdx);
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

procedure TTilingEncoder.SetRenderTilePage(AValue: Integer);
begin
  if FRenderTilePage = AValue then Exit;
  FRenderTilePage := Max(0, AValue);
end;

procedure TTilingEncoder.SetMotionPredictRadius(AValue: Integer);
begin
  if FMotionPredictRadius = AValue then Exit;
  FMotionPredictRadius := EnsureRange(AValue, 1, -Low(ShortInt));
end;

procedure TTilingEncoder.SetMotionPredictMaxBufferedFrames(AValue: Integer);
begin
  if FMotionPredictMaxBufferedFrames = AValue then Exit;
  FMotionPredictMaxBufferedFrames := EnsureRange(AValue, 1, 7);
end;

procedure TTilingEncoder.ConvertToCpnPixels(const ATile: TTile; VMirror, HMirror: Boolean; out ACpnPixel: TCpnPixels);

  procedure ToCpn(col, x, y: Integer);
  var
    r, g, b: Byte;
  begin
    FromRGB(col, r, g, b);

    ACpnPixel[0, y, x] := r * cDCTScale;
    ACpnPixel[1, y, x] := g * cDCTScale;
    ACpnPixel[2, y, x] := b * cDCTScale;
  end;

var
  x, y, xx, yy: Integer;
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

procedure TTilingEncoder.ComputePsyVisFeatures(const ACpnPixels: TCpnPixels; Mode: TPsyVisMode; ColorCpn: Integer; ADCT: PDCTScalar);
var
  u, v, cpn: Integer;
  z: Double;
  pLut: PSingle;
  pDCT: PSmallInt;
  pSnake: PByte;
begin
  Assert(not (Mode in [pvsWavelets]), 'Wavelets on SmallInt vector unimplemented!');

  if ColorCpn < 0 then
  begin
    for cpn := 0 to cColorCpns - 1 do
    begin
      pDCT := @ADCT[cpn * sqr(cTileWidth)];
      pLut := @FDCTLut[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
      pSnake := @cDCTSnake[0];
      for v := 0 to cTileWidth - 1 do
        for u := 0 to cTileWidth - 1 do
        begin
  		    z := DCTInner_asm(@ACpnPixels[cpn, 0, 0], pLut);

          if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
            z *= cDCTWeights[v, u];

          pDCT[pSnake^] := Round(z);
          Inc(pLut, Sqr(cTileWidth));
          Inc(pSnake);
        end;
    end;
  end
  else
  begin
    pDCT := @ADCT[0];
    pLut := @FDCTLut[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
    pSnake := @cDCTSnake[0];
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
		    z := DCTInner_asm(@ACpnPixels[ColorCpn, 0, 0], pLut);

        if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
          z *= cDCTWeights[v, u];

        pDCT[pSnake^] := Round(z);
        Inc(pLut, Sqr(cTileWidth));
        Inc(pSnake);
      end;
  end;
end;

procedure TTilingEncoder.ComputeTileCpnPsyVisFeatures(const ATile: TTile; Mode: TPsyVisMode; VMirror, HMirror: Boolean; ColorCpn: Integer; ADCT: PDouble);
var
  i, u, v: Integer;
  z: Double;
  CpnPixels: TCpnPixels;
  CpnPixelsDouble: TCpnPixelsDouble;
  pDCT, pLut: PDouble;
  LocalDCT: array[0..sqr(cTileWidth) - 1] of Double;
begin
  ConvertToCpnPixels(ATile, VMirror, HMirror, CpnPixels);

  for v := 0 to cTileWidth - 1 do
    for u := 0 to cTileWidth - 1 do
      CpnPixelsDouble[0, v, u] := CpnPixels[ColorCpn, v, u];

  if Mode = pvsWavelets then
  begin
    specialize WaveletGS<Double, PDouble>(@CpnPixelsDouble[0, 0, 0], @LocalDCT[0], cTileWidth, cTileWidth, 2);
  end
  else
  begin
    pDCT := @LocalDCT[0];
    pLut := @FDCTLutDouble[Mode in [pvsSpeDCT, pvsWeightedSpeDCT], 0];
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
        z := specialize DCTInner<PDouble>(@CpnPixelsDouble[0, 0, 0], pLut, 1);

        if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
           z *= cDCTWeights[v, u];

        pDCT^ := z;
        Inc(pDCT);
        Inc(pLut, Sqr(cTileWidth));
      end;
  end;

  for i := 0 to sqr(cTileWidth) - 1 do
    ADCT[cDCTSnake[i]] := LocalDCT[i];
end;

procedure TTilingEncoder.ComputeInvTileCpnPsyVisFeatures(DCT: PDouble; Mode: TPsyVisMode; ColorCpn: Integer; var ATile: TTile);
var
  i, u, v, x, y: Integer;
  CpnPixels: TCpnPixelsDouble;
  pCpn, pLut, pDCT: PDouble;
  LocalDCT: array[0..sqr(cTileWidth) - 1] of Double;
  d: Double;

  function FromCpn(x, y: Integer): Integer; inline;
  begin
    Result := EnsureRange(round(CpnPixels[0, y, x] * (1.0 / cDCTScale)), 0, High(Byte));
  end;

begin
  Assert(not (Mode in [pvsSpeDCT, pvsWeightedSpeDCT]), 'Special DCT is non-inversible');

  pDCT := @LocalDCT[0];
  i := 0;
  for v := 0 to cTileWidth - 1 do
    for u := 0 to cTileWidth - 1 do
    begin
      d := DCT[cDCTSnake[i]];
      if Mode in [pvsWeightedDCT, pvsWeightedSpeDCT] then
        pDCT^ := d / cDCTWeights[v, u]
      else
        pDCT^ := d;
      Inc(pDCT);
      Inc(i);
    end;

  if Mode = pvsWavelets then
  begin
    pCpn := @CpnPixels[0, 0, 0];
    specialize DeWaveletGS<Double, PDouble>(@LocalDCT[0], pCpn, cTileWidth, cTileWidth, 2);
  end
  else
  begin
    pCpn := @CpnPixels[0, 0, 0];
    pLut := @FInvDCTLutDouble[0];

    for y := 0 to cTileWidth - 1 do
      for x := 0 to cTileWidth - 1 do
      begin
        pCpn^ := specialize DCTInner<PDouble>(@LocalDCT[0], pLut, 1);
        Inc(pCpn);
        Inc(pLut, Sqr(cTileWidth));
      end;
  end;

  for y := 0 to (cTileWidth - 1) do
    for x := 0 to (cTileWidth - 1) do
      ATile.RGBPixels[y, x] := InsertRGB(ATile.RGBPixels[y, x], FromCpn(x, y), ColorCpn);
end;

class procedure TTilingEncoder.VMirrorTile(var ATile: TTile);
var
  j, i: Integer;
  v, sv: Integer;
begin
  // hardcode vertical mirror into the tile

  for j := 0 to cTileWidth div 2 - 1  do
    for i := 0 to cTileWidth - 1 do
    begin
      v := ATile.RGBPixels[j, i];
      sv := ATile.RGBPixels[cTileWidth - 1 - j, i];
      ATile.RGBPixels[j, i] := sv;
      ATile.RGBPixels[cTileWidth - 1 - j, i] := v;
    end;
end;

class procedure TTilingEncoder.HMirrorTile(var ATile: TTile);
var
  i, j: Integer;
  v, sv: Integer;
begin
  // hardcode horizontal mirror into the tile

  for j := 0 to cTileWidth - 1 do
    for i := 0 to cTileWidth div 2 - 1  do
    begin
      v := ATile.RGBPixels[j, i];
      sv := ATile.RGBPixels[j, cTileWidth - 1 - i];
      ATile.RGBPixels[j, i] := sv;
      ATile.RGBPixels[j, cTileWidth - 1 - i] := v;
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

procedure TTilingEncoder.Render;

  procedure DrawTile(const ABuffer: TIntegerDynArray2; AColorCpn: Integer; ATilePtr: PTile; ASY, ASX: Integer; AHmirror, AVmirror, AForceActive: Boolean); inline;
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
          if AColorCpn >= 0 then
          begin
            col := InsertRGB(psl^, ATilePtr^.RGBPixels[tym, txm], AColorCpn);
          end
          else
          begin
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
  i, j, sx, sy, globalTileCount, col, off, siz, iCpn: Integer;
  hmir, vmir: Boolean;
  tidx: Int64;
  q: Double;
  pFB: PInteger;
  TempTile, tilePtr: PTile;
  TempBuf: TIntegerDynArray2;
  TMI: PTileMapItem;
  Frame: TFrame;
  canvas: TCanvas;
begin
  if Length(FFrames) <= 0 then
    Exit;

  Frame := FFrames[FRenderFrameIndex];

  if not Assigned(Frame) or not Assigned(Frame.PKeyFrame) then
    Exit;

  TempTile := TTile.New;
  SetLength(TempBuf, cTileWidth, cTileWidth);
  try

    // Global

    globalTileCount := GetTileCount(False);

    FRenderTitleText := 'Global: ' + IntToStr(globalTileCount) + ' / Frame #' + IntToStr(FRenderFrameIndex) + IfThen(Frame.PKeyFrame.StartFrame = FRenderFrameIndex, ' [KF]', '     ') + ' : ' + IntToStr(GetFrameTileCount(Frame));

    // "Input" tab

    if FRenderPage = rpInput then
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

            DrawTile(TempBuf, -1, tilePtr, 0, 0, hmir, vmir, True);

            BlitBuffer(TempBuf, pFB, sy, sx, FInputBitmap.Width);
          end;
      finally
        FInputBitmap.EndUpdate;
        Frame.ReleaseFrameTiles;
      end;
    end;

    // "Output" tab

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
              TMI^.Attrs.BlendWeightM1, TMI^.Attrs.BlendWeightM2)
          else
            TempTile^.CopyRGBPixels(
              FRenderFrameBuffer.GetBuffer(-TMI^.Attrs.MotionBackBufferOffset),
              (sy shl cTileWidthBits) + TMI^.Attrs.MotionY,
              (sx shl cTileWidthBits) + TMI^.Attrs.MotionX);
          DrawTile(FRenderFrameBuffer.GetBuffer, -1, TempTile, sy, sx, False, False, True)
        end
        else if TMI^.IsValidTileIdx then
        begin
          hmir := TMI^.HMirror;
          vmir := TMI^.VMirror;

          if not FRenderMirrored then
          begin
            hmir := False;
            vmir := False;
          end;

          for iCpn := 0 to cColorCpns - 1 do
            DrawTile(FRenderFrameBuffer.GetBuffer, iCpn, FTiles[TMI^.TileIdx[iCpn]], sy, sx, hmir, vmir, False);
        end
        else
        begin
          DrawDummyTile(FRenderFrameBuffer.GetBuffer, sy, sx);
        end;
      end;

    if FRenderPage = rpOutput then
    begin
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
                col := $ff - (TMI^.Attrs.BlendWeightM1 + TMI^.Attrs.BlendWeightM2);
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

    if FRenderPage = rpTilesPalette then
    begin
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

              hmir := tilePtr^.HMirror_Initial;
              vmir := tilePtr^.VMirror_Initial;

              if not FRenderMirrored then
              begin
                hmir := False;
                vmir := False;
              end;

              for iCpn := 0 to cColorCpns - 1 do
                DrawTile(TempBuf, iCpn, tilePtr, 0, 0, hmir, vmir, False);

              BlitBuffer(TempBuf, pFB, sy, sx, FTilesBitmap.Width);
            end;
          end;
      finally
        FTilesBitmap.EndUpdate;
      end;
    end;

    // PSNR indicator

    q := 0.0;
    i := 0;
    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        TMI := @Frame.TileMap[sy, sx];

        if not IsInfinite(TMI^.PSNR) then
        begin
          q += TMI^.PSNR;
          Inc(i);
        end;
      end;
    if i <> 0 then
      q /= i;

    FRenderPsychoVisualQuality := q;

  finally
    FRenderPrevFrameIndex := FRenderFrameIndex;
    TTile.Dispose(TempTile);
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

    ini.WriteBool('GlobalTiling', 'GlobalTilingUseTargetPSNR', GlobalTilingUseTargetPSNR);
    ini.WriteFloat('GlobalTiling', 'GlobalTilingTargetPSNR', GlobalTilingTargetPSNR);
    ini.WriteFloat('GlobalTiling', 'GlobalTilingQualityBasedTileCount', GlobalTilingQualityBasedTileCount);
    ini.WriteInteger('GlobalTiling', 'GlobalTilingTileCount', GlobalTilingTileCount);

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

    GlobalTilingUseTargetPSNR := ini.ReadBool('GlobalTiling', 'GlobalTilingUseTargetPSNR', GlobalTilingUseTargetPSNR);
    GlobalTilingTargetPSNR := ini.ReadFloat('GlobalTiling', 'GlobalTilingTargetPSNR', GlobalTilingTargetPSNR);
    GlobalTilingQualityBasedTileCount := ini.ReadFloat('GlobalTiling', 'GlobalTilingQualityBasedTileCount', GlobalTilingQualityBasedTileCount);
    GlobalTilingTileCount := ini.ReadInteger('GlobalTiling', 'GlobalTilingTileCount', GlobalTilingTileCount); // after GlobalTilingQualityBasedTileCount because has priority

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

  MotionPredictRadius := 32;
  MotionPredictMaxBufferedFrames := 3;

  GlobalTilingUseTargetPSNR := False;
  GlobalTilingTargetPSNR := 20.0;
  GlobalTilingQualityBasedTileCount := 3.0;
  GlobalTilingTileCount := 0; // after GlobalTilingQualityBasedTileCount because has priority

  ShotTransMaxSecondsPerKF := 15.0;  // maximum seconds between keyframes
  ShotTransMinSecondsPerKF := 1.0;  // minimum seconds between keyframes
  ShotTransCorrelLoThres := 0.8;   // interframe pearson correlation low limit
end;

procedure TTilingEncoder.Test;
var
  i, j, rng: Integer;
  rr, gg, bb: Byte;
  l, a, b, y, u, v: TFloat;
  DCT: array [0..sqr(cTileWidth)-1] of Double;
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

  T := TTile.New;
  T2 := TTile.New;

  for i := 0 to cTileWidth - 1 do
    for j := 0 to cTileWidth - 1 do
      T^.RGBPixels[i, j] := i * 32 + j;

  ComputeTileCpnPsyVisFeatures(T^, pvsDCT, False, False, 0, @DCT[0]);
  ComputeInvTileCpnPsyVisFeatures(@DCT[0], pvsDCT, 0, T2^);

  //for i := 0 to 7 do
  //  for j := 0 to 7 do
  //    write(IntToHex(T^.RGBPixels[i, j], 6), '  ');
  //WriteLn();
  //for i := 0 to 7 do
  //  for j := 0 to 7 do
  //    write(IntToHex(T2^.RGBPixels[i, j], 6), '  ');
  //WriteLn();

  Assert(CompareMem(@T^.RGBPixels[0, 0], @T2^.RGBPixels[0, 0], SizeOf(TRGBPixels)), 'DCT/InvDCT mismatch');

  ComputeTileCpnPsyVisFeatures(T^, pvsWeightedDCT, False, False, 0, @DCT[0]);
  ComputeInvTileCpnPsyVisFeatures(@DCT[0], pvsWeightedDCT, 0, T2^);

  Assert(CompareMem(@T^.RGBPixels[0, 0], @T2^.RGBPixels[0, 0], SizeOf(TRGBPixels)), 'QWeighted DCT/InvDCT mismatch');

  ComputeTileCpnPsyVisFeatures(T^, pvsWavelets, False, False, 0, @DCT[0]);
  ComputeInvTileCpnPsyVisFeatures(@DCT[0], pvsWavelets, 0, T2^);

  Assert(CompareMem(@T^.RGBPixels[0, 0], @T2^.RGBPixels[0, 0], SizeOf(TRGBPixels)), 'WL/InvWL mismatch');

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

function TTilingEncoder.GetFrameTileCount(AFrame: TFrame): Integer;
var
  Used: TByteDynArray;
  sx, sy, iCpn: Integer;
  TMI: PTileMapItem;
begin
  Result := 0;

  if Length(Tiles) = 0 then
    Exit;

  SetLength(Used, Length(Tiles));
  FillByte(Used[0], Length(Tiles), 0);

  for sy := 0 to FTileMapHeight - 1 do
    for sx := 0 to FTileMapWidth - 1 do
    begin
      TMI := @AFrame.TileMap[sy, sx];
      for iCpn := 0 to cColorCpns - 1 do
        if TMI^.TileIdx[iCpn] >= 0 then
          Used[TMI^.TileIdx[iCpn]] := 1;
    end;

  for sx := 0 to High(Used) do
    Inc(Result, Used[sx]);
end;

function TTilingEncoder.GetUnpredictedTileCount: Integer;
var
  frmIdx: Integer;
begin
  Result := 0;
  for frmIdx := 0 to High(FFrames) do
    Inc(Result, FFrames[frmIdx].GetUnpredictedTileCount);
end;

function TTilingEncoder.GRTileCountFromPSNR(x: Double; Data: Pointer): Double;
var
  OnKFFirstFrame: PBoolean absolute Data;
  frmIdx, sy, sx, unpredictedTileCount: Integer;
  Frame: TFrame;
  TMI: PTileMapItem;
begin
  unpredictedTileCount := 0;
  for frmIdx := 0 to High(FFrames) do
  begin
    Frame := FFrames[frmIdx];

    if Assigned(OnKFFirstFrame) and (OnKFFirstFrame^ xor (Frame.Index = Frame.PKeyFrame.StartFrame)) then
      Continue;

    for sy := 0 to FTileMapHeight - 1 do
      for sx := 0 to FTileMapWidth - 1 do
      begin
        TMI := @Frame.TileMap[sy, sx];

        // trim bad (unfit) PSNRs
        TMI^.IsPredicted := TMI^.PSNR > x;

        inc(unpredictedTileCount, Ord(not TMI^.IsPredicted));
      end;
  end;

  Result := unpredictedTileCount;
end;

function TTilingEncoder.SolveTileCount(ATileCount: Integer; AOnKFFirstFrame: Boolean): Integer;
var
  err: Double;
begin
  err := Max(0.5, ATileCount * 0.001);
  Result := Round(GoldenRatioSearch(@GRTileCountFromPSNR, 0.0, cBestPSNR, ATileCount - err, cPsyVEpsilon, err, @AOnKFFirstFrame).Y);
end;

procedure TTilingEncoder.TransferTiles(ATileCount: Integer; AOnKFFirstFrame: Boolean);
var
  doneFrameCount: Integer;
  newTIdx: Integer;

  procedure DoTransfer(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    tIdx, sy, sx, ty, tx, iCpn: Integer;
    rgb: array[0 .. cColorCpns - 1] of Byte;
    Frame: TFrame;
    Tile, FrameTile: PTile;
    TMI: PTileMapItem;
  begin
    if not InRange(AIndex, 0, High(FFrames)) then
      Exit;

    Frame := FFrames[AIndex];

    if AOnKFFirstFrame xor (Frame.Index = Frame.PKeyFrame.StartFrame) then
      Exit;

    Frame.AcquireFrameTiles;
    try
      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMI := @Frame.TileMap[sy, sx];

          if not TMI^.IsPredicted then
          begin
            tIdx := InterLockedExchangeAdd(newTIdx, cColorCpns);

            FrameTile := Frame.FrameTiles[sy * FTileMapWidth + sx];
            Assert(FrameTile^.Active);

            for iCpn := 0 to cColorCpns - 1 do
            begin
              Tile := FTiles[tIdx];

              for ty := 0 to cTileWidth - 1 do
                for tx := 0 to cTileWidth - 1 do
                begin
                  FromRGB(FrameTile^.RGBPixels[ty, tx], rgb[0], rgb[1], rgb[2]);
                  Tile^.RGBPixels[ty, tx] := rgb[iCpn];
                end;

              Tile^.Flags := FrameTile^.Flags;
              Tile^.UseCount := 1;
              TMI^.TileIdx[iCpn] := tIdx;
              Inc(tIdx)
            end;
          end
          else
          begin
            TMI^.ResetTileIdx;
          end;
        end;

      Write(InterLockedIncrement(doneFrameCount):8, ' / ', Length(FFrames):8, #13);
    finally
      Frame.ReleaseFrameTiles;
    end;
  end;

begin
  WriteLn('TransferTiles ', ATileCount:8);

  doneFrameCount := 0;
  newTIdx := Length(FTiles);

  if newTIdx > 0 then
    TTile.Array1DRealloc(FTiles, newTIdx + ATileCount * cColorCpns)
  else
    FTiles := TTile.Array1DNew(ATileCount * cColorCpns);

  ProcThreadPool.DoParallelLocalProc(@DoTransfer, 0, High(FFrames));

  Assert(newTIdx = Length(FTiles));
end;

function TTilingEncoder.ReduceTiles(ATileCount: Integer): Integer;
var
  YakmoDataset: TSingleDynArray2;
  YakmoWeights: TCardinalDynArray;

  procedure DoDCT(AIndex: PtrInt; AData: Pointer; AItem: TMultiThreadProcItem);
  var
    iDCT: Integer;
    Tile: PTile;
    DCTDouble: array[0 .. sqr(cTileWidth) - 1] of Double;
  begin
    if not InRange(AIndex, 0, High(YakmoDataset)) then
      Exit;

    Tile := FTiles[AIndex];
    Assert(Tile^.Active);

    ComputeTileCpnPsyVisFeatures(Tile^, pvsWeightedDCT, False, False, 0, DCTDouble);
    for iDCT := 0 to sqr(cTileWidth) - 1 do
      YakmoDataset[AIndex, iDCT] := DCTDouble[iDCT];
    YakmoWeights[AIndex] := Tile^.UseCount;
  end;

var
  DSLen, iCluster, iDS, iDCT: Integer;
  MergeTileCount: Integer;

  Yakmo: PYakmoSingle;

  YakmoCentroids: TSingleDynArray2;
  YakmoClusters: TIntegerDynArray;
  MergeTileIdxs: TIntegerDynArray;

  DCTDouble: array[0 .. sqr(cTileWidth) - 1] of Double;
begin
  DSLen := Length(FTiles);

  SetLength(YakmoDataset, DSLen, Sqr(cTileWidth));
  SetLength(YakmoWeights, DSLen);

  // compute key frame frame tiles DCT

  ProcThreadPool.DoParallelLocalProc(@DoDCT, 0, DSLen - 1);

  // use Yakmo KMeans to reduce tile count

  Result := min(ATileCount, DSLen);

  WriteLn('ReduceTiles ', Result:8);

  SetLength(YakmoClusters, DSLen);
  SetLength(YakmoCentroids, Result, sqr(cTileWidth));

  Yakmo := yakmo_single_create(Result, 1, cYakmoMaxIterations, 1, 0, 0, 1);
  try
    yakmo_set_num_threads(MaxThreadCount);

    yakmo_single_load_train_data_weighted(Yakmo, Length(YakmoDataset), sqr(cTileWidth), PPSingle(@YakmoDataset[0]), @YakmoWeights[0]);
    yakmo_single_train_on_data(Yakmo, @YakmoClusters[0]);
    yakmo_single_get_centroids(Yakmo, PPSingle(@YakmoCentroids[0]));
  finally
    yakmo_single_destroy(Yakmo);
  end;

  // store centroid tiles

  InitMergeTiles;
  try
    SetLength(MergeTileIdxs, DSLen);

    for iCluster := 0 to High(YakmoCentroids) do
    begin
      MergeTileCount := 0;
      for iDS := 0 to High(YakmoClusters) do
        if YakmoClusters[iDS] = iCluster then
        begin
          MergeTileIdxs[MergeTileCount] := iDS;
          Inc(MergeTileCount);
        end;

      if MergeTileCount > 0 then
      begin
        for iDCT := 0 to sqr(cTileWidth) - 1 do
          DCTDouble[iDCT] := NanDef(YakmoCentroids[iCluster, iDCT], 0.0);
        ComputeInvTileCpnPsyVisFeatures(DCTDouble, pvsWeightedDCT, 0, FTiles[MergeTileIdxs[0]]^);

        MergeTiles(MergeTileIdxs, MergeTileCount, MergeTileIdxs[0]);
      end;
    end;
  finally
    FinishMergeTiles;
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

    ConvertToCpnPixels(T^, False, False, CpnPixels);
    ComputePsyVisFeatures(CpnPixels, pvsWeightedDCT, 0, @DS^.Dataset[AIndex, 0]);
  end;

var
  kfIdx: Integer;
begin
  // Compute psycho visual model for all tiles in all palettes

  DS := New(PTilingDataset);
  FillChar(DS^, SizeOf(TTilingDataset), 0);

  DS^.KNNSize := Length(FTiles);
  SetLength(DS^.Dataset, DS^.KNNSize, sqr(cTileWidth));

  ProcThreadPool.DoParallelLocalProc(@DoPsyV, 0, High(FTiles));

  // Build KNN

  DS^.ANN := ann_kdtree_short_create(PPSmallint(@DS^.Dataset[0]), DS^.KNNSize, sqr(cTileWidth), 32, ANN_KD_STD);

  // Dataset is ready

  FTileDS := DS;

  // init for LogPSNR

  for kfIdx := 0 to High(FKeyFrames) do
  begin
    FKeyFrames[kfIdx].ReconstructPSNRCml := 0;
    FKeyFrames[kfIdx].ReconstructFramesLeft := FKeyFrames[kfIdx].FrameCount;
  end;
end;

procedure TTilingEncoder.FinishReconstruct;
begin
  if Length(FTileDS^.Dataset) > 0 then
    ann_kdtree_short_destroy(FTileDS^.ANN);
  FTileDS^.ANN := nil;
  SetLength(FTileDS^.Dataset, 0);
  Dispose(FTileDS);

  FTileDS := nil;
end;

procedure TTilingEncoder.ReindexTiles;
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
  frmIdx, sx, sy, iCpn: Integer;
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

  LocTiles := TTile.Array1DNew(cnt);
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

  QuickSort(Tiles[0], 0, High(Tiles), SizeOf(PTile), @CompareTileUseCountRev);

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

        for iCpn := 0 to cColorCpns - 1 do
          Remap(TMI^.TileIdx[iCpn]);
      end;
  end;

  WriteLn('ReindexTiles: ', Length(Tiles):12, ' / ', Length(FFrames) * FTileMapSize:12,  ' final tiles, (', Length(Tiles) * 100.0 / (Length(FFrames) * FTileMapSize):4:3, '%)');
end;

function CompareTileRGBPixels(Item1, Item2:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PTile(Item1);
  t2 := PTile(Item2);
  Result := t1^.CompareRGBPixelsTo(t2^);
end;

procedure TTilingEncoder.MakeTilesUnique;
var
  i, pos, firstSameIdx: Integer;
  sortList: TFPList;
  sameIdx: TIntegerDynArray;

  procedure DoOneMerge;
  var
    j: Integer;
  begin
    if i - firstSameIdx >= 2 then
    begin
      for j := firstSameIdx to i - 1 do
        sameIdx[j - firstSameIdx] := PTile(sortList[j])^.TmpIndex;
      MergeTiles(sameIdx, i - firstSameIdx, sameIdx[0]);
    end;
    firstSameIdx := i;
  end;

begin
  InitMergeTiles;
  sortList := TFPList.Create;
  try

    // sort global tiles by palette indexes (L to R, T to B)

    SetLength(sameIdx, Length(FTiles));

    sortList.Count := Length(FTiles);
    pos := 0;
    for i := 0 to High(FTiles) do
      if FTiles[i]^.Active then
      begin
        sortList[pos] := FTiles[i];
        PTile(sortList[pos])^.TmpIndex := i;
        Inc(pos);
      end;
    sortList.Count := pos;

    sortList.Sort(@CompareTileRGBPixels);

    // merge exactly similar tiles (so, consecutive after prev code)

    firstSameIdx := 0;
    for i := 1 to sortList.Count - 1 do
      if CompareTileRGBPixels(sortList[i - 1], sortList[i]) <> 0 then
        DoOneMerge;

    i := sortList.Count;
    DoOneMerge;

  finally
    sortList.Free;
    FinishMergeTiles;
  end;
end;

procedure TTilingEncoder.MergeTiles(const TileIndexes: TIntegerDynArray; TileCount: Integer; BestIdx: Int64);
var
  i: Integer;
  tidx: Integer;
begin
  if TileCount <= 0 then
    Exit;

  for i := 0 to TileCount - 1 do
  begin
    tidx := TileIndexes[i];

    if tidx = BestIdx then
      Continue;

    Inc(FTiles[BestIdx]^.UseCount, FTiles[tidx]^.UseCount);

    FTiles[tidx]^.Active := False;
    FTiles[tidx]^.UseCount := 0;
    FTiles[tidx]^.MergeIndex := BestIdx;

    FTiles[tidx]^.ClearRGBPixels;
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
  sx, sy, frmIdx, iCpn: Integer;
  tidx: Int64;
begin
  for frmIdx := 0 to High(FFrames) do
    for sy := 0 to (FTileMapHeight - 1) do
      for sx := 0 to (FTileMapWidth - 1) do
        for iCpn := 0 to cColorCpns - 1 do
        begin
          tidx := FFrames[frmIdx].TileMap[sy, sx].TileIdx[iCpn];
          if tidx >= 0 then
          begin
            tidx := FTiles[tidx]^.MergeIndex;
            if tidx >= 0 then
              FFrames[frmIdx].TileMap[sy, sx].TileIdx[iCpn] := tidx;
          end;
        end;
end;

class function TTilingEncoder.GetTileZoneSum(const ATile: TTile; x, y, w, h: Integer): Integer;
var
  i, j: Integer;
  r, g, b: Byte;
begin
  Result := 0;
  for j := y to y + h - 1 do
    for i := x to x + w - 1 do
    begin
      FromRGB(ATile.RGBPixels[j, i], r, g, b);
      Result += ToLuma(r, g, b);
    end;
end;

class procedure TTilingEncoder.GetTileHVMirrorHeuristics(const ATile: TTile; out AHMirror, AVMirror: Boolean);
var
  q00, q01, q10, q11: Integer;
begin
  // enforce an heuristical 'spin' on tiles mirrors (brighter top-left corner)

  q00 := GetTileZoneSum(ATile, 0, 0, cTileWidth div 2, cTileWidth div 2);
  q01 := GetTileZoneSum(ATile, cTileWidth div 2, 0, cTileWidth div 2, cTileWidth div 2);
  q10 := GetTileZoneSum(ATile, 0, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);
  q11 := GetTileZoneSum(ATile, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);

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
      FTiles := TTile.Array1DNew(tileCnt);

    for iRawTile := rawStartIdx to rawEndIdx do
    begin
      tileIdx := baseTileIdx + iRawTile - rawStartIdx;

      KFStream.Read(FTiles[tileIdx]^.RGBPixels[0, 0], sqr(cTileWidth));
      FTiles[tileIdx]^.Active := True;
      rawTileIdxToTileIdx[iRawTile] := tileIdx;
    end;
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

  procedure SetTMI(tileIdx, palIdx: Integer; attrs: Integer; var TMI: TTileMapItem);
  begin
    //TMI.TileIdx := tileIdx; //TODO
    //TMI.PalIdx := palIdx;
    TMI.HMirror := attrs and 1 <> 0;
    TMI.VMirror := attrs and 2 <> 0;

    TMI.IsPredicted := False;

    if InRange(tileIdx, 0, High(FTiles)) then
      Inc(FTiles[tileIdx]^.UseCount);

    if InRange(palIdx, 0, High(FPalettes)) then
      Inc(FPalettes[palIdx].UseCount);
  end;

  function NextFrame(KF: TKeyFrame): TFrame;
  begin
    Inc(frmIdx);
    Result := TFrame.Create(Self, frmIdx);
    Result.PKeyFrame := kf;

    Result.FrameTiles := TTile.Array1DNew(FTileMapSize);
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
          //gtLoadPalette:
          //begin
          //  ReadPalette;
          //end;
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
            TMI^.Attrs.MotionBackBufferOffset := CommandData + 1;
            TMI^.IsPredicted := True;

            Inc(tmPos);
          end;
          //gtIntraTile:
          //begin
          //  palIdx := ReadWord;
          //
          //  tileIdx := Length(FTiles);
          //  TTile.Array1DRealloc(FTiles, tileIdx + 1);
          //
          //  KFStream.Read(FTiles[tileIdx]^.RGBPixels[0, 0], sqr(cTileWidth));
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

  procedure DoTMI(const TMI: TTileMapItem);
  var
    iCpn: Cardinal;
    attrs: Word;
    isLongTile, isLongOffsets: Boolean;
  begin
    if TMI.IsPredicted then
    begin
      if TMI.IsBlended then
      begin
        DoCmd(gtBlend, (TMI.Attrs.BlendWeightM2 shl CGTMBlendWeightShift) or TMI.Attrs.BlendWeightM1);
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
      isLongTile := False;
      for iCpn := 0 to cColorCpns - 1 do
        isLongTile := isLongTile or (TMI.TileIdx[iCpn] > High(Word));

      attrs := (Ord(TMI.VMirror) shl 1) or Ord(TMI.HMirror);

      if not isLongTile then
      begin
        DoCmd(gtShortTileIdx, attrs);
        for iCpn := 0 to cColorCpns - 1 do
          DoWord(TMI.TileIdx[iCpn]);
      end
      else
      begin
        DoCmd(gtLongTileIdx, attrs);
        for iCpn := 0 to cColorCpns - 1 do
          DoDWord(TMI.TileIdx[iCpn]);
      end;
    end;
  end;

  procedure WriteTiles(const AList: TIntegerDynArray; AStart: Integer = 0);
  var
    tlIdx, ty, tx: Integer;
  begin
    if Length(AList) > 0 then
    begin
      DoCmd(gtTileSet, 0);
      DoDWord(AStart); // start tile
      DoDWord(AStart + High(AList)); // end tile

      for tlIdx := 0 to High(AList) do
        for ty := 0 to cTileWidth - 1 do
          for tx := 0 to cTileWidth - 1 do
            DoByte(Tiles[AList[tlIdx]]^.RGBPixels[ty, tx] and High(Byte));
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
    DoDWord(maxTileCount); // tile count
  end;

  procedure WriteSettings;
  begin
    DoCmd(gtExtendedCommand, 0);
    ZStream.WriteAnsiString(GetSettings);
  end;

  procedure MapTiles;
  var
    tIdx, frmIdx, sy, sx, kfIdx, iCpn: Integer;
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

          for iCpn := 0 to cColorCpns - 1 do
          begin
            tIdx := TMI^.TileIdx[iCpn];
            if tIdx < 0 then
              Continue;

            tile := FTiles[tIdx];
            kfIdx := FFrames[frmIdx].PKeyFrame.Index;

            if tile^.TmpIndex < 0 then
              tile^.TmpIndex := kfIdx
            else if tile^.TmpIndex <> kfIdx then
              tile^.TmpIndex := High(Integer);
          end;
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

    // dim arrays

    SetLength(perKfTiles, Length(FKeyFrames));
    for kfIdx := 0 to High(perKfTiles) do
    begin
      SetLength(perKfTiles[kfIdx], perKFPos[kfIdx]);
      perKFPos[kfIdx] := 0;
    end;
    SetLength(globalTiles, globalPos);
    globalPos := 0;

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
  StartPos, StreamSize, LastKF, KFCount, KFSize, BlkSkipCount: Integer;
  kfIdx, frmIdx, yx, yxs, cs, sx, sy: Integer;
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
  Header.EncoderVersion := 4; // 2 -> fixed blending extents; 3 -> *AddlBlendTileIdx; 4 -> PredictMotion;
  Header.FramePixelWidth := FScreenWidth;
  Header.FramePixelHeight := FScreenHeight;
  Header.KFCount := Length(FKeyFrames);
  Header.FrameCount := Length(FFrames);
  Header.AverageBytesPerSec := 0;
  Header.KFMaxBytesPerSec := 0;
  AStream.WriteBuffer(Header, SizeOf(Header));

  SetLength(KFInfo, Length(FKeyFrames));
  for kfIdx := 0 to High(FKeyFrames) do
  begin
    FillChar(KFInfo[kfIdx], SizeOf(KFInfo[0]), 0);
    KFInfo[kfIdx].FourCC := 'GTMk';
    KFInfo[kfIdx].RIFFSize := SizeOf(KFInfo[0]) - SizeOf(KFInfo[0].FourCC) - SizeOf(KFInfo[0].RIFFSize);
    KFInfo[kfIdx].KFIndex := kfIdx;
    KFInfo[kfIdx].FrameIndex := FKeyFrames[kfIdx].StartFrame;
    KFInfo[kfIdx].TimeCodeMillisecond := Round(1000.0 * FKeyFrames[kfIdx].StartFrame / FFramesPerSecond);
    AStream.WriteBuffer(KFInfo[kfIdx], SizeOf(KFInfo[0]));
  end;

  Header.WholeHeaderSize := AStream.Size - StartPos;

  StartPos := AStream.Size;

  ZStream := TMemoryStream.Create;
  try
    MapTiles;

    WriteSettings;
    WriteDimensions;
    WriteTiles(globalTiles);

    LastKF := 0;
    for kfIdx := 0 to High(FKeyFrames) do
    begin
      KeyFrame := FKeyFrames[kfIdx];

      WriteTiles(perKfTiles[kfIdx], Length(globalTiles));

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
          KFCount := KeyFrame.EndFrame - LastKF + 1;
          LastKF := KeyFrame.EndFrame + 1;

          AStream.Position := AStream.Size;
          KFSize := AStream.Position;
          LZCompress(ZStream, AStream);

          KFSize := AStream.Size - KFSize;

          KFInfo[kfIdx].RawSize := ZStream.Size;
          KFInfo[kfIdx].CompressedSize := KFSize;
          if (kfIdx > 0) or (Length(FKeyFrames) = 1) then
            Header.KFMaxBytesPerSec := max(Header.KFMaxBytesPerSec, round(KFSize * FFramesPerSecond / KFCount));
          Header.AverageBytesPerSec += KFSize;

          WriteLn('KF: ', KeyFrame.StartFrame:8, ' FCnt: ', KFCount:4, ' Raw: ', KFInfo[kfIdx].RawSize:8, ' Written: ', KFSize:8, ' Bitrate: ', (KFSize / 1024.0 * 8.0 / KFCount):8:2, ' kbpf   (', (KFSize / 1024.0 * 8.0 / KFCount * FFramesPerSecond):8:2, ' kbps)');

          ZStream.Clear;
        end;
      end;
    end;
  finally
    ZStream.Free;
  end;

  Header.AverageBytesPerSec := round(Header.AverageBytesPerSec * FFramesPerSecond / Length(FFrames));
  AStream.Position := 0;
  AStream.WriteBuffer(Header, SizeOf(Header));
  for kfIdx := 0 to High(FKeyFrames) do
    AStream.WriteBuffer(KFInfo[kfIdx], SizeOf(KFInfo[0]));
  AStream.Position := AStream.Size;

  StreamSize := AStream.Size - StartPos;

  WriteLn('Written: ', StreamSize:12, ' Bitrate: ', (StreamSize / 1024.0 * 8.0 / Length(FFrames)):8:2, ' kbpf  (', (StreamSize / 1024.0 * 8.0 / Length(FFrames) * FFramesPerSecond):8:2, ' kbps)');
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

  FRenderPrevFrameIndex := -1;
  FRenderPredicted := True;
  FRenderMirrored := True;

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
    esReconstruct:
      Reconstruct;
    esPredictMotion:
      PredictMotion;
    esReindex:
      Reindex;
    esSave:
      Save;
  end;
end;

end.

