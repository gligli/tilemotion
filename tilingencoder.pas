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
  tbbmalloc, extern, utils, powell, mtpool, FPReadJPEG, mywritejpeg;
type
  TEncoderStep = (esAll = -1, esLoad = 0, esPredict, esReindex, esSave);
  TKeyFrameReason = (kfrNone, kfrManual, kfrLength, kfrDecorrelation, kfrEuclidean);
  TRenderPage = (rpNone, rpInput, rpOutput, rpTiles);
  TPsyVisMode = (pvsDCT, pvsWeightedDCT, pvsSpeDCT, pvsWeightedSpeDCT, pvsPSNRHVS);
  TBlendingMode = (bmNone, bmWeight, bmAlphaWeight);

const
  cEncoderStepLen: array[TEncoderStep] of Integer = ({esAll} -1, {esLoad} 5, {esPredict} 1, {esReindex} 3, {esSave} 1);

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
  // PredictedTileOffsets8x8:          data -> x offset (8 bits); y offset (8 bits); commandBits -> none (10 bits); backbuffer offset - 1 (2 bits)
  // PredictedTileBlending8x8:         data -> blending additive weight (8 bits) (256 + w); blending alpha (8 bits); commandBits -> none (10 bits); backbuffer offset - 1 (2 bits)
  // PredictedOffsetBlock0x0:          data -> none; commandBits -> block size in tiles - 1 (12 bits)
  // GlobalTile16:                     data -> global tile index (16 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // GlobalTile32:                     data -> global tile index (32 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // KeyFrmTile16:                     data -> keyframe tile index (16 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // KeyFrmTile32:                     data -> keyframe tile index (32 bits); commandBits -> none (10 bits); V mirror (1 bit); H mirror (1 bit)
  // PalTile:                          data -> tile index (32 bits); palette index (16 bits); commandBits -> none (9 bits); is keyframe tile (1 bit); V mirror (1 bit); H mirror (1 bit)
  //
  // (insert new commands here...)
  //
  // FrameEnd:                         data -> none; commandBits -> none (11 bits); is keyframe end (1 bit)
  // LoadPalette:                      data -> palette index (16 bits); { RGBA bytes (32bits) } * indexes count; commandBits -> palette format (0: RGBA32) (6 bits); indexes count per palette - 1 (6 bits)
  // TileSet:                          data -> start tile (32 bits); end tile (32 bits); { palette index (16 bits) } * count; { indexes per pixel (64 [bytes] / [nibbles, ie: 103254...]) } * count; commandBits -> none (10 bits); is nibble coded (1 bit); is keyframe tileset (1 bit)
  // SetDimensions:                    data -> width in tiles (32 bits); height in tiles (32 bits); frame length in nanoseconds (32 bits) (2^32-1: still frame); global tile count (32 bits); maximum key frame tile count (32 bits); commandBits -> none (12 bits)
  // ExtendedCommand:                  data -> following bytes count (32 bits); custom commands, proprietary extensions, ...; commandBits -> extended command index (12 bits)

  TGTMCommand = (
    gtPredictedTileOffsets6x6 = 0,
    gtPredictedTileOffsets8x8 = 1,
    gtPredictedTileBlending8x8 = 2,
    gtPredictedOffsetBlock0x0 = 3,
    gtGlobalTile16 = 4,
    gtGlobalTile32 = 5,
    gtKeyFrmTile16 = 6,
    gtKeyFrmTile32 = 7,
    gtPalTile = 8,

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

  TCpnPixelsB = array[0 .. cColorCpns - 1, 0 .. Sqr(cTileWidth) - 1] of Byte;
  TCpnPixelsF = array[0 .. cColorCpns - 1, 0 .. Sqr(cTileWidth) - 1] of Single;

  PCpnPixelsF = ^TCpnPixelsF;
  TPCpnPixelsFDynArray = array of PCpnPixelsF;

  ETilingEncoderGTMReloadError = class(Exception);

  { TTile }

  TTile = packed record
    UseCount: Cardinal;
    JPEGError: Cardinal;
    TmpIndex, MergeIndex, MapTileIndex, MapKFIndex: Integer;
    Flags: set of (tfActive, tfHMirror_Initial, tfVMirror_Initial, tfFinalized);
    Pixels: TCpnPixelsB;
  end;

  { TTileHelper }

  TTileHelper = record helper for TTile
  private
    function GetActive: Boolean;
    function GetHMirror_Initial: Boolean;
    function GetFinalized: Boolean;
    function GetVMirror_Initial: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure SetHMirror_Initial(AValue: Boolean);
    procedure SetFinalized(AValue: Boolean);
    procedure SetVMirror_Initial(AValue: Boolean);
  public

    class function Array1DNew(x: Integer): PTileDynArray; static;
    class procedure Array1DDispose(var AArray: PTileDynArray); static;
    class procedure Array1DRealloc(var AArray: PTileDynArray; ANewX: integer); static;
    class function New: PTile; static;
    class procedure Dispose(var ATile: PTile); static;
    procedure CopyFrom(const ATile: TTile);
    procedure CopyRGBPixels(const AFrameBuffer: TIntegerDynArray2; AY, AX: Integer); overload;
    procedure BlendRGBPixels(const AFrameM1, AFrameM2: TIntegerDynArray2; AY, AX: Integer; AAlpha, AWeight: Integer);
    procedure BlitRGBPixels(const AFrameBuffer: TIntegerDynArray2; AVMirror, AHMirror: Boolean; AY, AX: Integer);
    procedure ClearRGBPixels;
    function CompareRawPixelsTo(const ATile: TTile): Integer;
    function CompareHSVPixelsTo(const ATile: TTile): Integer;

    property Active: Boolean read GetActive write SetActive;
    property Finalized: Boolean read GetFinalized write SetFinalized;
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
      True: (Alpha: Byte; Weight: ShortInt; BlendBackBufferOffset: Byte);
    end;
    Flags: set of (tmfHMirror, tmfVMirror, tmfPredicted, tmfBlended); // 1
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
    function GetIsBlended: Boolean;
    function GetIsMotion: Boolean;
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
    property IsMotion: Boolean read GetIsMotion;
    property IsBlended: Boolean read GetIsBlended write SetIsBlended;
    property IsSmoothed: Boolean read GetIsSmoothed;
    property HMirror: Boolean read GetHMirror write SetHMirror;
    property VMirror: Boolean read GetVMirror write SetVMirror;
  end;

  TTilingEncoder = class;
  TKeyFrame = class;

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
    FrameTilesJPEG: PTileDynArray;
    FrameTilesRefCount: Integer;
    FrameTilesEvent: THandle;
    FrameTilesLock: TSpinlock;
    FrameTilesStream: TMemoryStream;
    FrameTilesJPEGStream: TMemoryStream;
    FrameTilesJPEGPSNR: Double;

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
    function GRPSNR(x: Double; Data: Pointer): Double;

    function PowellBlending(const x: TVector; data: Pointer): TScalar;
    procedure GetPredictExtents(ARadius, ADY, ADX: Integer; out oxmn, oxmx, oymn, oymx: Integer);

    procedure PredictTileBlending(AUnipolar: Boolean; ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem;
      const ADCT: TDCT; const ACpnPixels: TCpnPixelsF; AFrameBuffer: TFrameBuffer);
    procedure PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT;
      const ADCTs: TDCTDynArray; const APenaltyLUT: TCardinalDynArray);
    procedure PredictTileIntra(ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray);

    // processes

    procedure LoadFromImage(AImageWidth, AImageHeight: Integer; AImage: PInteger);
    procedure PrepareDCTs(AMTPool: TMTPool; const ADCTs: TDCTDynArray; const ABuffer: TIntegerDynArray2);
    procedure Predict(AMTPool: TMTPool; ARadius, ABackBufferOffset: Integer; ADCTBuffer: TDCTBuffer; AFrameBuffer: TFrameBuffer);
    procedure SelectPredictions;
    procedure DirectBlit(AMTPool: TMTPool; const ABuffer: TIntegerDynArray2);
    procedure PredictedBlit(AMTPool: TMTPool; AFrameBuffer: TFrameBuffer);
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
    FMotionPredictBlendingMode: TBlendingMode;
    FReduceQuality: Integer;
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
    FRenderPlaying: Boolean;
    FRenderOutputJPEG: Boolean;
    FRenderTilePage: Integer;
    FRenderFrameBuffer: TFrameBuffer;
    FOutputBitmap: TBitmap;
    FInputBitmap: TBitmap;
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
    function GetRenderTilePageCount: Integer;
    procedure SetFrameCountSetting(AValue: Integer);
    procedure SetFramesPerSecond(AValue: Double);
    procedure SetMaxThreadCount(AValue: Integer);
    procedure SetMotionPredictRadius(AValue: Integer);
    procedure SetMotionPredictMaxBufferedFrames(AValue: Integer);
    procedure SetRenderFrameIndex(AValue: Integer);
    procedure SetRenderGammaValue(AValue: Double);
    procedure SetRenderMirrored(AValue: Boolean);
    procedure SetRenderOutputJPEG(AValue: Boolean);
    procedure SetRenderPage(AValue: TRenderPage);
    procedure SetRenderPredicted(AValue: Boolean);
    procedure SetRenderTilePage(AValue: Integer);
    procedure SetReduceQuality(AValue: Integer);
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

    class procedure ConvertToCpnPixels(const ATile: TTile; VMirror, HMirror: Boolean; out ACpnPixel: TCpnPixelsF);
    procedure ComputePsyVisFeatures(const ACpnPixels: TCpnPixelsF; Mode: TPsyVisMode; ADCT: PDCTScalar);

    function GetTileCount(AActiveOnly: Boolean): Integer;
    function GetFrameTileCount(AFrame: TFrame): Integer;
    function GetUnpredictedTileCount: Integer;
    class function GetTileZoneSum(const ATile: TTile; ACpn, x, y, w, h: Integer): Integer;
    class procedure GetTileHVMirrorHeuristics(const ATile: TTile; ACpn: Integer; out AHMirror, AVMirror: Boolean);
    class procedure HMirrorTile(var ATile: TTile);
    class procedure VMirrorTile(var ATile: TTile);

    procedure InitLuts;
    procedure ClearAll(AKeepFrames: Boolean);
    procedure ReframeUI(AWidth, AHeight: Integer);
    procedure InitFrames(AFrameCount: Integer);
    procedure LoadInputVideo;
    procedure FindKeyFrames(AManualMode: Boolean);

    procedure TransferTiles(AFrame: TFrame);

    procedure ReindexTiles;
    procedure MakeTilesUnique;
    procedure InitMergeTiles;
    procedure FinishMergeTiles;
    procedure MergeTiles(const TileIndexes: TIntegerDynArray; TileCount: Integer; BestTileIdx: Int64);

    procedure RenderFrame(AFrameIndex: Integer; APage: TRenderPage);

    procedure LoadStream(AStream: TStream);
    procedure SaveStream(AStream: TStream);

    // processes

    procedure Load;
    procedure PredictMotion;
    procedure Reindex;
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
    property MotionPredictBlendingMode: TBlendingMode read FMotionPredictBlendingMode write FMotionPredictBlendingMode;
    property ReduceQuality: Integer read FReduceQuality write SetReduceQuality;
    property MaxThreadCount: Integer read FMaxThreadCount write SetMaxThreadCount;
    property ShotTransMaxSecondsPerKF: Double read FShotTransMaxSecondsPerKF write SetShotTransMaxSecondsPerKF;
    property ShotTransMinSecondsPerKF: Double read FShotTransMinSecondsPerKF write SetShotTransMinSecondsPerKF;
    property ShotTransCorrelLoThres: Double read FShotTransCorrelLoThres write SetShotTransCorrelLoThres;

    // GUI state variables

    property RenderPlaying: Boolean read FRenderPlaying write FRenderPlaying;
    property RenderFrameIndex: Integer read FRenderFrameIndex write SetRenderFrameIndex;
    property RenderPredicted: Boolean read FRenderPredicted write SetRenderPredicted;
    property RenderMirrored: Boolean read FRenderMirrored write SetRenderMirrored;
    property RenderOutputJPEG: Boolean read FRenderOutputJPEG write SetRenderOutputJPEG;
    property RenderUseGamma: Boolean read FRenderUseGamma write SetRenderUseGamma;
    property RenderTilePage: Integer read FRenderTilePage write SetRenderTilePage;
    property RenderTilePageCount: Integer read GetRenderTilePageCount;
    property RenderGammaValue: Double read GetRenderGammaValue write SetRenderGammaValue;
    property RenderPage: TRenderPage read FRenderPage write SetRenderPage;
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

  { TRGBTiledImg }

  TRGBTiledImg = class(TFPCustomImage)
  private
    FImage: PTileDynArray;
    FTileStride: Integer;
  protected
    function GetInternalColor(x, y: integer): TFPColor; override;
    procedure SetInternalColor (x, y: integer; const Value: TFPColor); override;
    function GetInternalPixel(x, y: integer): integer; override;
    procedure SetInternalPixel(x, y: integer; Value: integer); override;
  public
    property Image: PTileDynArray read FImage write FImage;
    property TileStride: Integer read FTileStride write FTileStride;
  end;

