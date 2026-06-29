// from https://github.com/CippoX/apple-silicon-kmeans/blob/main/LMD-K-means-Clustering-Algorithm/kmeans/parallel-mini-batch-kmeans.cpp
// ported to freepascal using AI
// improved by GliGli

unit ParallelMiniBatchKMeans;

{$mode objfpc}{$H+}
{$CODEALIGN LOCALMIN=16}

interface

uses
  Classes, SysUtils, Math, Types, fgl, mtpool, utils;

type
  { TParallelMiniBatchKMeans }

  TParallelMiniBatchKMeans = class
  type
    TFloat = Double;
    TFloatVector = array of TFloat;
    TDCTVector = array[0 .. cTileDCTSize - 1] of TFloat;
  private
    images: TDCTDynArray;
    weights: TCardinalDynArray;
    numberOfCentroids: Integer;
    miniBatchSize: Integer;
    clusters: TIntegerDynArray;
    vX: array of UInt64;
    centroids: TDCTDynArray;
    miniBatch: TIntegerDynArray;
    numberOfThreads: Cardinal;
    mtPool: TMTPool;
    rngMB: TKRng;
    verbose: Boolean;
    function MinimumEuclideanDistance(const v1, v2: TDCT; minDist: Cardinal): Cardinal;
    function EuclideanDistance(const v1, v2: TDCT): Cardinal;
    function OptimizedCalculateCentroidFromIndexes(const vectorIndexes: TIntegerDynArray): TDCTVector;
    function IndexOfClosestCentroid(const point: TDCT): Integer;
    function ReturnClusterElementsIndexes(const cluster: Integer): TIntegerDynArray;
    function ReturnMiniBatchClusterElementsIndexes(const cluster: Integer; var weightsSum: UInt64): TIntegerDynArray;
    function MeanClusteringError: Double;
    procedure SelectMiniBatch(k: Integer);
    procedure InitFarthestFirst;
    procedure AssignWholeDataset;
    procedure AssignmentStep;
    procedure UpdateStep;
  public
    constructor Create(const _images: TDCTDynArray; var _weights: TCardinalDynArray;
      _numberOfCentroids, _miniBatchSize: Integer; _numberOfThreads: Cardinal; _verbose: Boolean);
    destructor Destroy; override;
    procedure Run(var _clusters: TIntegerDynArray);
  end;

implementation

constructor TParallelMiniBatchKMeans.Create(const _images: TDCTDynArray; var _weights: TCardinalDynArray;
  _numberOfCentroids, _miniBatchSize: Integer; _numberOfThreads: Cardinal; _verbose: Boolean);
var
  i: Integer;
begin
  images := _images;
  weights := _weights;
  numberOfCentroids := _numberOfCentroids;
  miniBatchSize := _miniBatchSize;
  numberOfThreads := _numberOfThreads;
  verbose := _verbose;

  SetLength(clusters, Length(images));
  for i := 0 to High(clusters) do
    clusters[i] := Integer(-1);

  SetLength(vX, numberOfCentroids);
  for i := 0 to High(vX) do
    vX[i] := 0;

  mtPool := TMTPool.Create(_numberOfThreads);
  rngMB.init();
end;

destructor TParallelMiniBatchKMeans.Destroy;
begin
  mtPool.Free;

  inherited Destroy;
end;

function TParallelMiniBatchKMeans.MinimumEuclideanDistance(const v1, v2: TDCT; minDist: Cardinal): Cardinal;
begin
  Result := minDist;
  if QuickTestEuclideanDCTPtr_asm(@v1[0], @v2[0], minDist) then
    Result := CompareEuclideanDCTPtr_asm(@v1[0], @v2[0]);
end;

function TParallelMiniBatchKMeans.EuclideanDistance(const v1, v2: TDCT): Cardinal;
begin
  Result := CompareEuclideanDCTPtr_asm(@v1[0], @v2[0]);
end;

function TParallelMiniBatchKMeans.OptimizedCalculateCentroidFromIndexes(const vectorIndexes: TIntegerDynArray): TDCTVector;
var
  weightsSum, w: Int64;
  wmean: TDCTVector;
  i, j, vectorIndex: Integer;
  invWeightsSum: TFloat;
