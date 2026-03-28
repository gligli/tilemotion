"use strict";

const GTMHeader = {
	'FourCC' : 0, // ASCII "GTMv"
	'RIFFSize' : 1,
	'WholeHeaderSize' : 2, // including TGTMKeyFrameInfo and all
	'EncoderVersion' : 3,
	'FramePixelWidth' : 4,
	'FramePixelHeight' : 5,
	'KFCount' : 6,
	'FrameCount' : 7,
	'AverageBytesPerSec' : 8,
	'KFMaxBytesPerSec' : 9,
	'PSNRHVS' : 10
}; 

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
//
// (insert new commands here...)
//
// FrameEnd:                         data -> none; commandBits -> none (11 bits); keyframe end (1 bit)
// LoadPalette:                      data -> palette index (16 bits); { RGBA bytes (32bits) } * indexes count; commandBits -> palette format (0: RGBA32) (6 bits); indexes count per palette - 1 (6 bits)
// TileSet:                          data -> start tile (32 bits); end tile (32 bits); { palette index (16 bits) } * count; { indexes per pixel (64 bytes) } * count; commandBits -> none (11 bits); is keyframe tileset (1 bit)
// SetDimensions:                    data -> width in tiles (32 bits); height in tiles (32 bits); frame length in nanoseconds (32 bits) (2^32-1: still frame); global tile count (32 bits); maximum key frame tile count (32 bits); commandBits -> none (12 bits)
// ExtendedCommand:                  data -> following bytes count (32 bits); custom commands, proprietary extensions, ...; commandBits -> extended command index (12 bits)

const GTMCommand = {
    'PredictedTileOffsets6x6' : 0,
    'PredictedTileOffsets8x8' : 1,
    'PredictedTileBlending8x8' : 2,
    'PredictedOffsetBlock0x0' : 3,
    'GlobalTile16' : 4,
    'GlobalTile32' : 5,
    'KeyFrmTile16' : 6,
    'KeyFrmTile32' : 7,

    'FrameEnd' : 11,
    'LoadPalette' : 12,
    'TileSet' : 13,
    'SetDimensions' : 14,
    'ExtendedCommand' : 15    
}; 

const CTileWidth = 8;
const CTMAttrBits = 1 + 1 + 10; // HMir + VMir + PalIdx
const CShortIdxBits = 16 - CTMAttrBits;
const CTileSize = CTileWidth * CTileWidth;
const CMaxPaletteCount = 65536;
const CMaxTMBuffers = 4;

let gtmWLZMA = null;

let gtmCanvasId = '';
let gtmInBuffer = null;
let gtmOutStream = null;
let gtmHeader = null;
let gtmTiles = new Array(2);
let gtmTilePalIdxs = new Array(2);
let gtmTileCount = new Uint32Array(2);
let gtmPaletteR = new Array(CMaxPaletteCount);
let gtmPaletteG = new Array(CMaxPaletteCount);
let gtmPaletteB = new Array(CMaxPaletteCount);
let gtmPaletteA = new Array(CMaxPaletteCount);
let gtmTMBuffers = new Array(CMaxTMBuffers);
let gtmTMBufIdxs = new Uint8Array(CMaxTMBuffers);
let gtmFrameInterval = null;

let gtmAwaitingCanvasId = ''
let gtmAwaitingFile = null
let gtmAwaitingURL = null

let gtmReady = false;
let gtmPlaying = true;
let gtmUnpackingFinished = false;
let gtmDataBufIdx = 0;
let gtmDataBufPos = 0;
let gtmDataBufGlobalPos = 0;
let gtmWidth = 0;
let gtmHeight = 0;
let gtmFrameLength = 0;
let gtmPalSize = 0;
let gtmTMPos = 0;
let gtmLoopCount = 0;