implementation

const
  CGTMCommandsCount = Ord(High(TGTMCommand)) + 1;
  CGTMCommandCodeBits = round(ln(CGTMCommandsCount) / ln(2));
  CGTMCommandBits = 16 - CGTMCommandCodeBits;
  CGTMBlendWeightBaseShift = 8;
  CGTMBlendWeightMax = 127;
  CGTMBlendWeightMin = -CGTMBlendWeightMax - 1;
  CGTMBlendAlphaShift = 8;
  CGTMBlendAlphaMax = (1 shl CGTMBlendAlphaShift) - 1;

  function CompareTileUseCountRev(Item1, Item2, UserParameter:Pointer):Integer;
  var
    t1, t2: PTile;
  begin
    t1 := PPTile(Item1)^;
    t2 := PPTile(Item2)^;

    Result := CompareValue(t2^.UseCount, t1^.UseCount);
    if Result = 0 then
      Result := t1^.CompareHSVPixelsTo(t2^)
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
  Error := High(Cardinal);
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

function TTileMapItemHelper.GetIsMotion: Boolean;
begin
  Result := (tmfPredicted in Flags) and not (tmfBlended in Flags);
end;

function TTileMapItemHelper.GetIsSmoothed: Boolean;
begin
  Result := IsPredicted and
    ((not IsBlended and (Attrs.MotionX = 0) and (Attrs.MotionY = 0) and (Attrs.MotionBackBufferOffset = 1)) or
     (IsBlended and (Attrs.Alpha = 0) and (Attrs.Weight = 0) and (Attrs.BlendBackBufferOffset = 1)));
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

{ TRGBTiledImg }

function TRGBTiledImg.GetInternalColor(x, y: integer): TFPColor;
var
  r, g, b: Integer;
begin
  FromRGB(GetInternalPixel(x, y), r ,g, b);
  Result.red:=(r shl 8)+r;
  Result.green:=(g shl 8)+g;
  Result.blue:=(b shl 8)+b;
  Result.alpha:=alphaOpaque;
end;

procedure TRGBTiledImg.SetInternalColor(x, y: integer; const Value: TFPColor);
begin
  SetInternalPixel(x, y, ToRGB(Value.red shr 8, Value.green shr 8, Value.blue shr 8));
end;

function TRGBTiledImg.GetInternalPixel(x, y: integer): integer;
var
  yx: Integer;
  T: PTile;
begin
  T := FImage[(y shr cTileWidthBits) * FTileStride + (x shr cTileWidthBits)];
  yx := ((y and (cTileWidth - 1)) shl cTileWidthBits) or (x and (cTileWidth - 1));

  Result := ToRGB(T^.Pixels[0, yx], T^.Pixels[1, yx], T^.Pixels[2, yx]);
end;

procedure TRGBTiledImg.SetInternalPixel(x, y: integer; Value: integer);
var
  yx: Integer;
  T: PTile;
begin
  T := FImage[(y shr cTileWidthBits) * FTileStride + (x shr cTileWidthBits)];
  yx := ((y and (cTileWidth - 1)) shl cTileWidthBits) or (x and (cTileWidth - 1));

  FromRGB(Value, T^.Pixels[0, yx], T^.Pixels[1, yx], T^.Pixels[2, yx]);
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

function TTileHelper.GetFinalized: Boolean;
begin
  Result := tfFinalized in Flags;
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

procedure TTileHelper.SetFinalized(AValue: Boolean);
begin
  if AValue then
    Flags += [tfFinalized]
  else
    Flags -= [tfFinalized];
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
  tyx, ty, tx: Integer;
begin
  tyx := 0;
  for ty := 0 to cTileWidth - 1 do
  begin
    for tx := 0 to cTileWidth - 1 do
    begin
      FromRGB(AFrameBuffer[AY, AX], Pixels[0, tyx], Pixels[1, tyx], Pixels[2, tyx]);
      Inc(AX);
      Inc(tyx);
    end;
    Dec(AX, cTileWidth);
    Inc(AY);
  end;
end;

procedure TTileHelper.BlendRGBPixels(const AFrameM1, AFrameM2: TIntegerDynArray2; AY, AX: Integer; AAlpha,
  AWeight: Integer);
var
  tyx, ty, tx, col: Integer;
begin
  tyx := 0;
  for ty := 0 to cTileWidth - 1 do
  begin
    for tx := 0 to cTileWidth - 1 do
    begin
      col := BlendRGB(AFrameM1[AY, AX], AFrameM2[AY, AX], AAlpha, AWeight, CGTMBlendAlphaShift, CGTMBlendWeightBaseShift);
      FromRGB(col, Pixels[0, tyx], Pixels[1, tyx], Pixels[2, tyx]);
      Inc(AX);
      Inc(tyx);
    end;
    Dec(AX, cTileWidth);
    Inc(AY);
  end;
end;

procedure TTileHelper.BlitRGBPixels(const AFrameBuffer: TIntegerDynArray2; AVMirror, AHMirror: Boolean; AY, AX: Integer);
var
  tyx, ty, tx, tym, txm: Integer;
begin
  for ty := 0 to cTileWidth - 1 do
  begin
    tym := ty;
    if AVMirror then tym := cTileWidth - 1 - tym;

    for tx := 0 to cTileWidth - 1 do
    begin
      txm := tx;
      if AHMirror then txm := cTileWidth - 1 - txm;

      tyx := (tym shl cTileWidthBits) + txm;

      AFrameBuffer[AY + ty, AX + tx] := ToRGB(Pixels[0, tyx], Pixels[1, tyx], Pixels[2, tyx]);
    end;
  end;
end;

procedure TTileHelper.ClearRGBPixels;
begin
  FillChar(Pixels, SizeOf(Pixels), 0);
end;

function TTileHelper.CompareHSVPixelsTo(const ATile: TTile): Integer;
const
  CPrecisionDiv = 1;
var
  iPx, luma, lumaAccL, lumaAccR: Integer;
  h, s, v, hAccL, sAccL, vAccL, hAccR, sAccR, vAccR: TFloat;
begin
  lumaAccL := 0;
  lumaAccR := 0;
  hAccL := 0.0; sAccL := 0.0; vAccL := 0.0;
  hAccR := 0.0; sAccR := 0.0; vAccR := 0.0;


  for iPx := 0 to Sqr(cTileWidth) - 1 do
  begin
    luma := ToLuma(Pixels[0, iPx], Pixels[1, iPx], Pixels[2, iPx]);
    lumaAccL += luma;

    RGBToHSV(Pixels[0, iPx], Pixels[1, iPx], Pixels[2, iPx], h, s, v);
    hAccL += h; sAccL += s; vAccL += v;

    luma := ToLuma(ATile.Pixels[0, iPx], ATile.Pixels[1, iPx], ATile.Pixels[2, iPx]);
    lumaAccR += luma;

    RGBToHSV(Pixels[0, iPx], Pixels[1, iPx], Pixels[2, iPx], h, s, v);
    hAccR += h; sAccR += s; vAccR += v;
  end;

  Result := CompareValue(lumaAccL, lumaAccR, Sqr(cTileWidth) * cLumaDiv * CPrecisionDiv);
  if Result = 0 then
    Result := CompareValue(0.0, FMod(hAccL - hAccR, Sqr(cTileWidth)), Sqr(cTileWidth) / High(Byte) * CPrecisionDiv);
  if Result = 0 then
    Result := CompareValue(sAccL, sAccR, Sqr(cTileWidth) / High(Byte) * CPrecisionDiv);
  if Result = 0 then
    Result := CompareValue(vAccL, vAccR, Sqr(cTileWidth) / High(Byte) * CPrecisionDiv);