begin
  FillChar(wmean, SizeOf(wmean), 0);

  if Length(vectorIndexes) = 0 then
    Exit(wmean);

  weightsSum := 0;
  for i := 0 to High(vectorIndexes) do
  begin
    vectorIndex := vectorIndexes[i];

    w := weights[vectorIndex];
    weightsSum += w;

    for j := 0 to cTileDCTSize - 1 do
      wmean[j] := wmean[j] + w * images[vectorIndex][j];
  end;

  invWeightsSum := 1.0 / weightsSum;
  for i := 0 to cTileDCTSize - 1 do
    wmean[i] := wmean[i] * invWeightsSum;

  Result := wmean;
end;

function TParallelMiniBatchKMeans.IndexOfClosestCentroid(const point: TDCT): Integer;
var
  minimumDistance, distanceFromCentroid: Cardinal;
  index: Integer;
  i: Integer;
begin
  minimumDistance := High(Cardinal);
  index := 0;
  for i := 0 to High(centroids) do
  begin
    distanceFromCentroid := MinimumEuclideanDistance(point, centroids[i], minimumDistance);
    if distanceFromCentroid < minimumDistance then
    begin
      minimumDistance := distanceFromCentroid;
      index := i;
    end;
  end;
  Result := index;
end;

function TParallelMiniBatchKMeans.ReturnClusterElementsIndexes(const cluster: Integer): TIntegerDynArray;
var
  tempArray: TIntegerDynArray;
  i, count: Integer;
begin
  SetLength(tempArray, Length(clusters));
  count := 0;
  for i := 0 to High(clusters) do
    if clusters[i] = cluster then
    begin
      tempArray[count] := i;
      Inc(count);
    end;
  SetLength(tempArray, count);
  Result := tempArray;
end;

function TParallelMiniBatchKMeans.ReturnMiniBatchClusterElementsIndexes(
  const cluster: Integer; var weightsSum: UInt64): TIntegerDynArray;
var
  tempArray: TIntegerDynArray;
  i, idx, count: Integer;
begin
  SetLength(tempArray, Length(miniBatch));
  count := 0;
  weightsSum := 0;
  for i := 0 to High(miniBatch) do
  begin
    idx := miniBatch[i];
    if clusters[idx] = cluster then
    begin
      tempArray[count] := idx;
      Inc(count);
      Inc(weightsSum, weights[idx]);
    end;
  end;
  SetLength(tempArray, count);
  Result := tempArray;
end;

function TParallelMiniBatchKMeans.MeanClusteringError: Double;
var
  imageDists: array of Double;

  procedure DoImage(Index: PtrInt; Data: Pointer);
  begin
    imageDists[Index] := EuclideanDistance(images[Index], centroids[clusters[Index]]);
  end;

begin
  SetLength(imageDists, Length(images));

  mtPool.DoLocalProc(@DoImage, 0, High(images));

  Result := Mean(imageDists);
end;

procedure TParallelMiniBatchKMeans.SelectMiniBatch(k: Integer);
var
  auxVector: TIntegerDynArray;
  i, j: UInt64;
  temp: Integer;
begin
  SetLength(auxVector, Length(images));
  for i := 0 to High(auxVector) do
    auxVector[i] := i;

  for i := High(auxVector) downto 1 do
  begin
    j := rngMB.randInt() mod (i + 1);
    temp := auxVector[i];
    auxVector[i] := auxVector[j];
    auxVector[j] := temp;
  end;

  SetLength(auxVector, k);
  miniBatch := auxVector;
end;

procedure TParallelMiniBatchKMeans.InitFarthestFirst;
var
  lastCentroid: Integer;
  minDistances: array of Int64;

  procedure DoImage(Index: PtrInt; Data: Pointer);
  var
    d: Int64;
  begin
    d := MinimumEuclideanDistance(images[Index], centroids[lastCentroid], minDistances[Index] div weights[Index]);
    minDistances[Index] := Min(minDistances[Index], d * weights[Index]);
  end;

var
  first, pct, lastPct: Integer;
  c, i: Integer;
  v, farthest: Int64;
  nextCentroidIndex: Integer;
  chosen: TBooleanDynArray;