function gtmPlayFromFile(file, canvasId) {
	if (gtmReady) {
		gtmAwaitingCanvasId = canvasId
		gtmAwaitingFile = file
		gtmAwaitingURL = null
	} else {
		resetDecoding();

		gtmCanvasId = canvasId;
		
		var oReader = new FileReader();
		
		oReader.onload = function (oEvent) {
			startFromReader(oReader.result);
		};
		
		oReader.readAsArrayBuffer(file);
	}
}

function gtmPlayFromURL(url, canvasId) {
	if (gtmReady) {
		gtmAwaitingCanvasId = canvasId
		gtmAwaitingFile = null
		gtmAwaitingURL = url
	} else {
		resetDecoding();

		gtmCanvasId = canvasId;
		
		var oReq = new XMLHttpRequest();
		oReq.open("GET", url, true);
		oReq.responseType = "arraybuffer";
		
		oReq.onload = function (oEvent) {
			startFromReader(oReq.response);
		};
		
		oReq.send(null);
	}
}

function gtmSetPlaying(playing) {
	gtmPlaying = playing;
}

function resetDecoding() {
	if (gtmFrameInterval != null) {
		clearInterval(gtmFrameInterval);
		gtmFrameInterval = null;
	}
	gtmWLZMA = new WLZMA.Manager(1, URL.createObjectURL(new Blob(["("+worker_function.toString()+")(\""+ document.URL +"\")"], {type: 'text/javascript'})));
	
	gtmCanvasId = '';
	gtmInBuffer = null;
	gtmOutStream = null;
	gtmHeader = null;
	gtmTiles[0] = null;
	gtmTiles[1] = null;
	gtmTilePalIdxs[0] = null;
	gtmTilePalIdxs[1] = null;
	gtmTileCount[0] = 0;
	gtmTileCount[1] = 0;
	
	gtmReady = false;
	gtmUnpackingFinished = false;
	gtmDataBufIdx = 0;
	gtmDataBufPos = 0;
	gtmDataBufGlobalPos = 0;
	gtmFrameLength = 0;
	gtmPalSize = 0;
	gtmTMPos = 0;
	gtmLoopCount = 0;
}

function startFromReader(buffer) {
	gtmInBuffer = parseHeader(buffer);
	gtmOutStream = new LZMA.oStream();

	// invoke asynchronous decoding of the first keyframe (EOS terminated)
	gtmWLZMA.decode(gtmInBuffer)
	.then(function (outStream) {
		unpackNextKeyframe();
		
		if (!gtmReady) {
			gtmDataBufIdx = 0;
			gtmDataBufPos = 0;
			gtmDataBufGlobalPos = 0;
			gtmReady = true;
			setTimeout(decodeFrame, 10);
		}

	})
	.catch(function(err) {
		throw new Error(err.message);
	})	
}

function getHeaderDWord(stream) {
	let v = stream.readByte();
	v |= stream.readByte() << 8;
	v |= stream.readByte() << 16;
	v |= stream.readByte() << 24;
	return v;
}

function parseHeader(buffer) {
	let stream = new LZMA.iStream(buffer)
	
	let fcc = getHeaderDWord(stream);
	
	if (fcc == 0x764D5447) { // "GTMv"; file header
		let hdrsize = getHeaderDWord(stream);
		let whlsize = getHeaderDWord(stream);
		
		gtmHeader = new Array(whlsize >>> 2);
		gtmHeader[GTMHeader.FourCC] = fcc;
		gtmHeader[GTMHeader.RIFFSize] = hdrsize;
		gtmHeader[GTMHeader.WholeHeaderSize] = whlsize;
		for (let p = GTMHeader.WholeHeaderSize + 1; p < whlsize >>> 2; p++) {
			gtmHeader[p] = getHeaderDWord(stream);
		}
		
		gtmWidth = (gtmHeader[GTMHeader.FramePixelWidth] / CTileWidth) >>> 0;
		gtmHeight = (gtmHeader[GTMHeader.FramePixelHeight] / CTileWidth) >>> 0;
		console.log('Header:', gtmHeader[GTMHeader.FramePixelWidth], 'x', gtmHeader[GTMHeader.FramePixelHeight], ',',
			Math.round(gtmHeader[GTMHeader.AverageBytesPerSec] * 8 / 1024), 'KBps (average)', ',',
			Math.round(gtmHeader[GTMHeader.KFMaxBytesPerSec] * 8 / 1024), 'KBps (max)', ',',
			gtmHeader[GTMHeader.PSNRHVS] / (1000 * 1000), 'PSNR-HVS (global)');
		
		stream.offset = whlsize; // position on start of LZMA bitstream
		
		redimFrame();
	} else {
		stream.offset -= 4;
	}
	
	buffer = buffer.slice(stream.offset, buffer.length); // remove header from buffer
	return buffer;
}