end;

function TTileHelper.CompareRawPixelsTo(const ATile: TTile): Integer;
begin
  Result := CompareByte(Pixels[0, 0], ATile.Pixels[0, 0], sqr(cTileWidth) * cColorCpns);
end;

procedure TTileHelper.CopyFrom(const ATile: TTile);
begin
  Move(ATile, Self, SizeOf(TTile));
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
begin
  Encoder := AParent;
  Index := AIndex;

  FrameTilesEvent := CreateEvent(nil, True, False, nil);
  FrameTilesStream := TMemoryStream.Create;
  FrameTilesJPEGStream := TMemoryStream.Create;
  InterframeCorrelationEvent := CreateEvent(nil, True, False, nil);
  LoadFromImageFinishedEvent := CreateEvent(nil, True, False, nil);
  SpinLeave(@FrameTilesLock);

  SetLength(TileMap, Encoder.FTileMapHeight, Encoder.FTileMapWidth);
  ResetTileMap(False);
end;

destructor TFrame.Destroy;
begin
  CloseHandle(LoadFromImageFinishedEvent);
  CloseHandle(InterframeCorrelationEvent);
  FrameTilesStream.Free;
  FrameTilesJPEGStream.Free;
  CloseHandle(FrameTilesEvent);

  inherited Destroy;
end;

procedure TFrame.CompressFrameTiles;
var
  CompStream: Tcompressionstream;
begin
  FrameTilesStream.Clear;
  CompStream := Tcompressionstream.create(Tcompressionlevel.cldefault, FrameTilesStream, True);
  try
    CompStream.WriteBuffer(FrameTiles[0]^, Length(TileMap) * Length(TileMap[0]) * SizeOf(TTile));
    CompStream.flush;
  finally
    CompStream.Free;
  end;

  Assert(FrameTilesStream.Size > 0);

  // now that FrameTiles are compressed, dispose them

  TTile.Array1DDispose(FrameTiles);
end;

procedure TFrame.AcquireFrameTiles;
var
  CompStream: Tdecompressionstream;
  yx, ftrc: Integer;
  FT: PTile;
  Img: TRGBTiledImg;
  JPEGRd: TFPReaderJPEG;
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
    Assert(FrameTilesStream.Size > 0);

    FrameTilesStream.Position := 0;
    FrameTiles := TTile.Array1DNew(Length(TileMap) * Length(TileMap[0]));

    CompStream := Tdecompressionstream.create(FrameTilesStream, True);
    try
      CompStream.ReadBuffer(FrameTiles[0]^, Length(TileMap) * Length(TileMap[0]) * SizeOf(TTile));
    finally
      CompStream.Free;
    end;

    FrameTilesJPEGStream.Position := 0;
    FrameTilesJPEG := TTile.Array1DNew(Length(TileMap) * Length(TileMap[0]));
    for yx := 0 to Length(TileMap) * Length(TileMap[0]) - 1 do
    begin
      FT := FrameTilesJPEG[yx];
      FT^.Active := True;
      FT^.UseCount := 1;
    end;

    Img := TRGBTiledImg.Create(Length(TileMap[0]) shl cTileWidthBits, Length(TileMap) shl cTileWidthBits);
    JPEGRd := TFPReaderJPEG.Create;
    try
      JPEGRd.Performance := jpBestQuality;
      Img.TileStride := Length(TileMap[0]);
      Img.Image := FrameTilesJPEG;
      Img.LoadFromStream(FrameTilesJPEGStream, JPEGRd);
    finally
      JPEGRd.Free;
      Img.Free;
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
      TTile.Array1DDispose(FrameTilesJPEG);

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
    CpnPixels: TCpnPixelsF;
  begin
    yx := AIndex * (Encoder.FScreenWidth - cTileWidth + 1);

    DCTTile := TTile.New;
    try
      for x := 0 to Encoder.FScreenWidth - cTileWidth do
      begin
        DCTTile^.CopyRGBPixels(ABuffer, AIndex, x);

        Encoder.ConvertToCpnPixels(DCTTile^, False, False, CpnPixels);
        Encoder.ComputePsyVisFeatures(CpnPixels, pvsPSNRHVS, ADCTs[yx]);

        Inc(yx);
      end;
    finally
      TTile.Dispose(DCTTile);
    end;
  end;

begin
  AMTPool.DoLocalProc(@DoDCTs, 0, Encoder.FScreenHeight - cTileWidth);
end;

type
  TPowellBlendData = record
    DX, DY: Integer;
    FrameM1, FrameM2: TIntegerDynArray2;
    RefCpnPixels: TCpnPixelsF;
  end;

  PPowellBlendData = ^TPowellBlendData;

function TFrame.PowellBlending(const x: TVector; data: Pointer): TScalar;
var
  pbData: PPowellBlendData absolute data;
  dx, dy, tyx, ty, tx, alpha, weight: Integer;
  r, g, b: Byte;
  y, u, v: TFloat;
begin
  Assert((Length(x) = 2) = Assigned(pbData^.FrameM2));

  dx := pbData^.DX;
  dy := pbData^.DY;

  Result := 0.0;

  if Assigned(pbData^.FrameM2) then
  begin
    alpha := EnsureRange(Round(x[0]), 0, CGTMBlendAlphaMax);
    weight := EnsureRange(Round(x[1]), CGTMBlendWeightMin, CGTMBlendWeightMax);

    tyx := 0;
    for ty := 0 to (cTileWidth - 1) do
    begin
      for tx := 0 to (cTileWidth - 1) do
      begin
        BlendRGB(pbData^.FrameM1[dy, dx], pbData^.FrameM2[dy, dx], alpha, weight, CGTMBlendAlphaShift, CGTMBlendWeightBaseShift, r, g, b);

        RGBToYUV(r, g, b, y, u, v, cDCTScale);
        Result += Sqr(pbData^.RefCpnPixels[0, tyx] - y);
        Result += Sqr(pbData^.RefCpnPixels[1, tyx] - u);
        Result += Sqr(pbData^.RefCpnPixels[2, tyx] - v);

        Inc(dx);
        Inc(tyx);
      end;
      Dec(dx, cTileWidth);
      Inc(dy);
    end;
  end
  else
  begin
    alpha := 0;
    weight := EnsureRange(Round(x[0]), CGTMBlendWeightMin, CGTMBlendWeightMax);

    tyx := 0;
    for ty := 0 to (cTileWidth - 1) do
    begin
      for tx := 0 to (cTileWidth - 1) do
      begin
        BlendRGB(pbData^.FrameM1[dy, dx], 0, alpha, weight, CGTMBlendAlphaShift, CGTMBlendWeightBaseShift, r, g, b);

        RGBToYUV(r, g, b, y, u, v, cDCTScale);
        Result += Sqr(pbData^.RefCpnPixels[0, tyx] - y);
        Result += Sqr(pbData^.RefCpnPixels[1, tyx] - u);
        Result += Sqr(pbData^.RefCpnPixels[2, tyx] - v);

        Inc(dx);
        Inc(tyx);
      end;
      Dec(dx, cTileWidth);
      Inc(dy);
    end;
  end;
end;

procedure TFrame.PredictTileBlending(AUnipolar: Boolean; ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ACpnPixels: TCpnPixelsF; AFrameBuffer: TFrameBuffer);
var
  bestAlpha, bestWeight: Integer;
  bestErr: Cardinal;
  pbData: TPowellBlendData;
  X: TVector;
  BlendTile: PTile;
  BlendCpnPixels: TCpnPixelsF;
  BlendDCT: TDCT;
begin
  pbData.DX := ADX;
  pbData.DY := ADY;
  pbData.RefCpnPixels := ACpnPixels;
  pbData.FrameM1 := AFrameBuffer.GetBuffer(-ABackBufferOffset);

  BlendTile := TTile.New;
  try
    if AUnipolar then
    begin
      Assert(InRange(ABackBufferOffset, 1, Encoder.MotionPredictMaxBufferedFrames));

      pbData.FrameM2 := nil;

      X := [0.0];
      bestErr := Round(NelderMeadMinimize(@PowellBlending, X, [-CGTMBlendWeightMin], 0.5, @pbData));
      bestAlpha := 0;
      bestWeight := EnsureRange(Round(x[0]), CGTMBlendWeightMin, CGTMBlendWeightMax);

      BlendTile^.BlendRGBPixels(pbData.FrameM1, pbData.FrameM1, ADY, ADX, bestAlpha, bestWeight);
    end
    else
    begin
      Assert(InRange(ABackBufferOffset, 1, Encoder.MotionPredictMaxBufferedFrames - 1));

      pbData.FrameM2 := AFrameBuffer.GetBuffer(-ABackBufferOffset - 1);

      X := [(CGTMBlendAlphaMax + 1) * 0.25, 0.0];
      bestErr := Round(NelderMeadMinimize(@PowellBlending, X, [(CGTMBlendAlphaMax + 1) * 0.25, -CGTMBlendWeightMin], 0.5, @pbData));
      bestAlpha := EnsureRange(Round(x[0]), 0, CGTMBlendAlphaMax);
      bestWeight := EnsureRange(Round(x[1]), CGTMBlendWeightMin, CGTMBlendWeightMax);

      BlendTile^.BlendRGBPixels(pbData.FrameM1, pbData.FrameM2, ADY, ADX, bestAlpha, bestWeight);
    end;

    Encoder.ConvertToCpnPixels(BlendTile^, False, False, BlendCpnPixels);
    Encoder.ComputePsyVisFeatures(BlendCpnPixels, pvsPSNRHVS, BlendDCT);
    bestErr := CompareEuclideanDCTPtr_asm(ADCT, BlendDCT);
    bestErr += ApplyBlendPredictionPenalty(bestAlpha, bestWeight, ABackBufferOffset);
  finally
    TTile.Dispose(BlendTile);
  end;

  if bestErr < ATMI^.Error then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsBlended := True;
    ATMI^.TileIdx := -1;
    ATMI^.PalIdx := -1;
    ATMI^.Error := bestErr;
    ATMI^.Attrs.Alpha := bestAlpha;
    ATMI^.Attrs.Weight := bestWeight;
    ATMI^.Attrs.BlendBackBufferOffset := ABackBufferOffset;
  end;
