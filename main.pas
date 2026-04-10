unit main;

{$mode objfpc}{$H+}

interface

uses
  windows, Classes, SysUtils, strutils, types, Math, FileUtil, typinfo, LazLogger,
  Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, ComCtrls, Spin, Menus, IntfGraphics, Buttons,
  FPimage, FPCanvas, FPWritePNG, GraphType, FileInfo, extern, tilingencoder, utils;

type
  { TMainForm }

  TMainForm = class(TForm)
    btnGTM: TButton;
    btnInput: TButton;
    btnRunAll: TButton;
    btnPM: TButton;
    cbxBlendingMode: TComboBox;
    cbxDitheringMode: TComboBox;
    cbxMPMBF: TComboBox;
    cbxMPRadius: TComboBox;
    cbxPalCount: TComboBox;
    cbxPalSize: TComboBox;
    cbxScaling: TComboBox;
    cbxYilMix: TComboBox;
    chkStretch: TCheckBox;
    chkPredicted: TCheckBox;
    cbxEndStep: TComboBox;
    cbxStartStep: TComboBox;
    chkDitheredO: TCheckBox;
    chkGamma: TCheckBox;
    chkMirrored: TCheckBox;
    chkPlay: TCheckBox;
    chkUseTK: TCheckBox;
    edInput: TEdit;
    edOutput: TEdit;
    From: TLabel;
    gbMain: TGroupBox;
    gbAdvanced: TGroupBox;
    gbCPU: TGroupBox;
    imgDest: TImage;
    imgPalette: TPaintBox;
    imgSource: TImage;
    imgTiles: TImage;
    Label1: TLabel;
    Label10: TLabel;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    Label14: TLabel;
    Label15: TLabel;
    Label17: TLabel;
    Label18: TLabel;
    Label19: TLabel;
    Label20: TLabel;
    Label22: TLabel;
    Label4: TLabel;
    lblMaxCores: TLabel;
    lblPct: TLabel;
    lblQuality: TLabel;
    llPalTileDesc: TPanel;
    miGeneratePNGsOutput: TMenuItem;
    miGeneratePNGsInput: TMenuItem;
    miGenerateY4MOutput: TMenuItem;
    MenuItem7: TMenuItem;
    MenuItem8: TMenuItem;
    miGenerateY4MInput: TMenuItem;
    miGenerateY4M: TMenuItem;
    miReload: TMenuItem;
    miLoadSettings: TMenuItem;
    miGeneratePNGs: TMenuItem;
    miSaveSettings: TMenuItem;
    odFFInput: TOpenDialog;
    odGTM: TOpenDialog;
    odSettings: TOpenDialog;
    pbProgress: TProgressBar;
    pcPages: TPageControl;
    pnLbl: TPanel;
    sbPalettes: TScrollBar;
    sbTiles: TScrollBar;
    sdGTM: TSaveDialog;
    sdSettings: TSaveDialog;
    seFrameCount: TSpinEdit;
    seMaxCores: TSpinEdit;
    Separator1: TMenuItem;
    Separator3: TMenuItem;
    seShotTransCorrelLoThres: TFloatSpinEdit;
    seShotTransMaxSecondsPerKF: TFloatSpinEdit;
    seShotTransMinSecondsPerKF: TFloatSpinEdit;
    seStartFrame: TSpinEdit;
    seVisGamma: TFloatSpinEdit;
    tbQuality: TTrackBar;
    tiTrackbar: TTimer;
    tsTilesPal: TTabSheet;
    To1: TLabel;
    tsSettings: TTabSheet;
    tsInput: TTabSheet;
    tsOutput: TTabSheet;
    Label5: TLabel;
    Label8: TLabel;
    lblCorrel: TLabel;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem6: TMenuItem;
    miLoad: TMenuItem;
    MenuItem1: TMenuItem;
    pmProcesses: TPopupMenu;
    PopupMenu1: TPopupMenu;
    sedPalIdx: TSpinEdit;
    IdleTimer: TIdleTimer;
    tbFrame: TTrackBar;

    // processes
    procedure btnPredictMotionClick(Sender: TObject);
    procedure btnDitherClick(Sender: TObject);
    procedure btnGlobalLoadClick(Sender: TObject);
    procedure btnPreparePalettesClick(Sender: TObject);
    procedure btnClusterClick(Sender: TObject);
    procedure btnReconstructClick(Sender: TObject);
    procedure btnReindexClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);

    procedure btnPMClick(Sender: TObject);
    procedure btnGTMClick(Sender: TObject);
    procedure btnInputClick(Sender: TObject);
    procedure btnRunAllClick(Sender: TObject);
    procedure btnDebugClick(Sender: TObject);
    procedure btnDebug2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure IdleTimerTimer(Sender: TObject);
    procedure imgContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure imgPaletteClick(Sender: TObject);
    procedure imgPaintBackground(ASender: TObject; ACanvas: TCanvas; ARect: TRect);
    procedure imgPaletteContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure imgPaletteMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure imgPaletteMouseWheelDown(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
    procedure imgPaletteMouseWheelUp(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
    procedure imgPalettePaint(Sender: TObject);
    procedure imgTilesMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure imgTilesMouseWheelDown(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
    procedure imgTilesMouseWheelUp(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
    procedure miGeneratePNGsInputClick(Sender: TObject);
    procedure miGeneratePNGsOutputClick(Sender: TObject);
    procedure miGenerateY4MInputClick(Sender: TObject);
    procedure miGenerateY4MOutputClick(Sender: TObject);
    procedure miLoadSettingsClick(Sender: TObject);
    procedure miReloadClick(Sender: TObject);
    procedure miSaveSettingsClick(Sender: TObject);
    procedure sbPalettesChange(Sender: TObject);
    procedure sbTilesChange(Sender: TObject);
    procedure screenClick(Sender: TObject);
    procedure tbFrameChange(Sender: TObject);
    procedure tiTrackbarTimer(Sender: TObject);
    procedure UpdateVideo(Sender: TObject);
    procedure UpdateGUI(Sender: TObject);
  private
    FLastIOTabSheet: TTabSheet;
    FTilingEncoder: TTilingEncoder;
    FLockChanges: Boolean;
    FTrackbarTickCount: Integer;

    procedure TilingEncoderProgress(ASender: TTilingEncoder; APosition, AMax: Integer; AHourGlass: Boolean);
    procedure LoadGUISettings;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

function HasParam(p: String): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if SameText(p, ParamStr(i)) then
      Exit(True);
end;

function ParamStart(p: String): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 1 to ParamCount do
    if AnsiStartsStr(p, ParamStr(i)) then
      Exit(i);
end;

function ParamValue(p: String; def: Double): Double;
var
  idx: Integer;
begin
  idx := ParamStart(p);
  if idx < 0 then
    Exit(def);
  Result := StrToFloatDef(system.copy(ParamStr(idx), Length(p) + 1), def);
end;

{ TMainForm }

procedure TMainForm.btnClusterClick(Sender: TObject);
begin
  FTilingEncoder.Run(esReduce);
  UpdateVideo(nil);
end;

procedure TMainForm.btnPreparePalettesClick(Sender: TObject);
begin
  FTilingEncoder.Run(esPreparePalettes);
  UpdateVideo(nil);
end;

procedure TMainForm.btnReconstructClick(Sender: TObject);
begin
  FTilingEncoder.Run(esReconstruct);
  UpdateVideo(nil);
end;

procedure TMainForm.btnGlobalLoadClick(Sender: TObject);
begin
  FTilingEncoder.Run(esLoad);
  UpdateVideo(nil);
end;

procedure TMainForm.btnPredictMotionClick(Sender: TObject);
begin
  FTilingEncoder.Run(esPredict);
  UpdateVideo(nil);
end;

procedure TMainForm.btnDitherClick(Sender: TObject);
begin
  FTilingEncoder.Run(esDither);
  UpdateVideo(nil);
end;

procedure TMainForm.btnReindexClick(Sender: TObject);
begin
  FTilingEncoder.Run(esReindex2);
  UpdateVideo(nil);
end;

procedure TMainForm.btnSaveClick(Sender: TObject);
begin
  FTilingEncoder.Run(esSave);
  UpdateVideo(nil);
end;

procedure TMainForm.btnPMClick(Sender: TObject);
var
  pt: TPoint;
begin
  pt.X := btnPM.Left;
  pt.Y := btnPM.Top + btnPM.Height;
  pt := ClientToScreen(pt);
  pmProcesses.PopUp(pt.X, pt.Y);
end;

procedure TMainForm.imgPaintBackground(ASender: TObject; ACanvas: TCanvas; ARect: TRect);
begin
  ACanvas.Brush.Color := clBlack;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Clear;
end;

procedure TMainForm.imgPaletteContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  if sedPalIdx.Value >= 0 then
  begin
    sedPalIdx.Value := -1;
    Handled := True;
  end;
end;

procedure TMainForm.imgPaletteMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  palIdx, useCount: Integer;
begin
  P := imgPalette.ScreenToClient(Mouse.CursorPos);
  palIdx := Max(0, iDivDef(P.Y, imgPalette.Tag, 0) + sbPalettes.Position);

  if InRange(FTilingEncoder.RenderFrameIndex, 0, High(FTilingEncoder.Frames)) and
      Assigned(FTilingEncoder.Frames[FTilingEncoder.RenderFrameIndex].PKeyFrame) and
      InRange(palIdx, 0, High(FTilingEncoder.Palettes)) then
  begin
    useCount := FTilingEncoder.Palettes[palIdx].UseCount;
    llPalTileDesc.Caption := Format('Palette #: %3d, UseCount: %6d', [palIdx, useCount]);
  end
  else
  begin
    llPalTileDesc.Caption := 'Invalid palette!';
  end;
end;

procedure TMainForm.imgPaletteMouseWheelDown(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
begin
  sbPalettes.Position := EnsureRange(sbPalettes.Position + sbPalettes.LargeChange, 0, Length(FTilingEncoder.Palettes) - sbPalettes.LargeChange);
  Handled := True;
  imgPalette.Invalidate;
end;

procedure TMainForm.imgPaletteMouseWheelUp(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
begin
  sbPalettes.Position := EnsureRange(sbPalettes.Position - sbPalettes.LargeChange, 0, Length(FTilingEncoder.Palettes) - sbPalettes.LargeChange);
  Handled := True;
  imgPalette.Invalidate;
end;

procedure TMainForm.imgPalettePaint(Sender: TObject);
var
  x, y, palCnt, rectSize: Integer;
  C: TCanvas;
  R: TRect;
begin
  C := imgPalette.Canvas;

  rectSize := iDivDef(imgPalette.Width, FTilingEncoder.PaletteSize, 0);
  palCnt := iDivDef(C.ClipRect.Height - 1, rectSize, 0) + 1;

  R.Left := 0;
  R.Top := 0;
  R.Right := rectSize;
  R.Bottom := rectSize;

  C.Brush.Style := bsSolid;
  for y := sbPalettes.Position to sbPalettes.Position + palCnt - 1 do
  begin
    for x := 0 to FTilingEncoder.PaletteSize - 1 do
    begin
      C.Brush.Color := clFuchsia;
      if y < Length(FTilingEncoder.Palettes) then
      begin
        C.Brush.Color := imgPalette.Color;
        if x < Length(FTilingEncoder.Palettes[y].PaletteRGB) then
          C.Brush.Color := FTilingEncoder.Palettes[y].PaletteRGB[x];
      end;
      C.FillRect(R);
      R.Offset(rectSize, 0);
    end;
    R.Offset(-R.Left, rectSize);
  end;

  imgPalette.Tag := rectSize;
end;

procedure TMainForm.imgTilesMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  tileIdx: Integer;
begin
  P := imgTiles.ScreenToClient(Mouse.CursorPos);
  P.X := P.X * imgTiles.Picture.Width div imgTiles.Width;
  P.Y := P.Y * imgTiles.Picture.Height div imgTiles.Height;

  tileIdx := (sbTiles.Position * (imgTiles.Picture.Height shr cTileWidthBits) + (P.Y shr cTileWidthBits)) * (imgTiles.Picture.Width shr cTileWidthBits) + (P.X shr cTileWidthBits);

  if InRange(FTilingEncoder.RenderFrameIndex, 0, High(FTilingEncoder.Frames)) and
      Assigned(FTilingEncoder.Frames[FTilingEncoder.RenderFrameIndex].PKeyFrame) and
      InRange(tileIdx, 0, High(FTilingEncoder.Tiles)) then
    llPalTileDesc.Caption := Format('Page: %4d / %4d, Tile #: %6d, UseCount: %6d%s%s%s', [
        FTilingEncoder.RenderTilePage, FTilingEncoder.RenderTilePageCount - 1,
        tileIdx,
        FTilingEncoder.Tiles[tileIdx]^.UseCount,
        IfThen(FTilingEncoder.Tiles[tileIdx]^.Active, ', [Active]', '          '),
        IfThen(FTilingEncoder.Tiles[tileIdx]^.HMirror_Initial, ', [H]', '     '),
        IfThen(FTilingEncoder.Tiles[tileIdx]^.VMirror_Initial, ', [V]', '     ')])
  else
    llPalTileDesc.Caption := 'Invalid tile!';
end;

procedure TMainForm.imgTilesMouseWheelDown(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
begin
  sbTiles.Position := EnsureRange(sbTiles.Position + sbTiles.LargeChange, 0, FTilingEncoder.RenderTilePageCount - sbTiles.LargeChange);
  Handled := True;
  UpdateVideo(nil);
end;

procedure TMainForm.imgTilesMouseWheelUp(Sender: TObject; Shift: TShiftState; MousePos: TPoint; var Handled: Boolean);
begin
  sbTiles.Position := EnsureRange(sbTiles.Position - sbTiles.LargeChange, 0, FTilingEncoder.RenderTilePageCount - sbTiles.LargeChange);
  Handled := True;
  UpdateVideo(nil);
end;

procedure TMainForm.miGeneratePNGsInputClick(Sender: TObject);
var
  prevCursor: TCursor;
begin
  prevCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FTilingEncoder.GeneratePNGs(True);
  finally
    Screen.Cursor := prevCursor;
  end;

  UpdateVideo(nil);
end;

procedure TMainForm.miGeneratePNGsOutputClick(Sender: TObject);
var
  prevCursor: TCursor;
begin
  prevCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FTilingEncoder.GeneratePNGs(False);
  finally
    Screen.Cursor := prevCursor;
  end;

  UpdateVideo(nil);
end;

procedure TMainForm.miGenerateY4MInputClick(Sender: TObject);
var
  prevCursor: TCursor;
begin
  prevCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FTilingEncoder.GenerateY4M(FTilingEncoder.OutputFileName + '.input.y4m', True);
  finally
    Screen.Cursor := prevCursor;
  end;

  UpdateVideo(nil);
end;

procedure TMainForm.miGenerateY4MOutputClick(Sender: TObject);
var
  prevCursor: TCursor;
begin
  prevCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FTilingEncoder.GenerateY4M(FTilingEncoder.OutputFileName + '.y4m', False);
  finally
    Screen.Cursor := prevCursor;
  end;

  UpdateVideo(nil);
end;

procedure TMainForm.miLoadSettingsClick(Sender: TObject);
begin
  if FileExists(edInput.Text) then
    odSettings.FileName := ChangeFileExt(edInput.Text, '.gtm_settings');
  if odSettings.Execute then
  begin
    FTilingEncoder.LoadSettings(odSettings.FileName);
    LoadGUISettings;
    UpdateGUI(nil);
  end;
end;

procedure TMainForm.miReloadClick(Sender: TObject);
begin
  if odGTM.Execute then
  begin
    FTilingEncoder.ReloadGTM(odGTM.FileName);
    FTilingEncoder.Run(esReindex2);
    LoadGUISettings;
    edOutput.Text := ChangeFileExt(odGTM.FileName, '.reloaded.gtm');
    UpdateVideo(nil);
  end;
end;

procedure TMainForm.miSaveSettingsClick(Sender: TObject);
begin
  if FileExists(edInput.Text) then
    sdSettings.FileName := ChangeFileExt(edInput.Text, '.gtm_settings');
  if sdSettings.Execute then
  begin
    UpdateGUI(nil);
    FTilingEncoder.SaveSettings(sdSettings.FileName);
  end;
end;

procedure TMainForm.sbPalettesChange(Sender: TObject);
begin
  imgPalette.Invalidate;
end;

procedure TMainForm.sbTilesChange(Sender: TObject);
begin

end;

procedure TMainForm.screenClick(Sender: TObject);
begin
  tbFrame.SetFocus;
end;

procedure TMainForm.btnRunAllClick(Sender: TObject);
var
  firstStep: TEncoderStep;
  lastStep: TEncoderStep;
begin
  btnRunAll.SetFocus;

  firstStep := TEncoderStep(cbxStartStep.ItemIndex);
  lastStep := TEncoderStep(cbxEndStep.ItemIndex);

  FTilingEncoder.RunRange(firstStep, lastStep);
  UpdateVideo(nil);
end;

procedure TMainForm.btnInputClick(Sender: TObject);
begin
  odFFInput.InitialDir := ExtractFileDir(edInput.Text);
  if odFFInput.Execute then
  begin
    if (edOutput.Text = '') or (edOutput.Text = ChangeFileExt(edInput.Text, '.gtm')) then
    begin
      edOutput.Text := ChangeFileExt(odFFInput.FileName, '.gtm');
      sdGTM.FileName := edOutput.Text;
    end;
    edInput.Text := odFFInput.FileName;
  end;
end;

procedure TMainForm.btnGTMClick(Sender: TObject);
begin
  if sdGTM.Execute then
    edOutput.Text := sdGTM.FileName;
end;

procedure TMainForm.btnDebugClick(Sender: TObject);
begin
  edInput.Text := ExtractFileDrive(Application.ExeName) + '\tiler_misc\Star.Wars.Despecialized.Edition.v2.5.avi';
  edOutput.Text := ExtractFilePath(Application.ExeName) + 'debug.gtm';
  seFrameCount.Value := IfThen(seFrameCount.Value >= 12, IfThen(seFrameCount.Value = 12, 48, 2), 12);
  cbxScaling.ItemIndex := 4;
  cbxPalCount.Text := '256';
  cbxMPRadius.Text := '128';

  FTilingEncoder.Test;

  UpdateGUI(nil);
end;

procedure TMainForm.btnDebug2Click(Sender: TObject);
begin
  edInput.Text := ExtractFileDrive(Application.ExeName) + '\tiler_misc\sunflower_1080p25.y4m';
  edOutput.Text :=  ExtractFilePath(Application.ExeName) + 'debug.gtm';
  seFrameCount.Value := IfThen(seFrameCount.Value >= 12, IfThen(seFrameCount.Value = 12, 24, 2), 12);
  cbxScaling.ItemIndex := 2;
  cbxPalCount.Text := '256';
  cbxMPRadius.Text := '128';

  FTilingEncoder.Test;

  UpdateGUI(nil);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  k: Word;
  i: Integer;
begin
  k := Key;
  if k in [VK_F10, VK_F11, VK_F12, VK_PRIOR, VK_NEXT] then
    Key := 0; // KLUDGE: workaround event called twice
  case k of
    VK_F10: btnRunAllClick(nil);
    VK_F11: chkPlay.Checked := not chkPlay.Checked;
    VK_F12:
    begin
      if ssCtrl in Shift then
      begin
        btnDebugClick(nil);
      end
      else if ssAlt in Shift then
      begin
        btnDebug2Click(nil);
      end
      else
      begin
        if pcPages.ActivePage <> FLastIOTabSheet then
        begin
          if Assigned(FLastIOTabSheet) then
           pcPages.ActivePage := FLastIOTabSheet
          else
           pcPages.ActivePage := tsOutput;
        end
        else
        begin
          if pcPages.ActivePage = tsOutput then
           pcPages.ActivePage := tsInput
          else
           pcPages.ActivePage := tsOutput;
        end;
        UpdateVideo(nil);
      end;
    end;
    VK_PRIOR, VK_NEXT:
    begin
      for i := 0 to FTilingEncoder.KeyFrameCount - 1 do
        if InRange(tbFrame.Position, FTilingEncoder.KeyFrames[i].StartFrame, FTilingEncoder.KeyFrames[i].EndFrame) then
        begin
          if (k = VK_PRIOR) and (tbFrame.Position > FTilingEncoder.KeyFrames[i].StartFrame) then
            tbFrame.Position := FTilingEncoder.KeyFrames[i].StartFrame
          else if (k = VK_NEXT) and (tbFrame.Position >= FTilingEncoder.KeyFrames[FTilingEncoder.KeyFrameCount - 1].StartFrame) then
            tbFrame.Position := FTilingEncoder.KeyFrames[FTilingEncoder.KeyFrameCount - 1].EndFrame
          else
            tbFrame.Position := FTilingEncoder.KeyFrames[EnsureRange(i + IfThen(k = VK_NEXT, 1, -1), 0, FTilingEncoder.KeyFrameCount - 1)].StartFrame;
          Break;
        end;
      tbFrame.SetFocus;
    end;
    VK_CONTROL:
      tbFrame.LineSize := round(FTilingEncoder.FramesPerSecond);
  end;
end;

procedure TMainForm.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_CONTROL then
    tbFrame.LineSize := 1;
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

    FLockChanges := True;
    try
      tbFrame.Position := tbFrame.Position + 1;
    finally
      FLockChanges := False;
    end;

    UpdateVideo(nil);
  end;
end;

procedure TMainForm.imgContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  pt: TPoint;
begin
  pt := TImage(Sender).ScreenToClient(Mouse.CursorPos);

  pt.X -= (TImage(Sender).Width - FTilingEncoder.ScreenWidth) div 2;
  pt.Y -= (TImage(Sender).Height - FTilingEncoder.ScreenHeight) div 2;

  Handled := InRange(pt.X, 0, FTilingEncoder.ScreenWidth - 1) and InRange(pt.Y, 0, FTilingEncoder.ScreenHeight - 1) and (sedPalIdx.Value >= 0);

  if Handled then
    sedPalIdx.Value := -1;
end;

procedure TMainForm.imgPaletteClick(Sender: TObject);
var
  palIdx: Integer;
  P: TPoint;
begin
  P := imgPalette.ScreenToClient(Mouse.CursorPos);

  palIdx := Max(0, iDivDef(P.Y, imgPalette.Tag, 0) + sbPalettes.Position);
  if palIdx < Length(FTilingEncoder.Palettes) then
  begin
    sedPalIdx.Value := palIdx;
    FTilingEncoder.RenderPaletteIndex := palIdx;
  end;
end;

procedure TMainForm.tbFrameChange(Sender: TObject);
begin
  if FLockChanges then
    Exit;

  tiTrackbar.Enabled := False;
  tiTrackbar.Enabled := True;
end;

procedure TMainForm.tiTrackbarTimer(Sender: TObject);
begin
  tiTrackbar.Enabled := False;
  UpdateVideo(nil);
end;

procedure TMainForm.UpdateVideo(Sender: TObject);
begin
  UpdateGUI(Sender);

  FTilingEncoder.Render;

  imgSource.Picture.Bitmap := FTilingEncoder.InputBitmap;
  imgDest.Picture.Bitmap := FTilingEncoder.OutputBitmap;
  imgTiles.Picture.Bitmap := FTilingEncoder.TilesBitmap;

  pnLbl.Caption := FTilingEncoder.RenderTitleText;
  lblCorrel.Caption := FormatFloat('##0.000000', FTilingEncoder.RenderPsychoVisualQuality);
end;

procedure TMainForm.UpdateGUI(Sender: TObject);
var
  i: Integer;
  prevCursor: TCursor;
begin
  if FLockChanges then
    Exit;

  prevCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    tbFrame.Min := 0;
    tbFrame.Max := FTilingEncoder.FrameCount - 1;
    IdleTimer.Interval := round(1000 / FTilingEncoder.FramesPerSecond);
    FLastIOTabSheet := pcPages.ActivePage;

    FTilingEncoder.InputFileName := edInput.Text;
    FTilingEncoder.OutputFileName := edOutput.Text;
    FTilingEncoder.StartFrame := seStartFrame.Value;
    FTilingEncoder.FrameCountSetting := seFrameCount.Value;
    FTilingEncoder.PaletteCount := StrToIntDef(cbxPalCount.Text, 1);
    FTilingEncoder.PaletteSize := StrToIntDef(cbxPalSize.Text, 2);
    FTilingEncoder.Scaling := StrToFloatDef(cbxScaling.Text, 1.0, InvariantFormatSettings);

    FTilingEncoder.RenderPlaying := chkPlay.Checked;
    FTilingEncoder.RenderFrameIndex := Max(0, tbFrame.Position);
    FTilingEncoder.RenderPredicted := chkPredicted.Checked;
    FTilingEncoder.RenderMirrored := chkMirrored.Checked;
    FTilingEncoder.RenderOutputDithered := chkDitheredO.Checked;
    FTilingEncoder.RenderUseGamma := chkGamma.Checked;
    FTilingEncoder.RenderPaletteIndex := sedPalIdx.Value;
    FTilingEncoder.RenderTilePage := sbTiles.Position;
    FTilingEncoder.RenderGammaValue := seVisGamma.Value;

    FTilingEncoder.MotionPredictRadius := StrToIntDef(cbxMPRadius.Text, 0);
    FTilingEncoder.MotionPredictMaxBufferedFrames := StrToIntDef(cbxMPMBF.Text, 0);
    FTilingEncoder.MotionPredictBlendingMode := TBlendingMode(cbxBlendingMode.ItemIndex);

    FTilingEncoder.ReduceQuality := tbQuality.Position;

    FTilingEncoder.DitheringMode := TPsyVisMode(cbxDitheringMode.ItemIndex);
    FTilingEncoder.DitheringYliluoma2MixedColors := StrToIntDef(cbxYilMix.Text, 1);
    FTilingEncoder.DitheringUseThomasKnoll := chkUseTK.Checked;

    FTilingEncoder.ShotTransMinSecondsPerKF := seShotTransMinSecondsPerKF.Value;
    FTilingEncoder.ShotTransMaxSecondsPerKF := seShotTransMaxSecondsPerKF.Value;
    FTilingEncoder.ShotTransCorrelLoThres := seShotTransCorrelLoThres.Value;

    if pcPages.ActivePage = tsInput then
    begin
      if FTilingEncoder.RenderPage <> rpInput then
        tbFrame.SetFocus;
      FTilingEncoder.RenderPage := rpInput
    end
    else if pcPages.ActivePage = tsOutput then
    begin
      if FTilingEncoder.RenderPage <> rpOutput then
        tbFrame.SetFocus;
      FTilingEncoder.RenderPage := rpOutput
    end
    else if pcPages.ActivePage = tsTilesPal then
    begin
      FTilingEncoder.RenderPage := rpTiles
    end
    else
    begin
      FTilingEncoder.RenderPage := rpNone;
    end;

    FTilingEncoder.MaxThreadCount := seMaxCores.Value;

    sedPalIdx.MaxValue := FTilingEncoder.PaletteCount - 1;
    imgSource.Stretch := chkStretch.State in [cbGrayed, cbChecked];
    imgDest.Stretch := imgSource.Stretch;
    imgSource.Proportional := chkStretch.State = cbGrayed;
    imgDest.Proportional := imgSource.Proportional;
    tbFrame.PageSize := Round(FTilingEncoder.FramesPerSecond);
    sbPalettes.Max := Max(0, Length(FTilingEncoder.Palettes) - sbPalettes.LargeChange);
    sbTiles.Max := FTilingEncoder.RenderTilePageCount - sbTiles.LargeChange;
    lblQuality.Caption := IntToStr(FTilingEncoder.ReduceQuality) + ' %';

    if FTrackbarTickCount <> FTilingEncoder.KeyFrameCount then
    begin
      tbFrame.HandleNeeded;
      tbFrame.TickStyle := tsNone;
      tbFrame.TickStyle := tsManual;
      for i := 0 to FTilingEncoder.KeyFrameCount - 1 do
          tbFrame.SetTick(FTilingEncoder.KeyFrames[i].StartFrame);
      FTrackbarTickCount := FTilingEncoder.KeyFrameCount;
    end;

  finally
    Screen.Cursor := prevCursor;
  end;
end;

procedure TMainForm.TilingEncoderProgress(ASender: TTilingEncoder; APosition, AMax: Integer; AHourGlass: Boolean);
begin
  pbProgress.Max := AMax;
  pbProgress.Position := APosition;
  lblPct.Caption := IntToStr(pbProgress.Position * 100 div pbProgress.Max) + '%';

  if AHourGlass then
    Screen.Cursor := crHourGlass
  else
    Screen.Cursor := crDefault;

  Invalidate;
  Repaint;
end;

procedure TMainForm.LoadGUISettings;
begin
  FLockChanges := True;
  try
   edInput.Text := FTilingEncoder.InputFileName;
   edOutput.Text := FTilingEncoder.OutputFileName;
   seStartFrame.Value := FTilingEncoder.StartFrame;
   seFrameCount.Value := FTilingEncoder.FrameCountSetting;
   cbxScaling.Text := FloatToStr(FTilingEncoder.Scaling);

   cbxPalSize.Text := IntToStr(FTilingEncoder.PaletteSize);
   cbxPalCount.Text := IntToStr(FTilingEncoder.PaletteCount);

   cbxMPRadius.Text := IntToStr(FTilingEncoder.MotionPredictRadius);
   cbxMPMBF.Text := IntToStr(FTilingEncoder.MotionPredictMaxBufferedFrames);
   cbxBlendingMode.ItemIndex := Ord(FTilingEncoder.MotionPredictBlendingMode);

   tbQuality.Position := FTilingEncoder.ReduceQuality;

   cbxDitheringMode.ItemIndex := Ord(FTilingEncoder.DitheringMode);
   chkUseTK.Checked := FTilingEncoder.DitheringUseThomasKnoll;
   cbxYilMix.Text := IntToStr(FTilingEncoder.DitheringYliluoma2MixedColors);

   seVisGamma.Value := FTilingEncoder.RenderGammaValue;
   seMaxCores.Value := FTilingEncoder.MaxThreadCount;

   seShotTransMinSecondsPerKF.Value := FTilingEncoder.ShotTransMinSecondsPerKF;
   seShotTransMaxSecondsPerKF.Value := FTilingEncoder.ShotTransMaxSecondsPerKF;
   seShotTransCorrelLoThres.Value := FTilingEncoder.ShotTransCorrelLoThres;
  finally
    FLockChanges := False;
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  pvs: TPsyVisMode;
  es: TEncoderStep;
  ver: TFileVersionInfo;
begin
  ver := TFileVersionInfo.Create(nil);
  try
    ver.ReadFileInfo;
    Caption := Caption + ' ' + ver.VersionStrings.Values['FileVersion'] + ' (' + StringReplace({$I %DATE%}, '/', '', [rfReplaceAll]) + ')';
  finally
    ver.Free;
  end;

  FormatSettings := InvariantFormatSettings;
  FTilingEncoder := TTilingEncoder.Create;
  FTilingEncoder.OnProgress := @TilingEncoderProgress;

  Constraints.MinHeight := Height;
  Constraints.MinWidth := Width;
  pcPages.ActivePage := tsSettings;

  FTrackbarTickCount := -1;

  FLockChanges := True;
  try
    for es := Succ(Low(TEncoderStep)) to High(TEncoderStep) do
    begin
      cbxStartStep.AddItem(Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(es)), 3), TObject(PtrInt(Ord(es))));
      cbxEndStep.AddItem(Copy(GetEnumName(TypeInfo(TEncoderStep), Ord(es)), 3), TObject(PtrInt(Ord(es))));
    end;
    cbxStartStep.ItemIndex := Ord(Succ(Low(TEncoderStep)));
    cbxEndStep.ItemIndex := Ord(High(TEncoderStep));

    for pvs := Low(TPsyVisMode) to High(TPsyVisMode) do
      cbxDitheringMode.AddItem(Copy(GetEnumName(TypeInfo(TPsyVisMode), Ord(pvs)), 4), TObject(PtrInt(Ord(pvs))));

    seMaxCores.MaxValue := NumberOfProcessors + QuarterNumberOfProcessors;
  finally
    FLockChanges := False;
  end;

  LoadGUISettings;

  UpdateVideo(nil);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FTilingEncoder.Free;
end;

end.