function unpackNextKeyframe() {
	if (gtmWLZMA.nextStreams.length <= 0) {
		return;
	}
	
	if (gtmWLZMA.nextStreams.length >= 1 && gtmWLZMA.nextStreams[gtmWLZMA.nextStreams.length - 1] == null) {
		gtmWLZMA.nextStreams.pop();
		console.log('Finished Unpacking LZMA');
		gtmUnpackingFinished = true;
		return;
	}
	
	let outStream = gtmWLZMA.nextStreams.shift();
	
	for (let i = 0; i < outStream.buffers.length; ++i) {
		gtmOutStream.buffers.push(outStream.buffers[i]);
	}
	gtmOutStream.size += outStream.size;
}

function redimFrame() {
	var frame = document.getElementById(gtmCanvasId);
	
	if (frame.width != gtmWidth * CTileWidth || frame.height != gtmHeight * CTileWidth) {
		frame.width = gtmWidth * CTileWidth;
		frame.height = gtmHeight * CTileWidth;
		
		var canvas = frame.getContext('2d');
		canvas.fillStyle = 'black';
		canvas.fillRect(0, 0, frame.width, frame.height);

		for (let bufIdx = 0; bufIdx < CMaxTMBuffers; bufIdx++) {
			gtmTMBuffers[bufIdx] = canvas.getImageData(0, 0, frame.width, frame.height);
			gtmTMBufIdxs[bufIdx] = CMaxTMBuffers - 1 - bufIdx;
		}
	}
}

function renderEnd() {
	if (gtmWidth * gtmHeight == 0) {
		return;
	}
	
	var frame = document.getElementById(gtmCanvasId);
	var canvas = frame.getContext('2d');
	canvas.putImageData(gtmTMBuffers[gtmTMBufIdxs[0]], 0, 0);
}

function drawTilemapItem(idx, attrs, iskf) {
	let palIdx = gtmTilePalIdxs[iskf][idx];
	let tOff = idx * CTileSize;
	let palR = gtmPaletteR[palIdx];
	let palG = gtmPaletteG[palIdx];
	let palB = gtmPaletteB[palIdx];
	let palA = gtmPaletteA[palIdx];
	
	let x = (gtmTMPos % gtmWidth) * CTileWidth;
	let y = Math.trunc(gtmTMPos / gtmWidth) * CTileWidth;
	let p = (y * gtmWidth * CTileWidth + x) * 4;
	var data = gtmTMBuffers[gtmTMBufIdxs[0]].data;
	
	for (let ty = 0; ty < CTileWidth; ty++) {
		let tym = ty * CTileWidth;
		if (attrs & 2) tym = CTileSize - CTileWidth - tym;

		for (let tx = 0; tx < CTileWidth; tx++) {
			let txm = tx;
			if (attrs & 1) txm = CTileWidth - 1 - txm;
			
			let v = gtmTiles[iskf][tOff + tym + txm];
			data[p++] = palR[v]; 
			data[p++] = palG[v]; 
			data[p++] = palB[v]; 
			data[p++] = palA[v]; 
		}

		p += (gtmWidth - 1) * CTileWidth * 4;
	}
	
	gtmTMPos++;
}