end;

procedure TFrame.PredictTileMotion(ARadius, ABackBufferOffset, ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT;
  const ADCTs: TDCTDynArray; const APenaltyLUT: TCardinalDynArray);
var
  oy, yx, penLutMidOff, penLutWH: Integer;
  state: TDCTCribbleState;
  PrevDCTPtr: PDCTScalar;
begin
  state.Error := ATMI^.Error;
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

  if state.Error < ATMI^.Error then
  begin
    ATMI^.IsPredicted := True;
    ATMI^.IsBlended := False;
    ATMI^.TileIdx := -1;
    ATMI^.PalIdx := -1;
    ATMI^.Error := state.Error;
    ATMI^.Attrs.MotionY := state.Y - ADY;
    ATMI^.Attrs.MotionX := state.X - ADX;
    ATMI^.Attrs.MotionBackBufferOffset := ABackBufferOffset;
  end;
end;

procedure TFrame.PredictTileIntra(ADY, ADX: Integer; ATMI: PTileMapItem; const ADCT: TDCT; const ADCTs: TDCTDynArray);
var
  oy, ox, oymn, oymx, oxmn, oxmx, yx, bestX, bestY: Integer;
  bestErr: Cardinal;
  PSNRAcc: TFloat;
  PSNRIdx, PSNRCnt, err: Cardinal;
  PrevDCTPtr: PDCTScalar;
begin
  GetPredictExtents(High(ShortInt), ADY, ADX, oxmn, oxmx, oymn, oymx);

  bestErr := High(Cardinal);
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

      if err < bestErr then
      begin
        bestErr := err;
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
  ATMI^.TileIdx := -1;
  ATMI^.PalIdx := -1;
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
    CurCpnPixels: TCpnPixelsF;
    CurDCT: TDCT;
  begin
    DivMod(AIndex, Encoder.FTileMapWidth, sy, sx);

    TMI := @TileMap[sy, sx];
    FrameTile := FrameTiles[AIndex];

    Encoder.ConvertToCpnPixels(FrameTile^, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, CurCpnPixels);
    Encoder.ComputePsyVisFeatures(CurCpnPixels, pvsPSNRHVS, @CurDCT[0]);

    dx := sx shl cTileWidthBits;
    dy := sy shl cTileWidthBits;

    if ABackBufferOffset = 0 then
    begin
      PredictTileIntra(dy, dx, TMI, CurDCT, ADCTBuffer.GetBuffer)
    end
    else
    begin
      if Encoder.MotionPredictBlendingMode = bmAlphaWeight then
      begin
        if ABackBufferOffset >= 2 then
          PredictTileBlending(False, ABackBufferOffset - 1, dy, dx, TMI, CurDCT, CurCpnPixels, AFrameBuffer)
        else if (ABackBufferOffset = 1) and (Index = PKeyFrame.StartFrame + 1) then
          PredictTileBlending(True, ABackBufferOffset, dy, dx, TMI, CurDCT, CurCpnPixels, AFrameBuffer);
      end
      else if Encoder.MotionPredictBlendingMode = bmWeight then
      begin
        PredictTileBlending(True, ABackBufferOffset, dy, dx, TMI, CurDCT, CurCpnPixels, AFrameBuffer);
      end;

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

function TFrame.GRPSNR(x: Double; Data: Pointer): Double;
var
  sy, sx: Integer;
  errLimit: Cardinal;
  meanErr: UInt64;
  TMI: PTileMapItem;
begin
  errLimit := PSNRToEuclidean(x);

  meanErr := 0;
  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      TMI := @TileMap[sy, sx];

      if TMI^.Error < errLimit then
      begin
        TMI^.IsPredicted := True;
        meanErr += TMI^.Error
      end
      else
      begin
        TMI^.IsPredicted := False;
      end;
    end;

  Result := EuclideanToPSNR(meanErr div Encoder.FTileMapSize);
end;

procedure TFrame.SelectPredictions;
begin
  GoldenRatioSearch(@GRPSNR, 0.0, cBestPSNR, FrameTilesJPEGPSNR, cPSNRPrecision, 0.01, nil);
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
  i, j, col, ti, tyx: Integer;
  pcol: PInteger;
  FT: PTile;
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
          tyx := ((j and (cTileWidth - 1)) shl cTileWidthBits) + (i and (cTileWidth - 1));

          FT := FrameTiles[ti];

          FromRGB(col, FT^.Pixels[2, tyx], FT^.Pixels[1, tyx], FT^.Pixels[0, tyx]);
        end;
      end;
  end;

  // moderate the number of threads
  if Index >= Encoder.MaxThreadCount then
    WaitForSingleObject(Encoder.FFrames[Index - Encoder.MaxThreadCount].LoadFromImageFinishedEvent, INFINITE);

  TThread.ExecuteInThread(@DoAsyncLoadFromImage, Self);
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

      FrameTile := FrameTilesJPEG[yx];
      FrameTile^.BlitRGBPixels(ABuffer, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, dy, dx);

      Inc(yx);
    end;
  end;

begin
  AMTPool.DoLocalProc(@DoBlit, 0, Encoder.FTileMapHeight - 1);
end;

procedure TFrame.PredictedBlit(AMTPool: TMTPool; AFrameBuffer: TFrameBuffer);

  procedure DoBlit(AIndex: PtrInt; AData: Pointer);
  var
    sy, sx, dx, dy, ty, tx: Integer;
    errCml: UInt64;
    TMI: PTileMapItem;
    FrontBuf, BackBuf, M1Buf, M2Buf: TIntegerDynArray2;
    FrameTile: PTile;
  begin
    errCml := 0;

    sy := AIndex;
    dy := sy shl cTileWidthBits;

    FrontBuf := AFrameBuffer.GetBuffer;

    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      dx := sx shl cTileWidthBits;

      TMI := @TileMap[sy, sx];

      if TMI^.IsPredicted then
      begin
        // draw fb (motion predicted tile)

        if TMI^.IsBlended then
        begin
          M1Buf := AFrameBuffer.GetBuffer(-TMI^.Attrs.BlendBackBufferOffset);
          M2Buf := AFrameBuffer.GetBuffer(-TMI^.Attrs.BlendBackBufferOffset - 1);
          for ty := 0 to cTileWidth - 1 do
          begin
            for tx := 0 to cTileWidth - 1 do
            begin
              FrontBuf[dy, dx] := BlendRGB(M1Buf[dy, dx], M2Buf[dy, dx], TMI^.Attrs.Alpha, TMI^.Attrs.Weight, CGTMBlendAlphaShift, CGTMBlendWeightBaseShift);
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
        // draw fb (plain tile)

        FrameTile := FrameTilesJPEG[sy * Encoder.FTileMapWidth + sx];
        FrameTile^.BlitRGBPixels(FrontBuf, FrameTile^.VMirror_Initial, FrameTile^.HMirror_Initial, dy, dx);
      end;

      errCml += TMI^.Error;
    end;

    SpinEnter(@PKeyFrame.ReconstructLock);
    PKeyFrame.ReconstructErrCml += errCml;
    SpinLeave(@PKeyFrame.ReconstructLock);
  end;

begin
  AMTPool.DoLocalProc(@DoBlit, 0, Encoder.FTileMapHeight - 1);
end;

function TFrame.PrepareInterFrameData: TFloatDynArray;
var
  sy, sx, tyx, sz, di: Integer;
  l, a, b, invSize: TFloat;
  FT: PTile;
begin
  Result := nil;
  sz := Encoder.FTileMapSize;

  SetLength(Result, sz * cColorCpns);

  invSize := 1 / Sqr(cTileWidth);
  di := 0;
  for sy := 0 to Encoder.FTileMapHeight - 1 do
    for sx := 0 to Encoder.FTileMapWidth - 1 do
    begin
      FT := FrameTiles[sy * Encoder.FTileMapWidth + sx];

      for tyx := 0 to Sqr(cTileWidth) - 1 do
      begin
        RGBToLAB(FT^.Pixels[0, tyx], FT^.Pixels[1, tyx], FT^.Pixels[2, tyx], l, a, b);
        Result[di + 0] += l;
        Result[di + 1] += a;
        Result[di + 2] += b;
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
  errAcc: UInt64;
  Tile: PTile;
  TMI: PTileMapItem;
  prevFrameICD: TFloatDynArray;
  Img: TRGBTiledImg;
  JPEGTiles: PTileDynArray;
  JPEGWr: TMyWriterJPEG;
  JPEGRd: TFPReaderJPEG;
  CpnPixels: TCpnPixelsF;
  PlainDCT, JPEGDCT: TDCT;
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

  // Use JPEG to devise FrameTile target error (PSNR-HVS)

  Img := TRGBTiledImg.Create(Encoder.ScreenWidth, Encoder.ScreenHeight);
  JPEGTiles := TTile.Array1DNew(Encoder.FTileMapSize);
  JPEGWr := TMyWriterJPEG.Create;
  JPEGRd := TFPReaderJPEG.Create;
  try
    Img.Image := FrameTiles;
    Img.TileStride := Encoder.FTileMapWidth;

    JPEGWr.CompressionQuality := Encoder.ReduceQuality;
    JPEGWr.ProgressiveEncoding := False;
    JPEGWr.ChromaSubsampling := False;
    Img.SaveToStream(FrameTilesJPEGStream, JPEGWr);

    JPEGRd.Performance := jpBestQuality;
    Img.Image := JPEGTiles;
    FrameTilesJPEGStream.Seek(0, soBeginning);
    Img.LoadFromStream(FrameTilesJPEGStream, JPEGRd);

    errAcc := 0;
    for i := 0 to Encoder.FTileMapSize - 1 do
    begin
      Tile := JPEGTiles[i];
      Encoder.ConvertToCpnPixels(Tile^, False, False, CpnPixels);
      Encoder.ComputePsyVisFeatures(CpnPixels, pvsPSNRHVS, JPEGDCT);

      Tile := FrameTiles[i];
      Encoder.ConvertToCpnPixels(Tile^, False, False, CpnPixels);
      Encoder.ComputePsyVisFeatures(CpnPixels, pvsPSNRHVS, PlainDCT);

      Tile^.JPEGError := CompareEuclideanDCTPtr_asm(@PlainDCT[0], @JPEGDCT[0]);

      errAcc += Tile^.JPEGError;
    end;
    FrameTilesJPEGPSNR := EuclideanToPSNR(errAcc div Encoder.FTileMapSize);
  finally
    JPEGRd.Free;
    JPEGWr.Free;
    TTile.Array1DDispose(JPEGTiles);
    Img.Free;
  end;

  // also handle tilemap H/V mirrors

  for i := 0 to Encoder.FTileMapSize - 1 do
  begin
    Tile := FrameTiles[i];
    TMI := @TileMap[i div Encoder.FTileMapWidth, i mod Encoder.FTileMapWidth];

    Encoder.GetTileHVMirrorHeuristics(Tile^, -1, HMirror, VMirror);

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
  frmIdx, frmCnt, startFrmIdx: Integer;
  fn: String;
  bmp: TPicture;
  manualKeyFrames: Boolean;
  FFMPEG: TFFMPEG;