begin
  SetLength(centroids, numberOfCentroids);
  SetLength(minDistances, Length(images));
  SetLength(chosen, Length(images));

  for i := 0 to High(minDistances) do
    minDistances[i] := High(Cardinal);

  first := 0;
  centroids[0] := images[first];
  lastPct := 0;
  lastCentroid := 0;

  for c := 1 to numberOfCentroids - 1 do
  begin
    mtPool.DoLocalProc(@DoImage, 0, High(images));

    farthest := 0;
    nextCentroidIndex := -1;
    for i := 0 to High(minDistances) do
    begin
      v := minDistances[i];
      if (v > farthest) and not chosen[i] then
      begin
        farthest := v;
        nextCentroidIndex := i;
      end;
    end;

    centroids[c] := images[nextCentroidIndex];
    chosen[nextCentroidIndex] := True;
    lastCentroid := c;

    pct := Round((c + 1) * 100.0 / numberOfCentroids);
    if pct > lastPct then
    begin
      Write('Init... ', pct:3, '%', #13);
      lastPct := pct;
    end;
  end;
end;

procedure TParallelMiniBatchKMeans.AssignWholeDataset;

  procedure DoImg(Index: PtrInt; Data: Pointer);
  begin
    clusters[Index] := IndexOfClosestCentroid(images[Index]);
  end;

begin
  mtPool.DoLocalProc(@DoImg, 0, High(images));
end;

procedure TParallelMiniBatchKMeans.AssignmentStep;

  procedure DoMB(Index: PtrInt; Data: Pointer);
  var
    targetIdx: Integer;
  begin
    targetIdx := miniBatch[Index];
    clusters[targetIdx] := IndexOfClosestCentroid(images[targetIdx]);
  end;

begin
  mtPool.DoLocalProc(@DoMB, 0, High(miniBatch));
end;

procedure TParallelMiniBatchKMeans.UpdateStep;

  procedure DoCentroid(Index: PtrInt; Data: Pointer);
  var
    j: Integer;
    batchIdxs: TIntegerDynArray;
    batchWSum: UInt64;
    eta: TFloat;
    batchWMean: TFloatVector;
  begin
    batchIdxs := ReturnMiniBatchClusterElementsIndexes(Index, batchWSum);
    if batchWSum = 0 then
      Exit;

    vX[Index] := vX[Index] + batchWSum;
    eta := batchWSum / vX[Index];
    batchWMean := OptimizedCalculateCentroidFromIndexes(batchIdxs);

    for j := 0 to cTileDCTSize - 1 do
      centroids[Index][j] := Round((1.0 - eta) * centroids[Index][j] + eta * batchWMean[j]);
  end;

begin
  mtPool.DoLocalProc(@DoCentroid, 0, High(centroids));
end;

procedure TParallelMiniBatchKMeans.Run(var _clusters: TIntegerDynArray);
var
  iClus, iteration: Integer;
  delta: Double;
  errorValue: Double;
  previousError: Double;
begin
  InitFarthestFirst;
  AssignWholeDataset;

  delta := Infinity;
  previousError := Infinity;
  iteration := 0;

  while True do
  begin
    SelectMiniBatch(miniBatchSize);
    AssignmentStep;
    UpdateStep;

    errorValue := EuclideanToPSNR(MeanClusteringError);

    if not IsInfinite(delta) and not IsInfinite(previousError) then
      delta := lerp(delta, errorValue - previousError, 0.05);

    if IsInfinite(delta) and not IsInfinite(previousError) then
      delta := errorValue - previousError;

    previousError := errorValue;

    Inc(iteration);

    Write('Iteration: ', iteration:6, ', Error: ', errorValue:12:6, ', Delta: ', delta:12:6, #13);
    if verbose then
      WriteLn;

    if Abs(delta) < cPSNRPrecision then
      Break;
  end;

  AssignWholeDataset;

  if not verbose then
    WriteLn
  else
    WriteLn('Number of iterations: ', iteration:4);

  SetLength(_clusters, Length(clusters));
  for iClus := 0 to High(clusters) do
    _clusters[iClus] := clusters[iClus];
end;

end.