function drawPredictedTilemapItem(offsetY, offsetX, backBufOff) {
	var data = gtmTMBuffers[gtmTMBufIdxs[0]].data;
	var prevData = gtmTMBuffers[gtmTMBufIdxs[backBufOff]].data;

	let x = (gtmTMPos % gtmWidth) * CTileWidth;
	let y = Math.trunc(gtmTMPos / gtmWidth) * CTileWidth;
	let p = (y * gtmWidth * CTileWidth + x) * 4;
	let o = p + (offsetY * gtmWidth * CTileWidth + offsetX) * 4;
	
	for (let ty = 0; ty < CTileWidth; ty++) {
		for (let tx = 0; tx < CTileWidth; tx++) {
			data[p++] = prevData[o++];
			data[p++] = prevData[o++];
			data[p++] = prevData[o++];
			data[p++] = prevData[o++];
		}
		p += (gtmWidth - 1) * CTileWidth * 4;
		o += (gtmWidth - 1) * CTileWidth * 4;
	}

	gtmTMPos++;
}

function drawWeightedTilemapItem(weight, backBufOff) {
	var data = gtmTMBuffers[gtmTMBufIdxs[0]].data;
	var dataM1 = gtmTMBuffers[gtmTMBufIdxs[backBufOff]].data;

	let weightM1 = 256 + weight;
	let x = (gtmTMPos % gtmWidth) * CTileWidth;
	let y = Math.trunc(gtmTMPos / gtmWidth) * CTileWidth;
	let p = (y * gtmWidth * CTileWidth + x) * 4;
	
	for (let ty = 0; ty < CTileWidth; ty++) {
		for (let tx = 0; tx < CTileWidth; tx++) {
			data[p] = Math.max(Math.min((dataM1[p] * weightM1 + 128) >>> 8, 255), 0); p++;
			data[p] = Math.max(Math.min((dataM1[p] * weightM1 + 128) >>> 8, 255), 0); p++;
			data[p] = Math.max(Math.min((dataM1[p] * weightM1 + 128) >>> 8, 255), 0); p++;
			data[p] = dataM1[p]; p++;
		}
		p += (gtmWidth - 1) * CTileWidth * 4;
	}

	gtmTMPos++;
}

function drawBlendedTilemapItem(weight, alpha, backBufOff) {
	var data = gtmTMBuffers[gtmTMBufIdxs[0]].data;
	var dataM1 = gtmTMBuffers[gtmTMBufIdxs[backBufOff]].data;
	var dataM2 = gtmTMBuffers[gtmTMBufIdxs[backBufOff + 1]].data;

	let weightM1 = (256 + weight) * (256 - alpha);
	let weightM2 = (256 + weight) * alpha;
	let x = (gtmTMPos % gtmWidth) * CTileWidth;
	let y = Math.trunc(gtmTMPos / gtmWidth) * CTileWidth;
	let p = (y * gtmWidth * CTileWidth + x) * 4;
	
	for (let ty = 0; ty < CTileWidth; ty++) {
		for (let tx = 0; tx < CTileWidth; tx++) {
			data[p] = Math.max(Math.min((dataM1[p] * weightM1 + dataM2[p] * weightM2 + 32768) >>> 16, 255), 0); p++;
			data[p] = Math.max(Math.min((dataM1[p] * weightM1 + dataM2[p] * weightM2 + 32768) >>> 16, 255), 0); p++;
			data[p] = Math.max(Math.min((dataM1[p] * weightM1 + dataM2[p] * weightM2 + 32768) >>> 16, 255), 0); p++;
			data[p] = (dataM1[p] * (256 - alpha) + dataM2[p] * alpha + 128) >>> 8; p++;
		}
		p += (gtmWidth - 1) * CTileWidth * 4;
	}

	gtmTMPos++;
}

