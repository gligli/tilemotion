unit extern;

{$mode objfpc}{$H+}

interface

uses
  LazLogger, Windows, Classes, SysUtils, Types, Process, strutils, math;

type
  TFloat = Double;

  TFloatDynArray = array of TFloat;
  TFloatDynArray2 = array of TFloatDynArray;
  TDoubleDynArray2 = array of TDoubleDynArray;
  PFloat = ^TFloat;
  PPFloat = ^PFloat;
  PFloatDynArray = ^TFloatDynArray;

  TANNsplitRule = (
  		ANN_KD_STD = 0,      // the optimized kd-splitting rule
  		ANN_KD_MIDPT = 1,    // midpoint split
  		ANN_KD_FAIR	= 2,     // fair split
  		ANN_KD_SL_MIDPT = 3, // sliding midpoint splitting method
  		ANN_KD_SL_FAIR = 4,  // sliding fair split method
  		ANN_KD_SUGGEST = 5 // the authors' suggestion for best
  );

  TYakmo = record
  end;

  PYakmo = ^TYakmo;

  TYakmoCallback = procedure(cbData: Pointer); stdcall;

  TBICO = record
  end;

  PBICO = ^TBICO;

procedure LZCompress(ASourceStream: TStream; PrintProgress: Boolean; var ADestStream: TStream);

procedure DoExternalSKLearn(Dataset: TFloatDynArray2;  ClusterCount, Precision: Integer; PrintProgress: Boolean; var Clusters: TIntegerDynArray);
procedure DoExternalYakmo(TrainDS, TestDS: TFloatDynArray2; ClusterCount, RestartCount, IterationCount: Integer;
  OutputClusters, PrintProgress: Boolean; Centroids: TStringList; var Clusters: TIntegerDynArray);

procedure GenerateSVMLightData(Dataset: TFloatDynArray2; Output: TStringList; Header: Boolean);
function GenerateSVMLightFile(Dataset: TFloatDynArray2; Header: Boolean): String;
function GetSVMLightLine(index: Integer; lines: TStringList): TFloatDynArray;
function GetSVMLightClusterCount(lines: TStringList): Integer;

function NumberOfProcessors: Integer;

function yakmo_create(k: Cardinal; restartCount: Cardinal; maxIter: Integer; initType: Integer; initSeed: Integer; doNormalize: Integer; isVerbose: Integer): PYakmo; stdcall; external 'yakmo.dll';
procedure yakmo_destroy(ay: PYakmo); stdcall; external 'yakmo.dll';
procedure yakmo_load_train_data(ay: PYakmo; rowCount: Cardinal; colCount: Cardinal; dataset: PPFloat); stdcall; external 'yakmo.dll';
procedure yakmo_load_train_data_weighted(ay: PYakmo; rowCount: Cardinal; colCount: Cardinal; dataset: PPFloat; weights: PCardinal); stdcall; external 'yakmo.dll';
procedure yakmo_train_on_data(ay: PYakmo; pointToCluster: PInteger); stdcall; external 'yakmo.dll';
procedure yakmo_get_centroids(ay: PYakmo; centroids: PPFloat); stdcall; external 'yakmo.dll';
procedure yakmo_set_num_threads(num_threads: Integer); stdcall; external 'yakmo.dll';

function bico_create(dimension, npoints, k, nrandproj, coresetsize: Int64; randomSeed: Integer): PBICO; stdcall; external 'BICO.dll';
procedure bico_destroy(bico: PBICO); stdcall; external 'BICO.dll';
procedure bico_insert_line(bico: PBICO; line: PDouble; weight: Double); stdcall; external 'BICO.dll';
function bico_get_results(bico: PBICO; centroids: PDouble; weights: PDouble): Int64; stdcall; external 'BICO.dll';

