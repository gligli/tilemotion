unit extern;

{$mode objfpc}{$H+}

interface

uses
  LazLogger, Windows, Classes, SysUtils, Types, Process, strutils, math,
  libavcodec_codec, libavcodec_packet, libavcodec, libavformat, libavutil, libavutil_error, libavutil_frame,
  libavutil_imgutils, libavutil_log, libavutil_mem, libavutil_pixfmt, libavutil_rational, libswscale, FFUtils,
  ULZMAEncoder, ULZMADecoder;

type
  TFloat = Single;

  TIntegerDynArray2 = array of TIntegerDynArray;
  TIntegerDynArray3 = array of TIntegerDynArray2;
  TByteDynArray2 = array of TByteDynArray;
  TFloatDynArray = array of TFloat;
  TFloatDynArray2 = array of TFloatDynArray;
  TFloatDynArray3 = array of TFloatDynArray2;
  TDoubleDynArray2 = array of TDoubleDynArray;
  TDoubleDynArray3 = array of TDoubleDynArray2;
  TBooleanDynArray2 = array of TBooleanDynArray;
  PFloat = ^TFloat;
  PPFloat = ^PFloat;
  PFloatDynArray = ^TFloatDynArray;
  PFloatDynArray2 = ^TFloatDynArray2;
  PDoubleDynArray = ^TDoubleDynArray;
  PDoubleDynArray2 = ^TDoubleDynArray2;
  PPSingle = ^PSingle;
  TSingleDynArray2 = array of TSingleDynArray;

  PPSmallint = ^PSmallInt;
  TSmallIntDynArray2 = array of TSmallIntDynArray;

  TFFMPEG = record
    FmtCtx: PAVFormatContext;
    CodecCtx: PAVCodecContext;
    Codec: PAVCodec;
    VideoStream, DstWidth, DstHeight, FrameCount: Integer;
    Scaling, FramesPerSecond: Double;
    TimeBase: TAVRational;
    StartTimeStamp: Int64;
  end;

  TFFMPEGFrameCallback = procedure(AIndex, AWidth, AHeight:Integer; AFrameData: PInteger; AUserParameter: Pointer);

  EFFMPEGError = class(Exception);

procedure LZCompress(ASourceStream: TStream; ADestStream: TStream);
procedure LZDecompress(ASourceStream: TStream; ADestStream: TStream);

procedure DoExternalSKLearn(Dataset: TByteDynArray2; ClusterCount, Precision: Integer; Compiled, PrintProgress: Boolean; var Clusters: TIntegerDynArray);
procedure DoExternalKMeans(Dataset: TFloatDynArray2;  ClusterCount, ThreadCount: Integer; PrintProgress: Boolean; var Clusters: TIntegerDynArray);

procedure GenerateSVMLightData(Dataset: TFloatDynArray2; Output: TStringList; Header: Boolean);
function GenerateSVMLightFile(Dataset: TFloatDynArray2; Header: Boolean): String;
function GetSVMLightLine(index: Integer; lines: TStringList): TFloatDynArray;
function GetSVMLightClusterCount(lines: TStringList): Integer;

function NumberOfProcessors: Integer;
function HalfNumberOfProcessors: Integer;
function QuarterNumberOfProcessors: Integer;
function InvariantFormatSettings: TFormatSettings;
function RunProcess(p:TProcess;var outputstring:string; var stderrstring:string; var exitstatus:integer; PrintOut: Boolean):integer;

function FFMPEG_Open(AFileName: String; AScaling: Double; ASilent: Boolean): TFFMPEG;
procedure FFMPEG_Close(AFFMPEG: TFFMPEG);
procedure FFMPEG_LoadFrames(AFFMPEG: TFFMPEG; AStartFrame, AFrameCount: Integer; AFrameCallback: TFFMPEGFrameCallback; AUserParameter: Pointer = nil);

function GetActiveProcessorCount(GroupNumber: Word): DWORD; stdcall; external 'kernel32.dll';

const
  ALL_PROCESSOR_GROUPS = High(Word);

implementation

var
  GTempAutoInc : Integer = 0;
  GInvariantFormatSettings: TFormatSettings;
  GNumberOfProcessors: Integer = 0;