function skipBlock(skipCount) {
	for(let s = 0; s < skipCount; s++)
	{
		drawPredictedTilemapItem(0, 0, 1);
	}
}

function readBuffer_Unsafe(buffer, offset, size) {
	buffer.set(gtmOutStream.buffers[gtmDataBufIdx].slice(gtmDataBufPos, gtmDataBufPos + size), offset);
	
	gtmDataBufPos += size;
	
	if (gtmDataBufPos >= gtmOutStream.buffers[gtmDataBufIdx].length)
	{
		// move to next buffer
		++gtmDataBufIdx;
		gtmDataBufPos = 0;
	}
	
	gtmDataBufGlobalPos += size;
}

function readByte() {
	let v = gtmOutStream.buffers[gtmDataBufIdx][gtmDataBufPos++];
	
	if (gtmDataBufPos >= gtmOutStream.buffers[gtmDataBufIdx].length)
	{
		// move to next buffer
		++gtmDataBufIdx;
		gtmDataBufPos = 0;
	}
	
	++gtmDataBufGlobalPos;
	
	return v;
}

function readWord() {
	let v = readByte();
	v |= readByte() << 8;
	return v;
}

function readDWord() {
	let v = readWord();
	v |= readWord() << 16;
	return v;
}

function readCommand() {
	let v = readWord();
	return [v & ((1 << CShortIdxBits) - 1), v >>> CShortIdxBits];
}