begin
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
        frmCnt := Max(0, frmCnt - FStartFrame);
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

  ProgressRedraw(4, 'FindKeyFrames');

  WriteLn(GetSettings);

  ProgressRedraw(5, 'PrintSettings');
end;

procedure TTilingEncoder.PredictMotion;
var
  frmIdx, kfIdx, frmRelIdx, iBuf: Integer;
  isKFFF: Boolean;
  Frame: TFrame;
  FrameBuffer: TFrameBuffer;
  DCTBuffer: TDCTBuffer;
  MTPool: TMTPool;
begin
  if (Length(FFrames) = 0) or (FMotionPredictRadius <= 0) then
    Exit;

  ProgressRedraw(0, '', esPredict);

  // init for LogPSNR
  FKeyFramesLeft := Length(FKeyFrames);
  for kfIdx := 0 to High(FKeyFrames) do
  begin
    FKeyFrames[kfIdx].ReconstructErrCml := 0;
    FKeyFrames[kfIdx].ReconstructFramesLeft := FKeyFrames[kfIdx].FrameCount;
  end;

  MTPool := TMTPool.Create(MaxThreadCount);
  FrameBuffer := TFrameBuffer.Create(FMotionPredictMaxBufferedFrames + 1, FScreenHeight, FScreenWidth);
  DCTBuffer := TDCTBuffer.Create(FMotionPredictMaxBufferedFrames, (FScreenHeight - cTileWidth + 1) * (FScreenWidth - cTileWidth + 1));
  try
    for frmIdx := 0 to High(FFrames) do
    begin
      Frame := FFrames[frmIdx];

      isKFFF := Frame.Index = Frame.PKeyFrame.StartFrame;
      frmRelIdx := Frame.Index - Frame.PKeyFrame.StartFrame;

      Frame.ResetTileMap(True);

      Frame.AcquireFrameTiles;
      try
        if isKFFF then
        begin
          Frame.DirectBlit(MTPool, FrameBuffer.GetBuffer);
          Frame.PrepareDCTs(MTPool, DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
        end
        else
        begin
          for iBuf := 1 to Min(FMotionPredictMaxBufferedFrames, frmRelIdx) do
            Frame.Predict(MTPool, FMotionPredictRadius, iBuf, DCTBuffer, FrameBuffer);
          Frame.SelectPredictions;

          Frame.PredictedBlit(MTPool, FrameBuffer);
          Frame.PrepareDCTs(MTPool, DCTBuffer.GetBuffer, FrameBuffer.GetBuffer);
        end;

        TransferTiles(Frame);
      finally
        Frame.ReleaseFrameTiles;
      end;

      DCTBuffer.AdvanceFrame;
      FrameBuffer.AdvanceFrame;

      Frame.PKeyFrame.LogPSNR;

      Write(frmIdx + 1:8, ' / ', Length(FFrames):8, #13);
    end;

    ProgressRedraw(1, 'PredictMotion');
  finally
    DCTBuffer.Free;
    FrameBuffer.Free;
    MTPool.Free;
  end;
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
  frmIdx, sx, sy: Integer;
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

        HandleTileIndex(TMI^.TileIdx);
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

  ProgressRedraw(cEncoderStepLen[esLoad], 'ReloadGTM');
end;

procedure TTilingEncoder.GeneratePNGs(AInput: Boolean);
var
  palPict: TPortableNetworkGraphic;
  frmIdx: Integer;
  page: TRenderPage;
  BMP: TBitmap;
begin
  palPict := TFastPortableNetworkGraphic.Create;

  palPict.Width := FScreenWidth;
  palPict.Height := FScreenHeight;
  palPict.PixelFormat := pf24bit;

  try
    page := rpOutput;
    BMP := FOutputBitmap;
    if AInput then
    begin
      page := rpInput;
      BMP := FInputBitmap;
    end;

    for frmIdx := 0 to High(FFrames) do
    begin
      RenderFrame(frmIdx, page);

      palPict.Canvas.Draw(0, 0, BMP);
      palPict.SaveToFile(Format('%s_%.4d.png', [ChangeFileExt(FOutputFileName, ''), frmIdx]));
    end;
  finally
    palPict.Free;

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
    Header := Format('YUV4MPEG2 W%d H%d F%d:1000000 Ip C444 XCOLORRANGE=FULL'#10, [FTileMapWidth * cTileWidth, FTileMapHeight * cTileWidth, round(FFramesPerSecond * 1000000)]);
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

function TTilingEncoder.GetRenderTilePageCount: Integer;
begin
  Result := (Length(FTiles) - 1) div FTileMapSize + 1;
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
      fs.Write(ASettings[1], Length(ASettings));
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

function TTilingEncoder.GetFrameTileCount(AFrame: TFrame): Integer;
var
  Used: TByteDynArray;
  sx, sy: Integer;
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

      if TMI^.TileIdx >= 0 then
        Used[TMI^.TileIdx] := 1;
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

procedure TTilingEncoder.SetMaxThreadCount(AValue: Integer);
begin
 if FMaxThreadCount = AValue then Exit;
 FMaxThreadCount := max(1, AValue);
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

procedure TTilingEncoder.SetRenderOutputJPEG(AValue: Boolean);
begin
  if FRenderOutputJPEG = AValue then Exit;
  FRenderOutputJPEG := AValue;
  FRenderOutputDirty := True;
end;

procedure TTilingEncoder.SetRenderPage(AValue: TRenderPage);
begin
  if FRenderPage = AValue then Exit;
  FRenderPage := AValue;
  FRenderOutputDirty := FRenderOutputDirty or ((AValue = rpOutput) and not InRange(FRenderFrameIndex, FRenderOuptutFrameIndex, FRenderOuptutFrameIndex + 1));
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

procedure TTilingEncoder.SetReduceQuality(AValue: Integer);
begin
  if FReduceQuality = AValue then Exit;
  FReduceQuality := EnsureRange(AValue, Low(TMyJPEGCompressionQuality), High(TMyJPEGCompressionQuality));
end;

procedure TTilingEncoder.SetMotionPredictRadius(AValue: Integer);
begin
  if FMotionPredictRadius = AValue then Exit;
  FMotionPredictRadius := EnsureRange(AValue, 0, -Low(ShortInt));
end;

procedure TTilingEncoder.SetMotionPredictMaxBufferedFrames(AValue: Integer);
begin
  if FMotionPredictMaxBufferedFrames = AValue then Exit;
  FMotionPredictMaxBufferedFrames := EnsureRange(AValue, 1, 4);
end;

class procedure TTilingEncoder.ConvertToCpnPixels(const ATile: TTile; VMirror, HMirror: Boolean; out ACpnPixel: TCpnPixelsF);

  procedure ToCpn(col, yx: Integer);
  var
    r, g, b: Byte;
  begin
    FromRGB(col, r, g, b);
    RGBToYUV(r, g, b, ACpnPixel[0, yx], ACpnPixel[1, yx], ACpnPixel[2, yx], cDCTScale);
  end;

var
  iCpn, x, y, yx, xx, yy, yyxx: Integer;
begin
  for iCpn := 0 to cColorCpns - 1 do
  begin
    yx := 0;
    for y := 0 to (cTileWidth - 1) do
      for x := 0 to (cTileWidth - 1) do
      begin
        xx := x;
        yy := y;
        if HMirror then xx := cTileWidth - 1 - x;
        if VMirror then yy := cTileWidth - 1 - y;

        yyxx := (yy shl cTileWidthBits) + xx;

        ACpnPixel[iCpn, yx] := ATile.Pixels[iCpn, yyxx];

        Inc(yx);
      end;
  end;
end;

procedure TTilingEncoder.ComputePsyVisFeatures(const ACpnPixels: TCpnPixelsF; Mode: TPsyVisMode; ADCT: PDCTScalar);
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
  for cpn := 0 to cColorCpns - 1 do
    for v := 0 to cTileWidth - 1 do
      for u := 0 to cTileWidth - 1 do
      begin
  		  z := DCTInner_asm(@ACpnPixels[cpn, 0], pLut);
        pDCT[pSnake^] := Round(z);
        Inc(pLut, Sqr(cTileWidth));
        Inc(pSnake);
      end;
end;

class procedure TTilingEncoder.VMirrorTile(var ATile: TTile);
var
  iCpn, j, i, ji, rji: Integer;
  v, sv: Integer;
begin
  // hardcode vertical mirror into the tile

  for iCpn := 0 to cColorCpns - 1  do
    for j := 0 to cTileWidth div 2 - 1  do
      for i := 0 to cTileWidth - 1 do
      begin
        ji := (j shl cTileWidthBits) + i;
        rji := ((cTileWidth - 1 - j) shl cTileWidthBits) + i;
        v := ATile.Pixels[iCpn, ji];
        sv := ATile.Pixels[iCpn, rji];
        ATile.Pixels[iCpn, ji] := sv;
        ATile.Pixels[iCpn, rji] := v;
      end;
end;

class procedure TTilingEncoder.HMirrorTile(var ATile: TTile);
var
  iCpn, i, j, ji, jri: Integer;
  v, sv: Integer;
begin
  // hardcode horizontal mirror into the tile

  for iCpn := 0 to cColorCpns - 1  do
    for j := 0 to cTileWidth - 1 do
      for i := 0 to cTileWidth div 2 - 1  do
      begin
        ji := (j shl cTileWidthBits) + i;
        jri := (j shl cTileWidthBits) + cTileWidth - 1 - i;
        v := ATile.Pixels[iCpn, ji];
        sv := ATile.Pixels[iCpn, jri];
        ATile.Pixels[iCpn, ji] := sv;
        ATile.Pixels[iCpn, jri] := v;
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
const
  CDummyTilesColor = $303030;
  CDrawPredictBaseLuma = $d0;

  procedure DrawTile(const ABuffer: TIntegerDynArray2; ATilePtr: PTile; ASY, ASX: Integer; AHmirror, AVmirror, AForceActive: Boolean); inline;
  var
    col, tx, ty, txm, tym, tyxm: Integer;
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

        tyxm := (tym shl cTileWidthBits) + txm;

        col := $ff00ff;
        if ATilePtr^.Active or AForceActive then
          col := ToRGB(ATilePtr^.Pixels[0, tyxm], ATilePtr^.Pixels[1, tyxm], ATilePtr^.Pixels[2, tyxm]);

        psl^ := col;
        Inc(psl);
      end;
    end;
  end;

  procedure DrawDummyTile(const ABuffer: TIntegerDynArray2; ASY, ASX: Integer; AColor: Integer = CDummyTilesColor);
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
  sx, sy, globalTileCount, col, off, siz: Integer;
  hmir, vmir: Boolean;
  tidx: Int64;
  errCml: UInt64;
  pFB: PInteger;
  TempTile, tilePtr: PTile;
  TempBuf: TIntegerDynArray2;
  TMI: PTileMapItem;
  Frame: TFrame;
  canvas: TCanvas;
begin
  if (APage = rpInput) and (Length(FFrames) <= 0) then
  begin
    FInputBitmap.Canvas.Brush.Color := clBlack;
    FInputBitmap.Canvas.Brush.Style := bsSolid;
    FInputBitmap.Canvas.FillRect(FInputBitmap.Canvas.ClipRect);
    FInputBitmap.Canvas.Brush.Color := CDummyTilesColor;
    FInputBitmap.Canvas.Brush.Style := bsDiagCross;
    FInputBitmap.Canvas.FillRect(FInputBitmap.Canvas.ClipRect);
  end
  else if (APage = rpOutput) and (Length(FFrames) <= 0) then
  begin
    FOutputBitmap.Canvas.Brush.Color := clBlack;
    FOutputBitmap.Canvas.Brush.Style := bsSolid;
    FOutputBitmap.Canvas.FillRect(FOutputBitmap.Canvas.ClipRect);
    FOutputBitmap.Canvas.Brush.Color := CDummyTilesColor;
    FOutputBitmap.Canvas.Brush.Style := bsDiagCross;
    FOutputBitmap.Canvas.FillRect(FOutputBitmap.Canvas.ClipRect);
  end
  else if APage = rpTiles then
  begin
    FTilesBitmap.Canvas.Brush.Color := clAqua;
    FTilesBitmap.Canvas.Brush.Style := bsSolid;
    FTilesBitmap.Canvas.FillRect(FTilesBitmap.Canvas.ClipRect);
  end;

  if Length(FFrames) <= 0 then
    Exit;

  Frame := FFrames[AFrameIndex];

  if not Assigned(Frame) or not Assigned(Frame.PKeyFrame) then
    Exit;

  TempTile := TTile.New;
  SetLength(TempBuf, cTileWidth, cTileWidth);
  try

    // Global

    globalTileCount := GetTileCount(False);

    FRenderTitleText := Format('Global: %12d / Frame #%8d %s: %8d', [globalTileCount, Frame.Index, IfThen(Frame.PKeyFrame.StartFrame = Frame.Index, '[KF]', '    '), Frame.GetUsedTileCount]);

    // "Input" tab

    if APage = rpInput then
    begin
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

            DrawTile(TempBuf, tilePtr, 0, 0, hmir, vmir, True);

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
      if Frame.Index = FRenderOuptutFrameIndex + 1 then
        FRenderFrameBuffer.AdvanceFrame;

      for sy := 0 to FTileMapHeight - 1 do
        for sx := 0 to FTileMapWidth - 1 do
        begin
          TMI := @Frame.TileMap[sy, sx];

          if TMI^.IsPredicted then
          begin
            if TMI^.IsBlended then
              TempTile^.BlendRGBPixels(
                FRenderFrameBuffer.GetBuffer(-TMI^.Attrs.BlendBackBufferOffset),
                FRenderFrameBuffer.GetBuffer(-TMI^.Attrs.BlendBackBufferOffset - 1),
                sy shl cTileWidthBits,
                sx shl cTileWidthBits,
                TMI^.Attrs.Alpha, TMI^.Attrs.Weight)
            else
              TempTile^.CopyRGBPixels(
                FRenderFrameBuffer.GetBuffer(-TMI^.Attrs.MotionBackBufferOffset),
                (sy shl cTileWidthBits) + TMI^.Attrs.MotionY,
                (sx shl cTileWidthBits) + TMI^.Attrs.MotionX);

            DrawTile(FRenderFrameBuffer.GetBuffer, TempTile, sy, sx, False, False, True)
          end
          else if InRange(TMI^.TileIdx, 0, High(Tiles)) then
          begin
            tilePtr := FTiles[TMI^.TileIdx];

            hmir := TMI^.HMirror;
            vmir := TMI^.VMirror;

            if not FRenderMirrored then
            begin
              hmir := False;
              vmir := False;
            end;

            DrawTile(FRenderFrameBuffer.GetBuffer, tilePtr, sy, sx, hmir, vmir, False);
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

            if TMI^.IsSmoothed then
            begin
              canvas.Brush.Color := clWhite;
              canvas.FrameRect(
                (sx shl cTileWidthBits) - 3 + off, (sy shl cTileWidthBits) - 3 + off,
                (sx shl cTileWidthBits) + 3 + off, (sy shl cTileWidthBits) + 3 + off);
            end
            else if TMI^.IsBlended then
            begin
              if TMI^.Attrs.Alpha <> 0 then
              begin
                siz := TMI^.Attrs.Alpha + Abs(TMI^.Attrs.Weight);
                col := Max(0, CDrawPredictBaseLuma - siz);
                col := ToRGB($ff, $ff, col);
              end
              else
              begin
                siz := Abs(TMI^.Attrs.Weight) shl 1;
                col := Max(0, CDrawPredictBaseLuma - siz);
                col := ToRGB(col, $ff, col);
              end;

              canvas.Brush.Color := col;
              canvas.FillRect(
                (sx shl cTileWidthBits) - 2 + off, (sy shl cTileWidthBits) - 2 + off,
                (sx shl cTileWidthBits) + 2 + off, (sy shl cTileWidthBits) + 2 + off);
            end
            else if TMI^.IsMotion then
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

      FRenderOutputDirty := False;
      FRenderOuptutFrameIndex := Frame.Index;
    end;

    // "Tiles" tab

    if APage = rpTiles then
    begin
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

              DrawTile(TempBuf, tilePtr, 0, 0, hmir, vmir, False);

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
  frmIdx, sf: Integer;
begin
  if not FRenderOutputDirty or (FRenderPage <> rpOutput) or not Assigned(FFrames) then
  begin
    RenderFrame(FRenderFrameIndex, FRenderPage)
  end
  else
  begin
    frmIdx := EnsureRange(FRenderFrameIndex, 0, High(FFrames));
    sf := FFrames[frmIdx].PKeyFrame.StartFrame;
    if (FRenderOuptutFrameIndex < FRenderFrameIndex) and InRange(FRenderOuptutFrameIndex, sf, FFrames[frmIdx].PKeyFrame.EndFrame) then
      sf := FRenderOuptutFrameIndex;
    for frmIdx := sf to frmIdx do
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
    ini.WriteInteger('MotionPredict', 'MotionPredictBlendingMode', Ord(MotionPredictBlendingMode));

    ini.WriteInteger('Reduce', 'ReduceQuality', ReduceQuality);

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
    MotionPredictBlendingMode := TBlendingMode(EnsureRange(ini.ReadInteger('MotionPredict', 'MotionPredictBlendingMode', Ord(MotionPredictBlendingMode)), Ord(Low(TBlendingMode)), Ord(High(TBlendingMode))));

    ReduceQuality := ini.ReadInteger('Reduce', 'ReduceQuality', ReduceQuality);

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

  MotionPredictRadius := 64;
  MotionPredictMaxBufferedFrames := 3;
  MotionPredictBlendingMode := bmAlphaWeight;

  ReduceQuality := 80;

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
  i, rng: Integer;
  rr, gg, bb: Byte;
  l, a, b, y, u, v: TFloat;
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

  FRenderOutputDirty := True;

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

procedure TTilingEncoder.TransferTiles(AFrame: TFrame);
var
  tileCount, newTIdx, sx, sy: Integer;
  Tile: PTile;
  TMI: PTileMapItem;
begin
  tileCount := Length(FTiles) + AFrame.GetUnpredictedTileCount;
  newTIdx := Length(FTiles);

  if not Assigned(FTiles) then
    FTiles := TTile.Array1DNew(tileCount)
  else
    TTile.Array1DRealloc(FTiles, tileCount);

  for sy := 0 to FTileMapHeight - 1 do
    for sx := 0 to FTileMapWidth - 1 do
    begin
      TMI := @AFrame.TileMap[sy, sx];

      if not TMI^.IsPredicted then
      begin
        Tile := Tiles[newTIdx];
        Tile^.CopyFrom(AFrame.FrameTilesJPEG[sy * FTileMapWidth + sx]^);

        TMI^.TileIdx := newTIdx;

        if TMI^.HMirror then HMirrorTile(Tile^);
        if TMI^.VMirror then VMirrorTile(Tile^);

        Inc(newTIdx);
      end
      else
      begin
        TMI^.TileIdx := -1;
      end;
    end;

  Assert(newTIdx = tileCount);
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

        Remap(TMI^.TileIdx);
      end;
  end;

  // cleanup

  for tIdx := 0 to High(FTiles) do
    FTiles[tIdx]^.TmpIndex := -1;

  WriteLn('ReindexTiles: ', Length(Tiles):12, ' / ', Length(FFrames) * FTileMapSize:12,  ' reindexed tiles, (', Length(Tiles) * 100.0 / (Length(FFrames) * FTileMapSize):4:3, '%)');
end;

function CompareTileRawPixels(Item1, Item2:Pointer):Integer;
var
  t1, t2: PTile;
begin
  t1 := PTile(Item1);
  t2 := PTile(Item2);
  Result := t1^.CompareRawPixelsTo(t2^);
end;

procedure TTilingEncoder.MakeTilesUnique;
var
  sortListIdx, pos, firstSameIdx: Integer;
  sortList: TFPList;
  sameIdx: TIntegerDynArray;

  procedure DoOneMerge;
  var
    j: Integer;
  begin
    if sortListIdx - firstSameIdx >= 2 then
    begin
      for j := firstSameIdx to sortListIdx - 1 do
        sameIdx[j - firstSameIdx] := PTile(sortList[j])^.TmpIndex;
      MergeTiles(sameIdx, sortListIdx - firstSameIdx, sameIdx[0]);
    end;
    firstSameIdx := sortListIdx;
  end;

var
  tIdx: Integer;
begin
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

    sortList.Sort(@CompareTileRawPixels);

    // merge exactly similar tiles (so, consecutive after prev code)

    firstSameIdx := 0;
    for sortListIdx := 1 to sortList.Count - 1 do
      if CompareTileRawPixels(sortList[sortListIdx - 1], sortList[sortListIdx]) <> 0 then
        DoOneMerge;

    sortListIdx := sortList.Count;
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

class function TTilingEncoder.GetTileZoneSum(const ATile: TTile; ACpn, x, y, w, h: Integer): Integer;
var
  i, j, ji: Integer;
begin
  Result := 0;

  if ACpn < 0 then
  begin
    for j := y to y + h - 1 do
      for i := x to x + w - 1 do
      begin
        ji := (j shl cTileWidthBits) + i;
        Result += ToLuma(ATile.Pixels[0, ji], ATile.Pixels[1, ji], ATile.Pixels[2, ji]);
      end;
  end
  else
  begin
    for j := y to y + h - 1 do
      for i := x to x + w - 1 do
      begin
        ji := (j shl cTileWidthBits) + i;
        Result += ATile.Pixels[ACpn, ji];
      end;
  end;
end;

class procedure TTilingEncoder.GetTileHVMirrorHeuristics(const ATile: TTile; ACpn: Integer; out AHMirror, AVMirror: Boolean);
var
  q00, q01, q10, q11: Integer;
begin
  // enforce an heuristical 'spin' on tiles mirrors (brighter top-left corner)

  q00 := GetTileZoneSum(ATile, ACpn, 0, 0, cTileWidth div 2, cTileWidth div 2);
  q01 := GetTileZoneSum(ATile, ACpn, cTileWidth div 2, 0, cTileWidth div 2, cTileWidth div 2);
  q10 := GetTileZoneSum(ATile, ACpn, 0, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);
  q11 := GetTileZoneSum(ATile, ACpn, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2, cTileWidth div 2);

  AHMirror := q00 + q10 < q01 + q11;
  AVMirror := q00 + q01 < q10 + q11;
end;

procedure TTilingEncoder.LoadStream(AStream: TStream);
var
  KFStream: TMemoryStream;
  frmIdx, kfIdx, loadedFrmCount: Integer;
  curKFPSNRError: Cardinal;
  rawTileIdxToTileIdx: array[Boolean{is kf?}] of TIntegerDynArray;
  kfPSNRs: TDoubleDynArray;

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
    WriteLn(settings);
    SetSettings(settings);
  end;

  procedure ReadTiles(isKF, isNibbleCoded: Boolean);
  var
    iRawTile, rawStartIdx, rawEndIdx, baseTileIdx, tileIdx, tileCnt, ty, tx: Integer;
    b: Byte;
    T: PTile;
  begin
    //rawStartIdx := ReadDWord; // start tile
    //rawEndIdx := ReadDWord; // end tile
    //
    //baseTileIdx := Length(FTiles);
    //tileCnt := rawEndIdx - rawStartIdx + 1;
    //
    //if baseTileIdx > 0 then
    //  TTile.Array1DRealloc(FTiles, Length(FTiles) + tileCnt)
    //else
    //  FTiles := TTile.Array1DNew(tileCnt, True, True);
    //
    //for iRawTile := rawStartIdx to rawEndIdx do
    //begin
    //  tileIdx := baseTileIdx + iRawTile - rawStartIdx;
    //
    //  FTiles[tileIdx]^.PalIdx := ReadWord;
    //  FTiles[tileIdx]^.Active := True;
    //  rawTileIdxToTileIdx[isKF, iRawTile] := tileIdx;
    //end;
    //
    //for iRawTile := rawStartIdx to rawEndIdx do
    //begin
    //  tileIdx := baseTileIdx + iRawTile - rawStartIdx;
    //
    //  if isNibbleCoded then
    //  begin
    //    T := FTiles[tileIdx];
    //    for ty := 0 to cTileWidth - 1 do
    //      for tx := 0 to cTileWidth - 1 do
    //        if not Odd(tx) then
    //        begin
    //          b := ReadByte;
    //          T^.PalPixels[ty, tx] := b and 15;
    //          T^.PalPixels[ty, tx + 1] := (b shr 4) and 15;
    //        end;
    //  end
    //  else
    //  begin
    //    KFStream.Read(FTiles[tileIdx]^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
    //  end;
    //end;
  end;

  procedure ReadDimensions;
  var
    w, h, frmLen, tileCount: Integer;
  begin
    w := ReadDWord; // frame tilemap width
    h := ReadDWord; // frame tilemap height
    ReframeUI(w, h);

    frmLen := ReadDWord; // frame length in nanoseconds
    FFramesPerSecond := 1000*1000*1000 / frmLen;

    tileCount := ReadDWord; // global tile count
    SetLength(rawTileIdxToTileIdx[False], tileCount);

    tileCount := ReadDWord; // maximum key frame tile count
    SetLength(rawTileIdxToTileIdx[True], tileCount);
  end;

  procedure ReadPalette(palSize: Integer);
  var
    i, palIdx: Integer;
  begin
    //palIdx := ReadWord;
    //
    //if Length(FPalettes) <= palIdx then
    //begin
    //  SetLength(FPalettes, palIdx + 1);
    //  for i := 0 to palIdx do
    //    SetLength(FPalettes[i].PaletteRGB, palSize);
    //
    //  FPaletteCount := Length(FPalettes);
    //end;
    //
    //for i := 0 to palSize - 1 do
    //  FPalettes[palIdx].PaletteRGB[i] := ReadDWord and $ffffff;
    //
    //FPaletteSize := palSize;
  end;

  procedure SetTMI(tileIdx, palIdx: Integer; attrs: Integer; var TMI: TTileMapItem);
  begin
    //TMI.TileIdx := tileIdx;
    //TMI.PalIdx := palIdx;
    //if palIdx < 0 then
    //  TMI.PalIdx := FTiles[tileIdx]^.PalIdx;
    //TMI.HMirror := attrs and 1 <> 0;
    //TMI.VMirror := attrs and 2 <> 0;
    //
    //TMI.IsPredicted := False;
    //TMI.IsBlended := False;
    //
    //TMI.Error := curKFPSNRError;
  end;

  function NextFrame(KF: TKeyFrame): TFrame;
  begin
    Inc(frmIdx);
    Result := TFrame.Create(Self, frmIdx);
    Result.PKeyFrame := kf;

    Result.FrameTiles := TTile.Array1DNew(FTileMapSize);
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

    FKeyFrames[kfIdx].ReconstructPSNR := kfPSNRs[kfIdx];
    curKFPSNRError := PSNRToEuclidean(kfPSNRs[kfIdx]);
  end;

  procedure SkipBlock(frm: TFrame; SkipCount: Integer; var tmPos: Integer);
  var
    i: Integer;
    sx, sy: Integer;
    TMI: PTileMapItem;
  begin
    Assert(frm.Index > 0);
    for i := tmPos to tmPos + SkipCount - 1 do
    begin
      DivMod(i, FTileMapWidth, sy, sx);
      TMI := @frm.TileMap[sy, sx];

      TMI^.IsPredicted := True;
      TMI^.IsBlended := False;
      TMI^.Attrs.MotionX := 0;
      TMI^.Attrs.MotionY := 0;
      TMI^.Attrs.MotionBackBufferOffset := 1;

      TMI^.Error := curKFPSNRError;
    end;
    tmPos += SkipCount;
  end;

var
  Header: TGTMHeader;
  KFInfo: TGTMKeyFrameInfo;
  Command, prevCommand: TGTMCommand;
  CommandData: Word;
  b: Byte;
  tmPos, iKF: Integer;
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
    if Header.EncoderVersion <> 6 then
      raise ETilingEncoderGTMReloadError.Create('Can only reload GTM files made with current version!');

    SetLength(FKeyFrames, Header.KFCount);
    SetLength(FFrames, Header.FrameCount);

    SetLength(kfPSNRs, Length(FKeyFrames));
    FReconstructPSNR := Header.PSNRHVS / (1000.0 * 1000.0);
    for iKF := 0 to High(FKeyFrames) do
    begin
      AStream.ReadBuffer(KFInfo, SizeOf(KFInfo));
      kfPSNRs[iKF] := KFInfo.PSNRHVS / (1000.0 * 1000.0);
    end;
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
            ReadTiles((CommandData and 1) <> 0, (CommandData and 2) <> 0);
          end;
          gtLoadPalette:
          begin
            ReadPalette((CommandData and 63) + 1);
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
          gtPredictedOffsetBlock0x0:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            SkipBlock(frm, CommandData + 1, tmPos);
          end;
          gtGlobalTile16, gtGlobalTile32,
          gtKeyFrmTile16, gtKeyFrmTile32:
          begin
            if Command in [gtGlobalTile16, gtKeyFrmTile16] then
              tileIdx := ReadWord
            else
              tileIdx := ReadDWord;

            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            tileIdx := rawTileIdxToTileIdx[Command in [gtKeyFrmTile16, gtKeyFrmTile32], tileIdx];

            SetTMI(tileIdx, -1, CommandData, frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth]);
            Inc(tmPos);
          end;
          gtPalTile:
          begin
            tileIdx := ReadDWord;
            palIdx := ReadWord;

            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            tileIdx := rawTileIdxToTileIdx[(CommandData and 4) <> 0, tileIdx];

            SetTMI(tileIdx, palIdx, CommandData and 3, frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth]);
            Inc(tmPos);
          end;
          gtPredictedTileOffsets6x6:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];

            TMI^.Attrs.MotionY := ((CommandData shr 6) and 31) - ((CommandData shr 6) and 32);
            TMI^.Attrs.MotionX := (CommandData and 31) - (CommandData and 32);
            TMI^.Attrs.MotionBackBufferOffset := 1;
            TMI^.IsPredicted := True;
            TMI^.IsBlended := False;
            TMI^.Error := curKFPSNRError;

            Inc(tmPos);
          end;
          gtPredictedTileOffsets8x8:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];

            b := ReadByte;
            TMI^.Attrs.MotionX := (b and 127) - (b and 128);
            b := ReadByte;
            TMI^.Attrs.MotionY := (b and 127) - (b and 128);
            TMI^.Attrs.MotionBackBufferOffset := (CommandData and 3) + 1;
            TMI^.IsPredicted := True;
            TMI^.IsBlended := False;
            TMI^.Error := curKFPSNRError;

            Inc(tmPos);
          end;
          gtPredictedTileBlending8x8:
          begin
            // next frame if needed
            if frm = nil then
              frm := NextFrame(kf);

            TMI := @frm.TileMap[tmPos div FTileMapWidth, tmPos mod FTileMapWidth];

            b := ReadByte;
            TMI^.Attrs.Weight := (b and 127) - (b and 128);
            TMI^.Attrs.Alpha := ReadByte;
            TMI^.Attrs.BlendBackBufferOffset := (CommandData and 3) + 1;
            TMI^.IsPredicted := True;
            TMI^.IsBlended := True;
            TMI^.Error := curKFPSNRError;

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
  FRenderOutputDirty := True;