const
  READ_BYTES = 65536; // not too small to avoid fragmentation when reading large files.

// helperfunction that does the bulk of the work.
// We need to also collect stderr output in order to avoid
// lock out if the stderr pipe is full.
function RunProcess(p:TProcess;var outputstring:string;
                            var stderrstring:string; var exitstatus:integer; PrintOut: Boolean):integer;
var
    numbytes,bytesread,available : integer;
    outputlength, stderrlength : integer;
    stderrnumbytes,stderrbytesread, PrintLastPos, prp : integer;
begin
  result:=-1;
  try
    try
    p.Options :=  [poUsePipes];
    bytesread:=0;
    outputlength:=0;
    stderrbytesread:=0;
    stderrlength:=0;
    PrintLastPos:=1;
    p.Execute;
    while p.Running do
      begin
        // Only call ReadFromStream if Data from corresponding stream
        // is already available, otherwise, on  linux, the read call
        // is blocking, and thus it is not possible to be sure to handle
        // big data amounts bboth on output and stderr pipes. PM.
        available:=P.Output.NumBytesAvailable;
        if  available > 0 then
          begin
            if (BytesRead + available > outputlength) then
              begin
                outputlength:=BytesRead + READ_BYTES;
                Setlength(outputstring,outputlength);
              end;
            NumBytes := p.Output.Read(outputstring[1+bytesread], available);

            // output to screen
            prp := Pos(#10, Copy(outputstring, PrintLastPos, bytesread - PrintLastPos + NumBytes));
            if PrintOut and (prp <> 0) then
            begin
              Write(Copy(outputstring, PrintLastPos, prp));
              PrintLastPos += prp;
            end;

            if NumBytes > 0 then
              Inc(BytesRead, NumBytes);
          end
        // The check for assigned(P.stderr) is mainly here so that
        // if we use poStderrToOutput in p.Options, we do not access invalid memory.
        else if assigned(P.stderr) and (P.StdErr.NumBytesAvailable > 0) then
          begin
            available:=P.StdErr.NumBytesAvailable;
            if (StderrBytesRead + available > stderrlength) then
              begin
                stderrlength:=StderrBytesRead + READ_BYTES;
                Setlength(stderrstring,stderrlength);
              end;
            StderrNumBytes := p.StdErr.Read(stderrstring[1+StderrBytesRead], available);

            if StderrNumBytes > 0 then
              Inc(StderrBytesRead, StderrNumBytes);
          end
        else
          Sleep(10);
      end;

    if PrintOut then
      Write(Copy(stderrstring, PrintLastPos, StderrBytesRead - PrintLastPos));

    // Get left output after end of execution
    available:=P.Output.NumBytesAvailable;
    while available > 0 do
      begin
        if (BytesRead + available > outputlength) then
          begin
            outputlength:=BytesRead + READ_BYTES;
            Setlength(outputstring,outputlength);
          end;
        NumBytes := p.Output.Read(outputstring[1+bytesread], available);
        if NumBytes > 0 then
          Inc(BytesRead, NumBytes);
        available:=P.Output.NumBytesAvailable;
      end;
    setlength(outputstring,BytesRead);
    while assigned(P.stderr) and (P.Stderr.NumBytesAvailable > 0) do
      begin
        available:=P.Stderr.NumBytesAvailable;
        if (StderrBytesRead + available > stderrlength) then
          begin
            stderrlength:=StderrBytesRead + READ_BYTES;
            Setlength(stderrstring,stderrlength);
          end;
        StderrNumBytes := p.StdErr.Read(stderrstring[1+StderrBytesRead], available);
        if StderrNumBytes > 0 then
          Inc(StderrBytesRead, StderrNumBytes);
      end;
    setlength(stderrstring,StderrBytesRead);
    exitstatus:=p.exitstatus;
    result:=0; // we came to here, document that.
    except
      on e : Exception do
         begin
           result:=1;
           setlength(outputstring,BytesRead);
         end;
     end;
  finally
    p.free;
  end;
end;

procedure LZCompress(ASourceStream: TStream; ADestStream: TStream);
var
  plainSz: Int64;
  LZMA: TLZMAEncoder;
begin
  ASourceStream.Seek(0, soBeginning);
  plainSz := ASourceStream.Size;

  LZMA := TLZMAEncoder.Create;
  try
    LZMA.SetEndMarkerMode(True);
    LZMA.SetDictionarySize(1 shl Ceil(Log2(plainSz)));
    LZMA.SetLcLpPb(8,0,2);
    LZMA.WriteCoderProperties(ADestStream);
    ADestStream.WriteQWord(High(UInt64));

    LZMA.Code(ASourceStream,ADestStream, plainSz, -1);
  finally
    LZMA.Free;
  end;
end;

procedure LZDecompress(ASourceStream: TStream; ADestStream: TStream);
var
  LZMA: TLZMADecoder;
  EncoderProperties: array[0..4] of Byte;
begin
  LZMA := TLZMADecoder.Create;
  try
    ASourceStream.Read(EncoderProperties,SizeOf(EncoderProperties));
    LZMA.SetDecoderProperties(EncoderProperties);
    ASourceStream.ReadQWord;

    LZMA.Code(ASourceStream, ADestStream, -1);
  finally
    LZMA.Free;
  end;
end;

procedure DoExternalSKLearn(Dataset: TByteDynArray2; ClusterCount, Precision: Integer; Compiled, PrintProgress: Boolean;
  var Clusters: TIntegerDynArray);
var
  i, j, st: Integer;
  InFN, Line, Output, ErrOut: String;
  SL, Shuffler: TStringList;
  Process: TProcess;
  OutputStream: TMemoryStream;
  pythonExe: array[0..MAX_PATH-1] of Char;
begin
  SL := TStringList.Create;
  Shuffler := TStringList.Create;
  OutputStream := TMemoryStream.Create;
  try
    for i := 0 to High(Dataset) do
    begin
      Line := '';
      for j := 0 to High(Dataset[0]) do
        Line := Line + IntToStr(Dataset[i, j]) + ' ';
      SL.Add(Line);
    end;

    InFN := GetTempFileName('', 'dataset-'+IntToStr(InterLockedIncrement(GTempAutoInc))+'.txt');
    SL.SaveToFile(InFN);
    SL.Clear;

    Process := TProcess.Create(nil);
    Process.CurrentDirectory := ExtractFilePath(ParamStr(0));

    if Compiled then
    begin
      Process.Executable := 'cluster.exe';
    end
    else
    begin
      if SearchPath(nil, 'python.exe', nil, MAX_PATH, pythonExe, nil) = 0 then
        pythonExe := 'python.exe';
      Process.Executable := pythonExe;
    end;

    for i := 0 to GetEnvironmentVariableCount - 1 do
      Process.Environment.Add(GetEnvironmentString(i));
    Process.Environment.Add('MKL_NUM_THREADS=1');
    Process.Environment.Add('NUMEXPR_NUM_THREADS=1');
    Process.Environment.Add('OMP_NUM_THREADS=1');

    if not Compiled then
      Process.Parameters.Add('cluster.py');
    Process.Parameters.Add('-i "' + InFN + '" -n ' + IntToStr(ClusterCount) + ' -t ' + FloatToStr(intpower(10.0, -Precision + 1)));
    if PrintProgress then
      Process.Parameters.Add('-d');
    Process.ShowWindow := swoHIDE;
    Process.Priority := ppIdle;

    st := 0;
    RunProcess(Process, Output, ErrOut, st, PrintProgress); // destroys Process
    Write(Output);
    Write(ErrOut);

    SL.LoadFromFile(InFN + '.membership');

    DeleteFile(PChar(InFN));
    DeleteFile(PChar(InFN + '.membership'));
    DeleteFile(PChar(InFN + '.cluster_centres'));

    SetLength(Clusters, SL.Count);
    for i := 0 to SL.Count - 1 do
    begin
      Line := SL[i];
      Clusters[i] := StrToIntDef(Line, -1);
    end;
  finally
    OutputStream.Free;
    Shuffler.Free;
    SL.Free;
  end;
end;

procedure DoExternalKMeans(Dataset: TFloatDynArray2; ClusterCount, ThreadCount: Integer; PrintProgress: Boolean;
  var Clusters: TIntegerDynArray);
var
  i, j, Clu, Inp, st: Integer;
  Line, Output, ErrOut, InFN: String;
  OutSL, Shuffler: TStringList;
  FS: TFileStream;
  Process: TProcess;
  OutputStream: TMemoryStream;
  pdi: PFloat;
  pfo: PSingle;
  fbuf: TSingleDynArray;
begin
  OutSL := TStringList.Create;
  Shuffler := TStringList.Create;
  OutputStream := TMemoryStream.Create;
  try
    InFN := GetTempFileName('', 'dataset-'+IntToStr(InterLockedIncrement(GTempAutoInc))+'.bin');
    FS := TFileStream.Create(InFN, fmCreate or fmShareDenyWrite);
    try
      FS.WriteDWord(Length(Dataset));
      FS.WriteDWord(Length(Dataset[0]));
      SetLength(fbuf, Length(Dataset[0]));
      for i := 0 to High(Dataset) do
      begin
        pdi := @Dataset[i, 0];
        pfo := @fbuf[0];
        for j := 0 to High(Dataset[0]) do
        begin
          pfo^ := pdi^;
          Inc(pdi);
          Inc(pfo);
        end;
        FS.Write(fbuf[0], Length(Dataset[0]) * SizeOf(pfo^));
      end;
    finally
      FS.Free;
    end;

    Process := TProcess.Create(nil);
    Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
    Process.Executable := 'omp_main.exe';
    Process.Parameters.Add(' -b -i "' + InFN + '" -n ' + IntToStr(ClusterCount) + ' -t 0 ' + ifthen(ThreadCount > 0, ' -p ' + IntToStr(ThreadCount) + ' '));
    Process.ShowWindow := swoHIDE;
    Process.Priority := ppIdle;

    st := 0;
    RunProcess(Process, Output, ErrOut, st, PrintProgress); // destroys Process

    OutSL.LoadFromFile(InFN + '.membership');

    DeleteFile(PChar(InFN));
    DeleteFile(PChar(InFN + '.membership'));
    DeleteFile(PChar(InFN + '.cluster_centres'));

    for i := 0 to OutSL.Count - 1 do
    begin
      Line := OutSL[i];
      if TryStrToInt(Copy(Line, 1, Pos(' ', Line) - 1), Inp) and
          TryStrToInt(RightStr(Line, Pos(' ', ReverseString(Line)) - 1), Clu) then
        Clusters[Inp] := Clu;
    end;
  finally
    OutputStream.Free;
    Shuffler.Free;
    OutSL.Free;
  end;
end;

procedure GenerateSVMLightData(Dataset: TFloatDynArray2; Output: TStringList; Header: Boolean);
var
  i, j, cnt: Integer;
  Line: String;
begin
  Output.Clear;
  Output.LineBreak := sLineBreak;

  if Header then
  begin
    Output.Add('1 # m');
    Output.Add(IntToStr(Length(Dataset)) + ' # k');
    Output.Add(IntToStr(Length(Dataset[0])) + ' # number of features');
  end;

  for i := 0 to High(Dataset) do
  begin
    Line := Format('%d ', [i], GInvariantFormatSettings);

    cnt := Length(Dataset[i]);
    j := 0;

    while cnt > 16 do
    begin
      Line := Format('%s %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f %d:%.12f',
        [
          Line,
          j + 1,  Dataset[i, j + 0],  j + 2,  Dataset[i, j + 1],  j + 3,  Dataset[i, j + 2],  j + 4,  Dataset[i, j + 3],
          j + 5,  Dataset[i, j + 4],  j + 6,  Dataset[i, j + 5],  j + 7,  Dataset[i, j + 6],  j + 8,  Dataset[i, j + 7],
          j + 9,  Dataset[i, j + 8],  j + 10, Dataset[i, j + 9],  j + 11, Dataset[i, j + 10], j + 12, Dataset[i, j + 11],
          j + 13, Dataset[i, j + 12], j + 14, Dataset[i, j + 13], j + 15, Dataset[i, j + 14], j + 16, Dataset[i, j + 15]
        ],
        GInvariantFormatSettings);
      Dec(cnt, 16);
      Inc(j, 16);
    end;

    while cnt > 0 do
    begin
      Line := Format('%s %d:%.12f', [Line, j + 1,  Dataset[i, j]], GInvariantFormatSettings);
      Dec(cnt);
      Inc(j);
    end;

    Output.Add(Line);
  end;
end;

function GenerateSVMLightFile(Dataset: TFloatDynArray2; Header: Boolean): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    GenerateSVMLightData(Dataset, SL, Header);

    Result := GetTempFileName('', 'dataset-'+IntToStr(InterLockedIncrement(GTempAutoInc))+'.txt');

    SL.SaveToFile(Result);
  finally
    SL.Free;
  end;
end;

function GetLineInt(line: String): Integer;
begin
  Result := StrToInt(copy(line, 1, Pos(' ', line) - 1));
end;

function GetSVMLightLine(index: Integer; lines: TStringList): TFloatDynArray;
var
  i, p, np, clusterCount, restartCount: Integer;
  line, val, sc: String;

begin
  // TODO: so far, only compatible with YAKMO centroids

  restartCount := GetLineInt(lines[0]);
  clusterCount := GetLineInt(lines[1]);
  SetLength(Result, GetLineInt(lines[2]) + 1);

  Assert(InRange(index, 0, clusterCount - 1), 'wrong index!');

  line := lines[3 + clusterCount * (restartCount - 1) + index];
  for i := 0 to High(Result) do
  begin
    sc := ' ' + IntToStr(i) + ':';

    p := Pos(sc, line);
    if p = 0 then
    begin
      Result[i] := 0.0; //svmlight zero elimination
    end
    else
    begin
      p += Length(sc);

      np := PosEx(' ', line, p);
      if np = 0 then
        np := Length(line) + 1;
      val := Copy(line, p, np - p);

      //writeln(i, #9 ,index,#9,p,#9,np,#9, val);

      if Pos('nan', val) = 0 then
        Result[i] := StrToFloat(val, GInvariantFormatSettings)
      else
        Result[i] := abs(NaN); // Quiet NaN
    end;
  end;
end;

function GetSVMLightClusterCount(lines: TStringList): Integer;
begin
  Result := GetLineInt(lines[1]);
end;

function NumberOfProcessors: Integer;
begin
  Result := GNumberOfProcessors;
end;

function HalfNumberOfProcessors: Integer;
begin
  Result := max(1, GNumberOfProcessors div 2);
end;

function QuarterNumberOfProcessors: Integer;
begin
  Result := max(1, GNumberOfProcessors div 4);
end;

function InvariantFormatSettings: TFormatSettings;
begin
  Result := GInvariantFormatSettings;
end;

function FFMPEG_Open(AFileName: String; AScaling: Double; ASilent: Boolean): TFFMPEG;
var
  FFMPEG: TFFMPEG;
begin
  FillChar(FFMPEG, SizeOf(FFMPEG), 0);
  FFMPEG.VideoStream := -1;
  FFMPEG.Scaling := AScaling;

  av_log_set_level(IfThen(ASilent, AV_LOG_QUIET, AV_LOG_INFO));

  // Open video file
  if avformat_open_input(@FFMPEG.FmtCtx, PChar(AFileName), nil, nil) <> 0 then
    raise EFFMPEGError.Create('Could not open file: ' + AFileName);

  // Retrieve stream information
  if avformat_find_stream_info(FFMPEG.FmtCtx, nil) < 0 then
    raise EFFMPEGError.Create('Could not find stream information');

  // Dump information about file onto standard error
  av_dump_format(FFMPEG.FmtCtx, 0, PChar(AFileName), 0);

  // Find the first video stream
  FFMPEG.VideoStream := av_find_best_stream(FFMPEG.FmtCtx, AVMEDIA_TYPE_VIDEO, -1, -1, @FFMPEG.Codec, 0);
  if FFMPEG.VideoStream < 0 then
    raise EFFMPEGError.Create('Did not find a video stream');

  // create decoding context
  FFMPEG.CodecCtx := avcodec_alloc_context3(FFMPEG.Codec);
  if not Assigned(FFMPEG.CodecCtx) then
    raise EFFMPEGError.Create('Could not create decoding context');
  avcodec_parameters_to_context(FFMPEG.CodecCtx, PPtrIdx(FFMPEG.FmtCtx^.streams, FFMPEG.VideoStream)^.codecpar);

  // Open codec
  if avcodec_open2(FFMPEG.CodecCtx, FFMPEG.Codec, nil) < 0 then
    raise EFFMPEGError.Create('Could not open codec');

  FFMPEG.DstWidth := round(FFMPEG.CodecCtx^.width * FFMPEG.Scaling);
  FFMPEG.DstHeight := round(FFMPEG.CodecCtx^.height * FFMPEG.Scaling);
  FFMPEG.FramesPerSecond := av_q2d(PPtrIdx(FFMPEG.FmtCtx^.streams, FFMPEG.VideoStream)^.r_frame_rate);
  FFMPEG.TimeBase := PPtrIdx(FFMPEG.FmtCtx^.streams, FFMPEG.VideoStream)^.time_base;
  FFMPEG.StartTimeStamp := Max(0, PPtrIdx(FFMPEG.FmtCtx^.streams, FFMPEG.VideoStream)^.start_time);

  FFMPEG.FrameCount := PPtrIdx(FFMPEG.FmtCtx^.streams, FFMPEG.VideoStream)^.nb_frames;
  if FFMPEG.FrameCount <= 0 then
  begin
    // estimate frame count using stream duration
    FFMPEG.FrameCount := Round(Max(0, PPtrIdx(FFMPEG.FmtCtx^.streams, FFMPEG.VideoStream)^.duration) * FFMPEG.TimeBase.num * FFMPEG.FramesPerSecond / FFMPEG.TimeBase.den);
  end;
  if FFMPEG.FrameCount <= 0 then
  begin
    // estimate frame count using file duration
    FFMPEG.FrameCount := Round(Max(0, FFMPEG.FmtCtx^.duration) * FFMPEG.FramesPerSecond / AV_TIME_BASE_I);
  end;
  if FFMPEG.FrameCount <= 0 then
  begin
    // worst case, assume at least 1 frame
    FFMPEG.FrameCount := 1;
  end;

  Result := FFMPEG;
end;

procedure FFMPEG_Close(AFFMPEG: TFFMPEG);
begin
  avcodec_free_context(@AFFMPEG.CodecCtx);
  avformat_close_input(@AFFMPEG.FmtCtx);
end;

procedure FFMPEG_LoadFrames(AFFMPEG: TFFMPEG; AStartFrame, AFrameCount: Integer; AFrameCallback: TFFMPEGFrameCallback;
 AUserParameter: Pointer);
var
  frmTS, frmIdx: Int64;
  initialSeekDone: Boolean;
  doneFrameCount, ret, ret2: Integer;
  FFFrame: PAVFrame;
  FFSWSCtx: PSwsContext;
  FFPacket: PAVPacket;
  FFDstData: array[0..3] of PByte;
  FFDstLinesize: array[0..3] of Integer;
  FFDstPixFmt: TAVPixelFormat;
begin
  if AFrameCount <= 0 then
    Exit;

  FFFrame := nil;
  FFSWSCtx := nil;
  FFPacket := nil;
  FillChar(FFDstData, Sizeof(FFDstData), 0);
  doneFrameCount := 0;
  initialSeekDone := False;
  try
    FFDstPixFmt := AV_PIX_FMT_RGB32; // compatible with TPortableNetworkGraphic

    // Allocate video frame
    FFFrame := av_frame_alloc;
    if not Assigned(FFFrame) then
      raise EFFMPEGError.Create('Could not allocate frame');

    // Allocate destination image
    if av_image_alloc(@FFDstData[0], @FFDstLinesize[0], AFFMPEG.DstWidth, AFFMPEG.DstHeight, FFDstPixFmt, 1) < 0 then
      raise EFFMPEGError.Create('Could not allocate destination image');

    // Get scaler context
    FFSWSCtx := sws_getContext(
        AFFMPEG.CodecCtx^.width, AFFMPEG.CodecCtx^.height, AFFMPEG.CodecCtx^.pix_fmt,
        AFFMPEG.DstWidth, AFFMPEG.DstHeight, FFDstPixFmt,
        SWS_LANCZOS, nil, nil, nil);
    if not Assigned(FFSWSCtx) then
      raise EFFMPEGError.Create('Could not get scaler context');

    // Seek to desired frame
    frmTS := Round(AStartFrame * AFFMPEG.TimeBase.den / (AFFMPEG.FramesPerSecond * AFFMPEG.TimeBase.num));
    if frmTS > 0 then
      if avformat_seek_file(AFFMPEG.FmtCtx, AFFMPEG.VideoStream, 0, frmTS, frmTS, 0) < 0 then
        raise EFFMPEGError.Create('Could not seek to frame');

    avcodec_flush_buffers(AFFMPEG.CodecCtx);

    FFPacket := av_packet_alloc;

    while True do
    begin
      ret := avcodec_receive_frame(AFFMPEG.CodecCtx, FFFrame);
      if ret = AVERROR_EAGAIN then
      begin
        ret2 := av_read_frame(AFFMPEG.FmtCtx, FFPacket);
        if (ret2 < 0) and (ret2 <> AVERROR_EOF) then
          raise EFFMPEGError.Create('Error reading frame');
        try
          if FFPacket^.stream_index = AFFMPEG.VideoStream then
          begin
            if avcodec_send_packet(AFFMPEG.CodecCtx, FFPacket) < 0 then
              raise EFFMPEGError.Create('Error sending a packet for decoding');
          end;
        finally
          av_packet_unref(FFPacket);
        end;

        Continue;
      end
      else if ret = AVERROR_EOF then
      begin
        // EOF before video end -> fill remaining frames with black

        ret := av_image_fill_black(@FFDstData[0], PNativeInt(@FFDstLinesize[0]), FFDstPixFmt, AVCOL_RANGE_JPEG, AFFMPEG.DstWidth, AFFMPEG.DstHeight);
        if ret < 0 then
          raise EFFMPEGError.Create('Error clearing frame');

        while doneFrameCount < AFrameCount do
        begin
          AFrameCallback(AStartFrame + doneFrameCount, FFDstLinesize[0] shr 2, AFFMPEG.DstHeight, PInteger(FFDstData[0]), AUserParameter);
          Inc(doneFrameCount);
        end;

        Break;
      end
      else if ret < 0 then
        raise EFFMPEGError.Create('Error receiving frame');

      if not initialSeekDone then
      begin
        // Timestamps can be trusted enough to seek to the initial frame we want, but not much more (ie. they tend to falter at video end)

        frmIdx := 0;
        if (FFFrame^.best_effort_timestamp >= 0) and (FFFrame^.duration > 0) then
          frmIdx := (FFFrame^.best_effort_timestamp - AFFMPEG.StartTimeStamp) div FFFrame^.duration;
        initialSeekDone := frmIdx >= AStartFrame;
      end;

      if initialSeekDone then
      begin
        // Convert the image from its native format to RGB
        if sws_scale(FFSWSCtx, FFFrame^.data, FFFrame^.linesize, 0, AFFMPEG.CodecCtx^.height, FFDstData, FFDstLinesize) < 0 then
          raise EFFMPEGError.Create('Error rescaling frame');

        // Pass the image to the callback
        AFrameCallback(AStartFrame + doneFrameCount, FFDstLinesize[0] shr 2, AFFMPEG.DstHeight, PInteger(FFDstData[0]), AUserParameter);
        Inc(doneFrameCount);

        if doneFrameCount >= AFrameCount then
          Break;
      end;
    end;
  finally
    av_packet_free(@FFPacket);
    sws_freeContext(FFSWSCtx);
    av_freep(@FFDstData[0]);
    av_frame_free(@FFFrame);
  end;
end;

initialization
  GetLocaleFormatSettings(LOCALE_INVARIANT, GInvariantFormatSettings);
  GNumberOfProcessors := GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
end.