function decodeFrame() {
	gtmReady |= gtmDataBufGlobalPos < gtmOutStream.size;
	
	if (gtmReady && gtmPlaying) {
		renderEnd();
		
		let doContinue = true;
		do {
			let cmd = readCommand();
			
			// console.log('command @' + gtmDataBufGlobalPos + ': ' + cmd + '\n');
			
			switch (cmd[0]) {
			case GTMCommand.SetDimensions:
				gtmWidth = readDWord();
				gtmHeight = readDWord();
				gtmFrameLength = Math.round(readDWord() / (1000 * 1000));
				gtmTileCount[0] = readDWord();
				gtmTileCount[1] = readDWord();
				console.log('GlobalTileCount:', gtmTileCount[0], ',', 'KFMaxTileCount:', gtmTileCount[1]);
				
				if (gtmLoopCount <= 0) {
					gtmFrameInterval = setInterval(decodeFrame, gtmFrameLength);
					gtmTiles[0] = new Uint8Array(gtmTileCount[0] * CTileSize);
					gtmTiles[1] = new Uint8Array(gtmTileCount[1] * CTileSize);
					gtmTilePalIdxs[0] = new Uint16Array(gtmTileCount[0]);
					gtmTilePalIdxs[1] = new Uint16Array(gtmTileCount[1]);
					redimFrame();
				}
				break;
				
			case GTMCommand.LoadPalette:
				gtmPalSize = cmd[1] + 1;
				let palIdx = readWord();
				
				gtmPaletteR[palIdx] = new Uint8Array(gtmPalSize);
				gtmPaletteG[palIdx] = new Uint8Array(gtmPalSize);
				gtmPaletteB[palIdx] = new Uint8Array(gtmPalSize);
				gtmPaletteA[palIdx] = new Uint8Array(gtmPalSize);
				
				for (let i = 0; i < gtmPalSize; i++) {
					gtmPaletteR[palIdx][i] = readByte();
					gtmPaletteG[palIdx][i] = readByte();
					gtmPaletteB[palIdx][i] = readByte();
					gtmPaletteA[palIdx][i] = readByte();
				}
				break;
				
			case GTMCommand.TileSet:
				let isKFTileSet = (cmd[1] != 0) ? 1 : 0;
				let tstart = readDWord();
				let tend = readDWord();
				let tcnt = gtmTileCount[isKFTileSet];
				let tiles = gtmTiles[isKFTileSet];
				let tlpal = gtmTilePalIdxs[isKFTileSet];

				for (let p = tstart; p <= tend; p++) {
					tlpal[p] = readWord();
				}

				readBuffer_Unsafe(tiles, tstart * CTileSize, (tend - tstart + 1) * CTileSize);
				break;
				
			case GTMCommand.FrameEnd:
				if (gtmTMPos != gtmWidth * gtmHeight) {
					console.error('Incomplete tilemap ' + gtmTMPos + ' <> ' + gtmWidth * gtmHeight + '\n');
				}
				gtmTMPos = 0;

				for (let bufIdx = 0; bufIdx < CMaxTMBuffers; bufIdx++) {
					gtmTMBufIdxs[bufIdx] = (gtmTMBufIdxs[bufIdx] + 1) % CMaxTMBuffers;
				}
				doContinue = false;
				break;
				
			case GTMCommand.PredictedOffsetBlock0x0:
				skipBlock(cmd[1] + 1);
				break;

			case GTMCommand.GlobalTile16:
				drawTilemapItem(readWord(), cmd[1], 0);
				break;
				
			case GTMCommand.KeyFrmTile16:
				drawTilemapItem(readWord(), cmd[1], 1);
				break;
				
			case GTMCommand.GlobalTile32:
				drawTilemapItem(readDWord(), cmd[1], 0);
				break;
				
			case GTMCommand.KeyFrmTile32:
				drawTilemapItem(readDWord(), cmd[1], 1);
				break;
				
			case GTMCommand.PredictedTileOffsets6x6:
				drawPredictedTilemapItem(((cmd[1] >>> 6) & 31) - ((cmd[1] >>> 6) & 32), (cmd[1] & 31) - (cmd[1] & 32), 1);
				break;

			case GTMCommand.PredictedTileOffsets8x8:
				let offsetX = readByte();
				let offsetY = readByte();
				drawPredictedTilemapItem((offsetY & 127) - (offsetY & 128), (offsetX & 127) - (offsetX & 128), cmd[1] + 1);
				break;
				
			case GTMCommand.PredictedTileBlending8x8:
				let blendWeight = readByte();
				let blendAlpha = readByte();
				
				blendWeight = (blendWeight & 127) - (blendWeight & 128);
				
				if (blendAlpha) {
					drawBlendedTilemapItem(blendWeight, blendAlpha, cmd[1] + 1);
				} else {
					drawWeightedTilemapItem(blendWeight, cmd[1] + 1);
				}
				break;
				
			case GTMCommand.ExtendedCommand:
				let size = readDWord();
				let settings = '';
				for (let i = 0; i < size; i++) {
					settings += String.fromCharCode(readByte());
				}
				if (cmd[1] == 0 && gtmLoopCount <= 0) {
					console.log(settings);
				}
				break;
			
			default:
				console.error('Undecoded command @' + gtmDataBufGlobalPos + ': ' + cmd + '\n');
				break;
			}

			gtmReady = gtmDataBufGlobalPos < gtmOutStream.size;
		} while (doContinue && gtmReady);
		
		if (!doContinue && !gtmReady && gtmUnpackingFinished) {
			gtmDataBufIdx = 0;
			gtmDataBufPos = 0;
			gtmDataBufGlobalPos = 0;
			gtmLoopCount++;
			gtmReady = true;
		}
	}
	
	unpackNextKeyframe();
	
	if(gtmAwaitingFile != null || gtmAwaitingURL != null) {
		console.log('Processing awaiting video...');

		gtmReady = false;
		if (gtmAwaitingFile != null)
		{
			gtmPlayFromFile(gtmAwaitingFile, gtmAwaitingCanvasId)
		} else if (gtmAwaitingURL != null) {
			gtmPlayFromURL(gtmAwaitingURL, gtmAwaitingCanvasId)
		}

		gtmAwaitingCanvasId = ''
		gtmAwaitingFile = null
		gtmAwaitingURL = null
	}
}