end;

function CompareTileIdxsUseCountHSVPixels(Item1, Item2, UserParameter:Pointer):Integer;
var
  Encoder: TTilingEncoder absolute UserParameter;
  t1, t2: PTile;
begin
  t1 := Encoder.FTiles[PInteger(Item1)^];
  t2 := Encoder.FTiles[PInteger(Item2)^];

  Result := CompareValue(t2^.UseCount, t1^.UseCount);

  if Result = 0 then
    Result := t1^.CompareHSVPixelsTo(t2^);
end;

function CompareTileIdxsHSVPixels(Item1, Item2, UserParameter:Pointer):Integer;
var
  Encoder: TTilingEncoder absolute UserParameter;
  t1, t2: PTile;
begin
  t1 := Encoder.FTiles[PInteger(Item1)^];
  t2 := Encoder.FTiles[PInteger(Item2)^];

  Result := t1^.CompareHSVPixelsTo(t2^);
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
    finalTileIdx: Integer;
    attrs: Word;
    isLongOffsets, isKeyFrameTile, isTile32, isPalTile: Boolean;
  begin
    if TMI.IsBlended then
    begin
      DoCmd(gtPredictedTileBlending8x8, TMI.Attrs.BlendBackBufferOffset - 1);
      DoByte(PByte(@TMI.Attrs.Weight)^);
      DoByte(TMI.Attrs.Alpha);
    end
    else if TMI.IsMotion then
    begin
      isLongOffsets := not InRange(TMI.Attrs.MotionX, -32, 31) or not InRange(TMI.Attrs.MotionY, -32, 31) or (TMI.Attrs.MotionBackBufferOffset > 1);

      if isLongOffsets then
      begin
        DoCmd(gtPredictedTileOffsets8x8, TMI.Attrs.MotionBackBufferOffset - 1);
        DoByte(PByte(@TMI.Attrs.MotionX)^);
        DoByte(PByte(@TMI.Attrs.MotionY)^);
      end
      else
      begin
        attrs := (PByte(@TMI.Attrs.MotionX)^ and 63) or ((PByte(@TMI.Attrs.MotionY)^ and 63) shl 6);

        DoCmd(gtPredictedTileOffsets6x6, attrs);
      end;
    end
    else
    begin
      attrs := (Ord(TMI.VMirror) shl 1) or Ord(TMI.HMirror);
      finalTileIdx := FTiles[TMI.TileIdx]^.TmpIndex;

      isKeyFrameTile := finalTileIdx >= Length(globalTiles);
      if isKeyFrameTile then
      begin
        finalTileIdx -= Length(globalTiles);
        Assert(finalTileIdx >= 0);
      end;

      //isTile32 := finalTileIdx > High(Word);
      //isPalTile := TMI.PalIdx <> FTiles[TMI.TileIdx]^.PalIdx;
      //
      //if isPalTile then
      //begin
      //  DoCmd(gtPalTile, attrs or (Ord(isKeyFrameTile) shl 2));
      //  DoDWord(finalTileIdx);
      //  DoWord(TMI.PalIdx);
      //end
      //else
      //begin
      //  if isTile32 then
      //  begin
      //    DoAltCmd(gtGlobalTile32, gtKeyFrmTile32, isKeyFrameTile, attrs);
      //    DoDWord(finalTileIdx);
      //  end
      //  else
      //  begin
      //    DoAltCmd(gtGlobalTile16, gtKeyFrmTile16, isKeyFrameTile, attrs);
      //    DoWord(finalTileIdx);
      //  end;
      //end;
    end;
  end;

  procedure WritePalettes;
  var
    colIdx, palIdx, col: Integer;
  begin
    //for palIdx := 0 to FPaletteCount - 1 do
    //begin
    //  DoCmd(gtLoadPalette, (0 shl 6) or (FPaletteSize - 1));
    //  DoWord(palIdx);
    //  for colIdx := 0 to FPaletteSize - 1 do
    //  begin
    //    col := 0;
    //    if InRange(palIdx, 0, High(FPalettes)) and InRange(colIdx, 0, High(FPalettes[palIdx].PaletteRGB)) then
    //      col := FPalettes[palIdx].PaletteRGB[colIdx];
    //
    //    if col = cDitheringNullColor then
    //      col := $ffffff;
    //
    //    DoDWord(col or $ff000000);
    //  end;
    //end;
  end;

  procedure WriteTiles(const AList: TIntegerDynArray; IsKF: Boolean; AStart: Integer = 0);
  var
    tx, ty, tlIdx: Integer;
    isNibbleCoded: Boolean;
    T: PTile;
  begin
    if Length(AList) > 0 then
    begin
      //isNibbleCoded := FPaletteSize <= 16;
      //
      //DoCmd(gtTileSet, Ord(IsKF) or (Ord(isNibbleCoded) shl 1));
      //DoDWord(AStart); // start tile
      //DoDWord(AStart + High(AList)); // end tile
      //
      //for tlIdx := 0 to High(AList) do
      //  DoWord(Tiles[AList[tlIdx]]^.PalIdx);
      //
      //if isNibbleCoded then
      //begin
      //  for tlIdx := 0 to High(AList) do
      //  begin
      //    T := Tiles[AList[tlIdx]];
      //    for ty := 0 to cTileWidth - 1 do
      //      for tx := 0 to cTileWidth - 1 do
      //        if not Odd(tx) then
      //          DoByte((T^.PalPixels[ty, tx] and 15) + ((T^.PalPixels[ty, tx + 1] and 15) shl 4));
      //  end;
      //end
      //else
      //begin
      //  for tlIdx := 0 to High(AList) do
      //    ZStream.Write(Tiles[AList[tlIdx]]^.GetPalPixelsPtr^[0, 0], sqr(cTileWidth));
      //end;
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
    tIdx, iTIdx, frmIdx, sy, sx, kfIdx: Integer;
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

          if TMI^.IsPredicted then
            Continue;

          tIdx := TMI^.TileIdx;
          Assert(tIdx >= 0);

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

    // dim arrays

    SetLength(globalTiles, globalPos);
    globalPos := 0;
    SetLength(perKfTiles, Length(FKeyFrames));
    for kfIdx := 0 to High(perKfTiles) do
    begin
      SetLength(perKfTiles[kfIdx], perKFPos[kfIdx]);
      perKFPos[kfIdx] := 0;
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
          perKfTiles[kfIdx, perKFPos[kfIdx]] := tIdx;
          Inc(perKFPos[kfIdx]);
        end
        else
        begin
          globalTiles[globalPos] := tIdx;
          Inc(globalPos);
        end;
      end;
    end;

    // sort arrays

    if Assigned(globalTiles) then
      QuickSort(globalTiles[0], 0, High(globalTiles), SizeOf(Integer), @CompareTileIdxsUseCountHSVPixels, Self);

    for kfIdx := 0 to High(perKfTiles) do
      if Assigned(perKfTiles[kfIdx]) then
        QuickSort(perKfTiles[kfIdx, 0], 0, High(perKfTiles[kfIdx]), SizeOf(Integer), @CompareTileIdxsHSVPixels, Self);

    // map tiles to final indexes thru TmpIndex

    for iTIdx := 0 to High(globalTiles) do
      FTiles[globalTiles[iTIdx]]^.TmpIndex := iTIdx;

    for kfIdx := 0 to High(perKfTiles) do
      for iTIdx := 0 to High(perKfTiles[kfIdx]) do
        FTiles[perKfTiles[kfIdx, iTIdx]]^.TmpIndex := iTIdx + Length(globalTiles);

    // log TileCount

    WriteLn('Global      , TileCount: ', Length(globalTiles):8);
    for kfIdx := 0 to High(perKfTiles) do
      WriteLn('KF: ', FKeyFrames[kfIdx].StartFrame:8,', TileCount: ', Length(perKfTiles[kfIdx]):8);
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
  Header.EncoderVersion := 6; // 2 -> fixed blending extents; 3 -> *AddlBlendTileIdx; 4 -> PredictMotion; 5 -> (unreleased); 6 -> Blend,Glob/KF,TilePalIdxs
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

  FRenderOuptutFrameIndex := -1;
  FRenderPredicted := True;
  FRenderMirrored := True;
  FRenderOutputJPEG := True;

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
begin
  case AStep of
    esAll:
      RunRange(esLoad, esSave);
    esLoad:
      Load;
    esPredict:
      PredictMotion;
    esReindex:
      Reindex;
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

