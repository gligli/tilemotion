program tiler;

{$mode objfpc}{$H+}

uses
  tbbmalloc,
  //cmem,
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, main, extern, sysutils, LCLType, Controls, typinfo, tilingencoder, utils, powell, mtpool;

{$R *.res}

type

{ TEvtHolder }

TEvtHolder = class
  procedure AppException(Sender : TObject; E : Exception);
end;

procedure TEvtHolder.AppException(Sender: TObject; E: Exception);
var
  I: Integer;
  Frames: PPointer;
  Report: string;
begin
  Screen.Cursor := crDefault;
  Report := 'Program exception! ' + LineEnding +
    'Stacktrace:' + LineEnding + LineEnding;
  if E <> nil then begin
    Report := Report + 'Exception class: ' + E.ClassName + LineEnding +
    'Message: ' + E.Message + LineEnding;
  end;
  Report := Report + BackTraceStrFunc(ExceptAddr);
  Frames := ExceptFrames;
  for I := 0 to ExceptFrameCount - 1 do
    Report := Report + LineEnding + BackTraceStrFunc(Frames[I]);
  WriteLn(Report);
  TApplication(Sender).MessageBox(PChar(Report), PChar(Application.Title), MB_ICONERROR);
end;

var
  EvtHolder: TEvtHolder;
  Encoder: TTilingEncoder;
begin
  if ParamCount <= 0 then
  begin
    EvtHolder := TEvtHolder.Create;
    try
      RequireDerivedFormResource:=True;
      Application.Initialize;
      Application.CreateForm(TMainForm, MainForm);
      Application.OnException := @EvtHolder.AppException;
      Application.Run;
    finally
      EvtHolder.Free;
    end;
  end
  else
  begin
    Encoder := TTilingEncoder.Create;
    try
      Encoder.LoadSettings(ParamStr(1));
      Encoder.Run;
    finally
      Encoder.Free;
    end;

    ReadLn;
  end;
end.

