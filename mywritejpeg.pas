{ Copyright (C) 2003 Mattias Gaertner

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation, Inc.,
  51 Franklin Street, Fifth Floor, Boston, MA 02111-1301, USA.
}
// modified by GliGli for ChromaSubsampling / Gamma / ...
unit mywritejpeg;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FPImage, JPEGLib, FPReadJPEG, JcAPIstd, JcAPImin, JDataDst,
  JcParam, JError;

type
  { TMyWriterJPEG }

  TMyJPEGCompressionQuality = 0..100;   // 100 = best quality, 25 = pretty awful

  TMyWriterJPEG = class(TFPCustomImageWriter)
  private
    FInfo: jpeg_compress_struct;

    FChromaSubsampling: boolean;
    FGamma: Double;
    FGrayscale: boolean;
    FProgressiveEncoding: boolean;
    FWriteMarkers: Boolean;
    FQuality: TMyJPEGCompressionQuality;

    FError: jpeg_error_mgr;
  protected
    procedure InternalWrite(Str: TStream; Img: TFPCustomImage); override;
  public
    constructor Create; override;
    destructor Destroy; override;
    property CompressionQuality: TMyJPEGCompressionQuality read FQuality write FQuality;
    property ProgressiveEncoding: boolean read FProgressiveEncoding write FProgressiveEncoding;
    property GrayScale: boolean read FGrayscale write FGrayScale;
    property WriteMarkers: Boolean read FWriteMarkers write FWriteMarkers;
    property ChromaSubsampling: boolean read FChromaSubsampling write FChromaSubsampling;
    property Gamma: Double read FGamma write FGamma;
  end;

implementation

procedure JPEGError(CurInfo: j_common_ptr);
begin
  if CurInfo=nil then exit;
  {$ifdef FPC_Debug_Image}
  writeln('JPEGError ',CurInfo^.err^.msg_code,' ');
  {$endif}
  raise Exception.CreateFmt('JPEG error',[CurInfo^.err^.msg_code]);
end;

procedure EmitMessage(CurInfo: j_common_ptr; msg_level: Integer);
begin
  if CurInfo=nil then exit;
  if msg_level=0 then ;
end;

procedure OutputMessage(CurInfo: j_common_ptr);
begin
  if CurInfo=nil then exit;
end;

procedure FormatMessage(CurInfo: j_common_ptr; var buffer: string);
begin
  if CurInfo=nil then exit;
  {$ifdef FPC_Debug_Image}
  writeln('FormatMessage ',buffer);
  {$endif}
end;

procedure ResetErrorMgr(CurInfo: j_common_ptr);
begin
  if CurInfo=nil then exit;
  CurInfo^.err^.num_warnings := 0;
  CurInfo^.err^.msg_code := 0;
end;

{ TMyWriterJPEG }

procedure TMyWriterJPEG.InternalWrite(Str: TStream; Img: TFPCustomImage);
var
  MemStream: TMemoryStream;
  Continue: Boolean;

  procedure InitWriting;
  begin
    FillChar(FInfo, sizeof(FInfo), 0);

    with FError do begin
      error_exit:=@JPEGError;
      emit_message:=@EmitMessage;
      output_message:=@OutputMessage;
      format_message:=@FormatMessage;
      reset_error_mgr:=@ResetErrorMgr;
    end;

    FInfo.err := jerror.jpeg_std_error(FError);

    jpeg_create_compress(@FInfo);
  end;

  procedure SetDestination;
  begin
    if Str is TMemoryStream then
      MemStream:=TMemoryStream(Str)
    else
      MemStream := TMemoryStream.Create;
    jpeg_stdio_dest(@FInfo, @MemStream);
  end;

  procedure WriteHeader;
  begin
    FInfo.image_width := Img.Width;
    FInfo.image_height := Img.Height;
    if FGrayscale then
    begin
      FInfo.input_components := 1;
      FInfo.in_color_space := JCS_GRAYSCALE;
    end
    else
    begin
      FInfo.input_components := 3; // RGB has 3 components
      FInfo.in_color_space := JCS_RGB;
    end;

    jpeg_set_defaults(@FInfo);
    jpeg_set_quality(@FInfo, FQuality, True);

    FInfo.input_gamma := FGamma;

    if not FChromaSubsampling then
    begin
      FInfo.comp_info^[0].h_samp_factor := 1;
      FInfo.comp_info^[0].v_samp_factor := 1;
      FInfo.comp_info^[1].h_samp_factor := 1;
      FInfo.comp_info^[1].v_samp_factor := 1;
      FInfo.comp_info^[2].h_samp_factor := 1;
      FInfo.comp_info^[2].v_samp_factor := 1;
    end;

    if not FWriteMarkers then
    begin
      FInfo.write_Adobe_marker := False;
      FInfo.write_JFIF_header := False;
    end;

    if ProgressiveEncoding then
      jpeg_simple_progression(@FInfo);
  end;

  procedure WritePixels;
  var
    LinesWritten: Cardinal;
    SampArray: JSAMPARRAY;
    SampRow: JSAMPROW;
    Color: TFPColor;
    x: Integer;
    y: Integer;
  begin
    Progress(psStarting, 0, False, Rect(0,0,0,0), '', Continue);
    if not Continue then exit;
    jpeg_start_compress(@FInfo, True);

    // write one line per call
    GetMem(SampArray,SizeOf(JSAMPROW));
    GetMem(SampRow,FInfo.image_width*FInfo.input_components);
    SampArray^[0]:=SampRow;
    try
      y:=0;
      while (FInfo.next_scanline < FInfo.image_height) do begin
        if FGrayscale then
        for x:=0 to FInfo.image_width-1 do
          SampRow^[x]:=CalculateGray(Img.Colors[x,y]) shr 8
        else
        for x:=0 to FInfo.image_width-1 do begin
          Color:=Img.Colors[x,y];
          SampRow^[x*3+0]:=Color.Red shr 8;
          SampRow^[x*3+1]:=Color.Green shr 8;
          SampRow^[x*3+2]:=Color.Blue shr 8;
        end;
        LinesWritten := jpeg_write_scanlines(@FInfo, SampArray, 1);
        if LinesWritten<1 then break;
        inc(y);
      end;
    finally
      FreeMem(SampRow);
      FreeMem(SampArray);
    end;

    jpeg_finish_compress(@FInfo);
    Progress(psEnding, 100, False, Rect(0,0,0,0), '', Continue);
  end;

  procedure EndWriting;
  begin
    jpeg_destroy_compress(@FInfo);
  end;

begin
  Continue := true;
  MemStream:=nil;
  try
    InitWriting;
    SetDestination;
    WriteHeader;
    WritePixels;
    if MemStream<>Str then begin
      MemStream.Position:=0;
      Str.CopyFrom(MemStream,MemStream.Size);
    end;
  finally
    EndWriting;
    if MemStream<>Str then
      MemStream.Free;
  end;
end;

constructor TMyWriterJPEG.Create;
begin
  inherited Create;
  FQuality := 75;
  FGamma := 1.0;
  FChromaSubsampling := True;
  FWriteMarkers := True;
end;

destructor TMyWriterJPEG.Destroy;
begin
  inherited Destroy;
end;

end.