function InvariantFormatSettings: TFormatSettings;
function internalRuncommand(p:TProcess;var outputstring:string;
                            var stderrstring:string; var exitstatus:integer; PrintOut: Boolean):integer;

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
function internalRuncommand(p:TProcess;var outputstring:string;
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

procedure LZCompress(ASourceStream: TStream; PrintProgress: Boolean; var ADestStream: TStream);
var
  Process: TProcess;
  RetCode: Integer;
  Output, ErrOut, SrcFN, DstFN: String;
  SrcStream, DstStream: TFileStream;
begin
  Process := TProcess.Create(nil);
  Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
  Process.Executable := 'bzip2.exe';

  SrcFN := GetTempFileName('', 'lz-' + IntToStr(InterLockedIncrement(GTempAutoInc)) + '.dat');
  DstFN := ChangeFileExt(SrcFN, ExtractFileExt(SrcFN) + '.bz2');

  SrcStream := TFileStream.Create(SrcFN, fmCreate or fmShareDenyWrite);
  try
    ASourceStream.Seek(0, soBeginning);
    SrcStream.CopyFrom(ASourceStream, ASourceStream.Size);
  finally
    SrcStream.Free;
  end;

  Process.Parameters.Add('-9');
  Process.Parameters.Add(SrcFN);
  Process.ShowWindow := swoHIDE;
  Process.Priority := ppIdle;

  RetCode := 0;
  internalRuncommand(Process, Output, ErrOut, RetCode, PrintProgress); // destroys Process

  DstStream := TFileStream.Create(DstFN, fmOpenRead or fmShareDenyWrite);
  try
    ADestStream.CopyFrom(DstStream, DstStream.Size);
  finally
    DstStream.Free;
  end;
end;

procedure DoExternalSKLearn(Dataset: TFloatDynArray2; ClusterCount, Precision: Integer; PrintProgress: Boolean;
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
      Line := IntToStr(i) + ' ';
      for j := 0 to High(Dataset[0]) do
        Line := Line + FloatToStr(Dataset[i, j]) + ' ';
      SL.Add(Line);
    end;

    InFN := GetTempFileName('', 'dataset-'+IntToStr(InterLockedIncrement(GTempAutoInc))+'.txt');
    SL.SaveToFile(InFN);
    SL.Clear;

    Process := TProcess.Create(nil);
    Process.CurrentDirectory := ExtractFilePath(ParamStr(0));

    if SearchPath(nil, 'python.exe', nil, MAX_PATH, pythonExe, nil) = 0 then
      pythonExe := 'python.exe';
    Process.Executable := pythonExe;

    for i := 0 to GetEnvironmentVariableCount - 1 do
      Process.Environment.Add(GetEnvironmentString(i));
    Process.Environment.Add('MKL_NUM_THREADS=1');
    Process.Environment.Add('NUMEXPR_NUM_THREADS=1');
    Process.Environment.Add('OMP_NUM_THREADS=1');

    Process.Parameters.Add('cluster.py');
    Process.Parameters.Add('-i "' + InFN + '" -n ' + IntToStr(ClusterCount) + ' -t ' + FloatToStr(intpower(10.0, -Precision + 1)));
    if PrintProgress then
      Process.Parameters.Add('-d');
    Process.ShowWindow := swoHIDE;
    Process.Priority := ppIdle;

    st := 0;
    internalRuncommand(Process, Output, ErrOut, st, PrintProgress); // destroys Process

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

procedure DoExternalYakmo(TrainDS, TestDS: TFloatDynArray2; ClusterCount, RestartCount, IterationCount: Integer;
  OutputClusters, PrintProgress: Boolean; Centroids: TStringList; var Clusters: TIntegerDynArray);
var
  i, PrevLen, Clu, Inp, RetCode: Integer;
  TrainFN, TrainStmt, TestFN, CrFN, Line, Output, ErrOut, CmdLine: String;
  SL: TStringList;
  Process: TProcess;
begin
  if Assigned(TrainDS) and (ClusterCount >= Length(TrainDS)) then
  begin
    // force a valid dataset by duplicating some lines
    PrevLen := Length(TrainDS);
    SetLength(TrainDS, ClusterCount + 1);
    for i := PrevLen to ClusterCount do
      TrainDS[i] := TrainDS[i - PrevLen];
  end;

  Process := TProcess.Create(nil);
  SL := TStringList.Create;
  try
    if Assigned(TrainDS) then
      TrainFN := GenerateSVMLightFile(TrainDS, False);

    if Assigned(TestDS) then
      TestFN := GenerateSVMLightFile(TestDS, False);

    if Assigned(Centroids) then
    begin
      CrFN := GetTempFileName('', 'centroids-'+IntToStr(InterLockedIncrement(GTempAutoInc))+'.txt');
      if not Assigned(TrainDS) then
        Centroids.SaveToFile(CrFN)
    end;

    Process.CurrentDirectory := ExtractFilePath(ParamStr(0));
    Process.Executable := IfThen(SizeOf(TFloat) = SizeOf(Double), 'yakmo.exe', 'yakmo_single.exe');

    CmdLine := IfThen(OutputClusters, ' --output=2 ');
    CmdLine += IfThen(IterationCount < 0, ' --iteration=10000 ', ' --iteration=' + IntToStr(IterationCount) + ' ');
    CmdLine += IfThen((ClusterCount >= 0) and Assigned(TrainDS), ' --num-cluster=' + IntToStr(ClusterCount) + ' ');
    CmdLine += IfThen(RestartCount >= 0, ' --num-result=' + IntToStr(RestartCount) + ' ');

    TrainStmt := IfThen(TrainFN = '', '-', '"' + TrainFN + '"');

    if Assigned(TestDS) then
      CmdLine := TrainStmt + ' "' + CrFN + '" "' + TestFN + '" ' + CmdLine
    else if Assigned(Centroids) then
      CmdLine := TrainStmt + ' "' + CrFN + '" - ' + CmdLine
    else
      CmdLine := TrainStmt + ' - - ' + CmdLine;

    Process.Parameters.Add(CmdLine);
    Process.ShowWindow := swoHIDE;
    Process.Priority := ppIdle;

    RetCode := 0;
    internalRuncommand(Process, Output, ErrOut, RetCode, PrintProgress); // destroys Process

    if RetCode <> 0 then
      DebugLn('Yakmo failed! RetCode: ' + IntToStr(RetCode) + sLineBreak + 'Msg: ' + ErrOut + sLineBreak + 'CmdLine: ' + CmdLine);

    if Assigned(TrainDS) then
      DeleteFile(PChar(TrainFN));

    if Assigned(TestDS) then
      DeleteFile(PChar(TestFN));

    if Assigned(Centroids) then
    begin
      if Assigned(TrainDS) then
      begin
        if FileExists(CrFN) then
          Centroids.LoadFromFile(CrFN)
        else
          GenerateSVMLightData(TrainDS, Centroids, True);
      end;

      DeleteFile(PChar(CrFN));
    end;

    if OutputClusters then
    begin
      if (Pos(#10, Output) <> Pos(#13#10, Output) + 1) then
        SL.LineBreak := #10;

      SL.Text := Output;

      SetLength(Clusters, SL.Count);
      for i := 0 to SL.Count - 1 do
      begin
        Line := SL[i];
        if TryStrToInt(Copy(Line, 1, Pos(' ', Line) - 1), Inp) and
            TryStrToInt(RightStr(Line, Pos(' ', ReverseString(Line)) - 1), Clu) then
          Clusters[Inp] := Clu;
      end;
    end;
  finally
    SL.Free;
  end;
end;

procedure GenerateSVMLightData(Dataset: TFloatDynArray2; Output: TStringList; Header: Boolean);
var
  i, j: Integer;
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
    Line := Format('%d 1:%e', [i, Dataset[i, 0]], GInvariantFormatSettings);

    for j := 1 to High(Dataset[0]) do
      Line := Format('%s %d:%e', [Line, j + 1, Dataset[i, j]], GInvariantFormatSettings);

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
  SetLength(Result, GetLineInt(lines[2]));

  Assert(InRange(index, 0, clusterCount - 1), 'wrong index!');

  line := lines[3 + clusterCount * (restartCount - 1) + index];
  for i := 0 to High(Result) do
  begin
    sc := ' ' + IntToStr(i + 1) + ':';

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

function InvariantFormatSettings: TFormatSettings;
begin
  Result := GInvariantFormatSettings;
end;

function NumberOfProcessors: Integer;
begin
  Result := GNumberOfProcessors;
end;

var
  SystemInfo: SYSTEM_INFO;
initialization
  GetLocaleFormatSettings(LOCALE_INVARIANT, GInvariantFormatSettings);
  GetSystemInfo(SystemInfo);
  GNumberOfProcessors := SystemInfo.dwNumberOfProcessors;
end.

