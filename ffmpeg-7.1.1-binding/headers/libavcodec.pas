(*
 * copyright (c) 2001 Fabrice Bellard
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(**
 * @file
 * @ingroup libavc
 * Libavcodec external API header
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavcodec/avcodec.h
 * Ported by CodeCoolie@CNSW 2008/03/17 -> $Date:: 2025-11-03 #$
 *)

(*
FFmpeg Delphi/Pascal Headers and Examples License Agreement

A modified part of FFVCL - Delphi FFmpeg VCL Components.
Copyright (c) 2008-2025 DelphiFFmpeg.com
All rights reserved.
http://www.DelphiFFmpeg.com

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

This source code is provided "as is" by DelphiFFmpeg.com without
warranty of any kind, either expressed or implied, including but not
limited to the implied warranties of merchantability and/or fitness
for a particular purpose.

Please also notice the License agreement of FFmpeg libraries.
*)

unit libavcodec;

interface

{$I CompilerDefines.inc}

uses
  libavcodec_codec,
  libavcodec_codec_defs,
  libavcodec_codec_desc,
  libavcodec_codec_id,
  libavcodec_codec_par,
  libavcodec_packet,
  libavutil,
  libavutil_buffer,
  libavutil_channel_layout,
  libavutil_dict,
  libavutil_frame,
  libavutil_log,
  libavutil_pixfmt,
  libavutil_rational,
  libavutil_samplefmt,
  FFTypes;

{$I libversion.inc}

(**
 * @defgroup libavc libavcodec
 * Encoding/Decoding Library
 *
 * @{
 *
 * @defgroup lavc_decoding Decoding
 * @{
 * @}
 *
 * @defgroup lavc_encoding Encoding
 * @{
 * @}
 *
 * @defgroup lavc_codec Codecs
 * @{
 * @defgroup lavc_codec_native Native Codecs
 * @{
 * @}
 * @defgroup lavc_codec_wrappers External library wrappers
 * @{
 * @}
 * @defgroup lavc_codec_hwaccel Hardware Accelerators bridge
 * @{
 * @}
 * @}
 * @defgroup lavc_internal Internal
 * @{
 * @}
 * @}
 *)

(**
 * @ingroup libavc
 * @defgroup lavc_encdec send/receive encoding and decoding API overview
 * @{
 *
 * The avcodec_send_packet()/avcodec_receive_frame()/avcodec_send_frame()/
 * avcodec_receive_packet() functions provide an encode/decode API, which
 * decouples input and output.
 *
 * The API is very similar for encoding/decoding and audio/video, and works as
 * follows:
 * - Set up and open the AVCodecContext as usual.
 * - Send valid input:
 *   - For decoding, call avcodec_send_packet() to give the decoder raw
 *     compressed data in an AVPacket.
 *   - For encoding, call avcodec_send_frame() to give the encoder an AVFrame
 *     containing uncompressed audio or video.
 *
 *   In both cases, it is recommended that AVPackets and AVFrames are
 *   refcounted, or libavcodec might have to copy the input data. (libavformat
 *   always returns refcounted AVPackets, and av_frame_get_buffer() allocates
 *   refcounted AVFrames.)
 * - Receive output in a loop. Periodically call one of the avcodec_receive_*()
 *   functions and process their output:
 *   - For decoding, call avcodec_receive_frame(). On success, it will return
 *     an AVFrame containing uncompressed audio or video data.
 *   - For encoding, call avcodec_receive_packet(). On success, it will return
 *     an AVPacket with a compressed frame.
 *
 *   Repeat this call until it returns AVERROR(EAGAIN) or an error. The
 *   AVERROR(EAGAIN) return value means that new input data is required to
 *   return new output. In this case, continue with sending input. For each
 *   input frame/packet, the codec will typically return 1 output frame/packet,
 *   but it can also be 0 or more than 1.
 *
 * At the beginning of decoding or encoding, the codec might accept multiple
 * input frames/packets without returning a frame, until its internal buffers
 * are filled. This situation is handled transparently if you follow the steps
 * outlined above.
 *
 * In theory, sending input can result in EAGAIN - this should happen only if
 * not all output was received. You can use this to structure alternative decode
 * or encode loops other than the one suggested above. For example, you could
 * try sending new input on each iteration, and try to receive output if that
 * returns EAGAIN.
 *
 * End of stream situations. These require "flushing" (aka draining) the codec,
 * as the codec might buffer multiple frames or packets internally for
 * performance or out of necessity (consider B-frames).
 * This is handled as follows:
 * - Instead of valid input, send NULL to the avcodec_send_packet() (decoding)
 *   or avcodec_send_frame() (encoding) functions. This will enter draining
 *   mode.
 * - Call avcodec_receive_frame() (decoding) or avcodec_receive_packet()
 *   (encoding) in a loop until AVERROR_EOF is returned. The functions will
 *   not return AVERROR(EAGAIN), unless you forgot to enter draining mode.
 * - Before decoding can be resumed again, the codec has to be reset with
 *   avcodec_flush_buffers().
 *
 * Using the API as outlined above is highly recommended. But it is also
 * possible to call functions outside of this rigid schema. For example, you can
 * call avcodec_send_packet() repeatedly without calling
 * avcodec_receive_frame(). In this case, avcodec_send_packet() will succeed
 * until the codec's internal buffer has been filled up (which is typically of
 * size 1 per output frame, after initial input), and then reject input with
 * AVERROR(EAGAIN). Once it starts rejecting input, you have no choice but to
 * read at least some output.
 *
 * Not all codecs will follow a rigid and predictable dataflow; the only
 * guarantee is that an AVERROR(EAGAIN) return value on a send/receive call on
 * one end implies that a receive/send call on the other end will succeed, or
 * at least will not fail with AVERROR(EAGAIN). In general, no codec will
 * permit unlimited buffering of input or output.
 *
 * A codec is not allowed to return AVERROR(EAGAIN) for both sending and receiving. This
 * would be an invalid state, which could put the codec user into an endless
 * loop. The API has no concept of time either: it cannot happen that trying to
 * do avcodec_send_packet() results in AVERROR(EAGAIN), but a repeated call 1 second
 * later accepts the packet (with no other receive/flush API calls involved).
 * The API is a strict state machine, and the passage of time is not supposed
 * to influence it. Some timing-dependent behavior might still be deemed
 * acceptable in certain cases. But it must never result in both send/receive
 * returning EAGAIN at the same time at any point. It must also absolutely be
 * avoided that the current state is "unstable" and can "flip-flop" between
 * the send/receive APIs allowing progress. For example, it's not allowed that
 * the codec randomly decides that it actually wants to consume a packet now
 * instead of returning a frame, after it just returned AVERROR(EAGAIN) on an
 * avcodec_send_packet() call.
 * @}
 *)

(**
 * @defgroup lavc_core Core functions/structures.
 * @ingroup libavc
 *
 * Basic definitions, functions for querying libavcodec capabilities,
 * allocating core structures, etc.
 * @{
 *)

{$IFDEF FF_API_BUFFER_MIN_SIZE}
const
(**
 * @ingroup lavc_encoding
 * minimum encoding buffer size
 * Used to avoid some checks during header writing.
 * @deprecated Unused: avcodec_receive_packet() does not work
 *             with preallocated packet buffers.
 *)
  AV_INPUT_BUFFER_MIN_SIZE = 16384;
{$ENDIF}

type
(**
 * @ingroup lavc_encoding
 *)
  PRcOverride = ^TRcOverride;
  TRcOverride = record // SizeOf = 16
    start_frame: Integer;
    end_frame: Integer;
    qscale: Integer; // If this is 0 then quality_factor will be used instead.
    quality_factor: Single;
  end;

(* encoding support
   These flags can be passed in AVCodecContext.flags before initialization.
   Note: Not everything is supported yet.
*)

const
(**
 * Allow decoders to produce frames with data planes that are not aligned
 * to CPU requirements (e.g. due to cropping).
 *)
  AV_CODEC_FLAG_UNALIGNED       = (1 shl  0);
(**
 * Use fixed qscale.
 *)
  AV_CODEC_FLAG_QSCALE          = (1 shl  1);
(**
 * 4 MV per MB allowed / advanced prediction for H.263.
 *)
  AV_CODEC_FLAG_4MV             = (1 shl  2);
(**
 * Output even those frames that might be corrupted.
 *)
  AV_CODEC_FLAG_OUTPUT_CORRUPT  = (1 shl  3);
(**
 * Use qpel MC.
 *)
  AV_CODEC_FLAG_QPEL            = (1 shl  4);
{$IFDEF FF_API_DROPCHANGED}
(**
 * Don't output frames whose parameters differ from first
 * decoded frame in stream.
 *
 * @deprecated callers should implement this functionality in their own code
 *)
  AV_CODEC_FLAG_DROPCHANGED     = (1 shl  5);
{$ENDIF}
(**
 * Request the encoder to output reconstructed frames, i.e.\ frames that would
 * be produced by decoding the encoded bistream. These frames may be retrieved
 * by calling avcodec_receive_frame() immediately after a successful call to
 * avcodec_receive_packet().
 *
 * Should only be used with encoders flagged with the
 * @ref AV_CODEC_CAP_ENCODER_RECON_FRAME capability.
 *
 * @note
 * Each reconstructed frame returned by the encoder corresponds to the last
 * encoded packet, i.e. the frames are returned in coded order rather than
 * presentation order.
 *
 * @note
 * Frame parameters (like pixel format or dimensions) do not have to match the
 * AVCodecContext values. Make sure to use the values from the returned frame.
 *)
  AV_CODEC_FLAG_RECON_FRAME     = (1 shl  6);
(**
 * @par decoding
 * Request the decoder to propagate each packet's AVPacket.opaque and
 * AVPacket.opaque_ref to its corresponding output AVFrame.
 *
 * @par encoding:
 * Request the encoder to propagate each frame's AVFrame.opaque and
 * AVFrame.opaque_ref values to its corresponding output AVPacket.
 *
 * @par
 * May only be set on encoders that have the
 * @ref AV_CODEC_CAP_ENCODER_REORDERED_OPAQUE capability flag.
 *
 * @note
 * While in typical cases one input frame produces exactly one output packet
 * (perhaps after a delay), in general the mapping of frames to packets is
 * M-to-N, so
 * - Any number of input frames may be associated with any given output packet.
 *   This includes zero - e.g. some encoders may output packets that carry only
 *   metadata about the whole stream.
 * - A given input frame may be associated with any number of output packets.
 *   Again this includes zero - e.g. some encoders may drop frames under certain
 *   conditions.
 * .
 * This implies that when using this flag, the caller must NOT assume that
 * - a given input frame's opaques will necessarily appear on some output packet;
 * - every output packet will have some non-NULL opaque value.
 * .
 * When an output packet contains multiple frames, the opaque values will be
 * taken from the first of those.
 *
 * @note
 * The converse holds for decoders, with frames and packets switched.
 *)
  AV_CODEC_FLAG_COPY_OPAQUE     = (1 shl  7);
(**
 * Signal to the encoder that the values of AVFrame.duration are valid and
 * should be used (typically for transferring them to output packets).
 *
 * If this flag is not set, frame durations are ignored.
 *)
  AV_CODEC_FLAG_FRAME_DURATION  = (1 shl  8);
(**
 * Use internal 2pass ratecontrol in first pass mode.
 *)
  AV_CODEC_FLAG_PASS1           = (1 shl  9);
(**
 * Use internal 2pass ratecontrol in second pass mode.
 *)
  AV_CODEC_FLAG_PASS2           = (1 shl 10);
(**
 * loop filter.
 *)
  AV_CODEC_FLAG_LOOP_FILTER     = (1 shl 11);
(**
 * Only decode/encode grayscale.
 *)
  AV_CODEC_FLAG_GRAY            = (1 shl 13);
(**
 * error[?] variables will be set during encoding.
 *)
  AV_CODEC_FLAG_PSNR            = (1 shl 15);
(**
 * Use interlaced DCT.
 *)
  AV_CODEC_FLAG_INTERLACED_DCT  = (1 shl 18);
(**
 * Force low delay.
 *)
  AV_CODEC_FLAG_LOW_DELAY       = (1 shl 19);
(**
 * Place global headers in extradata instead of every keyframe.
 *)
  AV_CODEC_FLAG_GLOBAL_HEADER   = (1 shl 22);
(**
 * Use only bitexact stuff (except (I)DCT).
 *)
  AV_CODEC_FLAG_BITEXACT        = (1 shl 23);
(* Fx : Flag for H.263+ extra options *)
(**
 * H.263 advanced intra coding / MPEG-4 AC prediction
 *)
  AV_CODEC_FLAG_AC_PRED         = (1 shl 24);
(**
 * interlaced motion estimation
 *)
  AV_CODEC_FLAG_INTERLACED_ME   = (1 shl 29);
  AV_CODEC_FLAG_CLOSED_GOP      = (1 shl 31);

(**
 * Allow non spec compliant speedup tricks.
 *)
  AV_CODEC_FLAG2_FAST           = (1 shl  0);
(**
 * Skip bitstream encoding.
 *)
  AV_CODEC_FLAG2_NO_OUTPUT      = (1 shl  2);
(**
 * Place global headers at every keyframe instead of in extradata.
 *)
  AV_CODEC_FLAG2_LOCAL_HEADER   = (1 shl  3);

(**
 * Input bitstream might be truncated at a packet boundaries
 * instead of only at frame boundaries.
 *)
  AV_CODEC_FLAG2_CHUNKS         = (1 shl 15);
(**
 * Discard cropping information from SPS.
 *)
  AV_CODEC_FLAG2_IGNORE_CROP    = (1 shl 16);

(**
 * Show all frames before the first keyframe
 *)
  AV_CODEC_FLAG2_SHOW_ALL       = (1 shl 22);
(**
 * Export motion vectors through frame side data
 *)
  AV_CODEC_FLAG2_EXPORT_MVS     = (1 shl 28);
(**
 * Do not skip samples and export skip information as frame side data
 *)
  AV_CODEC_FLAG2_SKIP_MANUAL    = (1 shl 29);
(**
 * Do not reset ASS ReadOrder field on flush (subtitles decoding)
 *)
  AV_CODEC_FLAG2_RO_FLUSH_NOOP  = (1 shl 30);
(**
 * Generate/parse ICC profiles on encode/decode, as appropriate for the type of
 * file. No effect on codecs which cannot contain embedded ICC profiles, or
 * when compiled without support for lcms2.
 *)
  AV_CODEC_FLAG2_ICC_PROFILES   = (1 shl 31);

(* Exported side data.
   These flags can be passed in AVCodecContext.export_side_data before initialization.
*)
(**
 * Export motion vectors through frame side data
 *)
  AV_CODEC_EXPORT_DATA_MVS      = (1 shl 0);
(**
 * Export encoder Producer Reference Time through packet side data
 *)
  AV_CODEC_EXPORT_DATA_PRFT     = (1 shl 1);
(**
 * Decoding only.
 * Export the AVVideoEncParams structure through frame side data.
 *)
  AV_CODEC_EXPORT_DATA_VIDEO_ENC_PARAMS = (1 shl 2);
(**
 * Decoding only.
 * Do not apply film grain, export it instead.
 *)
  AV_CODEC_EXPORT_DATA_FILM_GRAIN = (1 shl 3);

(**
 * Decoding only.
 * Do not apply picture enhancement layers, export them instead.
 *)
  AV_CODEC_EXPORT_DATA_ENHANCEMENTS = (1 shl 4);

(**
 * The decoder will keep a reference to the frame and may reuse it later.
 *)
  AV_GET_BUFFER_FLAG_REF = (1 shl 0);

(**
 * The encoder will keep a reference to the packet and may reuse it later.
 *)
  AV_GET_ENCODE_BUFFER_FLAG_REF = (1 shl 0);

const
  // AVCodecContext.workaround_bugs
  FF_BUG_AUTODETECT       = 1;  ///< autodetection
  FF_BUG_XVID_ILACE       = 4;
  FF_BUG_UMP4             = 8;
  FF_BUG_NO_PADDING       = 16;
  FF_BUG_AMV              = 32;
  FF_BUG_QPEL_CHROMA      = 64;
  FF_BUG_STD_QPEL         = 128;
  FF_BUG_QPEL_CHROMA2     = 256;
  FF_BUG_DIRECT_BLOCKSIZE = 512;
  FF_BUG_EDGE             = 1024;
  FF_BUG_HPEL_CHROMA      = 2048;
  FF_BUG_DC_CLIP          = 4096;
  FF_BUG_MS               = 8192; ///< Work around various bugs in Microsoft's broken decoders.
  FF_BUG_TRUNCATED        = 16384;
  FF_BUG_IEDGE            = 32768;

  // AVCodecContext.dct_algo
  FF_DCT_AUTO    = 0;
  FF_DCT_FASTINT = 1;
  FF_DCT_INT     = 2;
  FF_DCT_MMX     = 3;
  FF_DCT_ALTIVEC = 5;
  FF_DCT_FAAN    = 6;
  FF_DCT_NEON    = 7;

  // AVCodecContext.idct_algo
  FF_IDCT_AUTO          = 0;
  FF_IDCT_INT           = 1;
  FF_IDCT_SIMPLE        = 2;
  FF_IDCT_SIMPLEMMX     = 3;
  FF_IDCT_ARM           = 7;
  FF_IDCT_ALTIVEC       = 8;
  FF_IDCT_SIMPLEARM     = 10;
  FF_IDCT_XVID          = 14;
  FF_IDCT_SIMPLEARMV5TE = 16;
  FF_IDCT_SIMPLEARMV6   = 17;
  FF_IDCT_FAAN          = 20;
  FF_IDCT_SIMPLENEON    = 22;
  FF_IDCT_SIMPLEAUTO    = 128;

  // AVCodecContext.error_concealment
  FF_EC_GUESS_MVS   = 1;
  FF_EC_DEBLOCK     = 2;
  FF_EC_FAVOR_INTER = 256;

  // AVCodecContext.debug
  FF_DEBUG_PICT_INFO   = 1;
  FF_DEBUG_RC          = 2;
  FF_DEBUG_BITSTREAM   = 4;
  FF_DEBUG_MB_TYPE     = 8;
  FF_DEBUG_QP          = 16;
  FF_DEBUG_DCT_COEFF   = $00000040;
  FF_DEBUG_SKIP        = $00000080;
  FF_DEBUG_STARTCODE   = $00000100;
  FF_DEBUG_ER          = $00000400;
  FF_DEBUG_MMCO        = $00000800;
  FF_DEBUG_BUGS        = $00001000;
  FF_DEBUG_BUFFERS     = $00008000;
  FF_DEBUG_THREADS     = $00010000;
  FF_DEBUG_GREEN_MD    = $00800000;
  FF_DEBUG_NOMC        = $01000000;

  // AVCodecContext.properties
  FF_CODEC_PROPERTY_LOSSLESS        = $00000001;
  FF_CODEC_PROPERTY_CLOSED_CAPTIONS = $00000002;
  FF_CODEC_PROPERTY_FILM_GRAIN      = $00000004;

  // AVCodecContext.ildct_cmp
  FF_CMP_SAD        = 0;
  FF_CMP_SSE        = 1;
  FF_CMP_SATD       = 2;
  FF_CMP_DCT        = 3;
  FF_CMP_PSNR       = 4;
  FF_CMP_BIT        = 5;
  FF_CMP_RD         = 6;
  FF_CMP_ZERO       = 7;
  FF_CMP_VSAD       = 8;
  FF_CMP_VSSE       = 9;
  FF_CMP_NSSE       = 10;
  FF_CMP_W53        = 11;
  FF_CMP_W97        = 12;
  FF_CMP_DCTMAX     = 13;
  FF_CMP_DCT264     = 14;
  FF_CMP_MEDIAN_SAD = 15;
  FF_CMP_CHROMA     = 256;

  // AVCodecContext.slice_flags
  SLICE_FLAG_CODED_ORDER    = $0001; ///< draw_horiz_band() is called in coded order instead of display
  SLICE_FLAG_ALLOW_FIELD    = $0002; ///< allow draw_horiz_band() with field slices (MPEG-2 field pics)
  SLICE_FLAG_ALLOW_PLANE    = $0004; ///< allow draw_horiz_band() with 1 component at a time (SVQ1)

  // AVCodecContext.mb_decision
  FF_MB_DECISION_SIMPLE = 0;        ///< uses mb_cmp
  FF_MB_DECISION_BITS   = 1;        ///< chooses the one which needs the fewest bits
  FF_MB_DECISION_RD     = 2;        ///< rate distortion

  // AVCodecContext.compression_level
  FF_COMPRESSION_DEFAULT = -1;

{$IFDEF FF_API_FF_PROFILE_LEVEL}
  // AVCodecContext.profile
  (** @deprecated The following defines are deprecated; use AV_PROFILE_*
   * in defs.h instead. *)
  FF_PROFILE_UNKNOWN  = -99;
  FF_PROFILE_RESERVED = -100;

  FF_PROFILE_AAC_MAIN = 0;
  FF_PROFILE_AAC_LOW  = 1;
  FF_PROFILE_AAC_SSR  = 2;
  FF_PROFILE_AAC_LTP  = 3;
  FF_PROFILE_AAC_HE   = 4;
  FF_PROFILE_AAC_HE_V2 = 28;
  FF_PROFILE_AAC_LD   = 22;
  FF_PROFILE_AAC_ELD  = 38;
  FF_PROFILE_MPEG2_AAC_LOW = 128;
  FF_PROFILE_MPEG2_AAC_HE  = 131;

  FF_PROFILE_DNXHD       = 0;
  FF_PROFILE_DNXHR_LB    = 1;
  FF_PROFILE_DNXHR_SQ    = 2;
  FF_PROFILE_DNXHR_HQ    = 3;
  FF_PROFILE_DNXHR_HQX   = 4;
  FF_PROFILE_DNXHR_444   = 5;

  FF_PROFILE_DTS               = 20;
  FF_PROFILE_DTS_ES            = 30;
  FF_PROFILE_DTS_96_24         = 40;
  FF_PROFILE_DTS_HD_HRA        = 50;
  FF_PROFILE_DTS_HD_MA         = 60;
  FF_PROFILE_DTS_EXPRESS       = 70;
  FF_PROFILE_DTS_HD_MA_X       = 61;
  FF_PROFILE_DTS_HD_MA_X_IMAX  = 62;


  FF_PROFILE_EAC3_DDP_ATMOS        = 30;

  FF_PROFILE_TRUEHD_ATMOS          = 30;

  FF_PROFILE_MPEG2_422    = 0;
  FF_PROFILE_MPEG2_HIGH   = 1;
  FF_PROFILE_MPEG2_SS     = 2;
  FF_PROFILE_MPEG2_SNR_SCALABLE = 3;
  FF_PROFILE_MPEG2_MAIN   = 4;
  FF_PROFILE_MPEG2_SIMPLE = 5;

  FF_PROFILE_H264_CONSTRAINED = (1 shl 9);  // 8+1; constraint_set1_flag
  FF_PROFILE_H264_INTRA       = (1 shl 11); // 8+3; constraint_set3_flag

  FF_PROFILE_H264_BASELINE             = 66;
  FF_PROFILE_H264_CONSTRAINED_BASELINE = (66 or FF_PROFILE_H264_CONSTRAINED);
  FF_PROFILE_H264_MAIN                 = 77;
  FF_PROFILE_H264_EXTENDED             = 88;
  FF_PROFILE_H264_HIGH                 = 100;
  FF_PROFILE_H264_HIGH_10              = 110;
  FF_PROFILE_H264_HIGH_10_INTRA        = (110 or FF_PROFILE_H264_INTRA);
  FF_PROFILE_H264_MULTIVIEW_HIGH       = 118;
  FF_PROFILE_H264_HIGH_422             = 122;
  FF_PROFILE_H264_HIGH_422_INTRA       = (122 or FF_PROFILE_H264_INTRA);
  FF_PROFILE_H264_STEREO_HIGH          = 128;
  FF_PROFILE_H264_HIGH_444             = 144;
  FF_PROFILE_H264_HIGH_444_PREDICTIVE  = 244;
  FF_PROFILE_H264_HIGH_444_INTRA       = (244 or FF_PROFILE_H264_INTRA);
  FF_PROFILE_H264_CAVLC_444            = 44;

  FF_PROFILE_VC1_SIMPLE   = 0;
  FF_PROFILE_VC1_MAIN     = 1;
  FF_PROFILE_VC1_COMPLEX  = 2;
  FF_PROFILE_VC1_ADVANCED = 3;

  FF_PROFILE_MPEG4_SIMPLE                    =  0;
  FF_PROFILE_MPEG4_SIMPLE_SCALABLE           =  1;
  FF_PROFILE_MPEG4_CORE                      =  2;
  FF_PROFILE_MPEG4_MAIN                      =  3;
  FF_PROFILE_MPEG4_N_BIT                     =  4;
  FF_PROFILE_MPEG4_SCALABLE_TEXTURE          =  5;
  FF_PROFILE_MPEG4_SIMPLE_FACE_ANIMATION     =  6;
  FF_PROFILE_MPEG4_BASIC_ANIMATED_TEXTURE    =  7;
  FF_PROFILE_MPEG4_HYBRID                    =  8;
  FF_PROFILE_MPEG4_ADVANCED_REAL_TIME        =  9;
  FF_PROFILE_MPEG4_CORE_SCALABLE             = 10;
  FF_PROFILE_MPEG4_ADVANCED_CODING           = 11;
  FF_PROFILE_MPEG4_ADVANCED_CORE             = 12;
  FF_PROFILE_MPEG4_ADVANCED_SCALABLE_TEXTURE = 13;
  FF_PROFILE_MPEG4_SIMPLE_STUDIO             = 14;
  FF_PROFILE_MPEG4_ADVANCED_SIMPLE           = 15;

  FF_PROFILE_JPEG2000_CSTREAM_RESTRICTION_0  = 1;
  FF_PROFILE_JPEG2000_CSTREAM_RESTRICTION_1  = 2;
  FF_PROFILE_JPEG2000_CSTREAM_NO_RESTRICTION = 32768;
  FF_PROFILE_JPEG2000_DCINEMA_2K             = 3;
  FF_PROFILE_JPEG2000_DCINEMA_4K             = 4;

  FF_PROFILE_VP9_0                           = 0;
  FF_PROFILE_VP9_1                           = 1;
  FF_PROFILE_VP9_2                           = 2;
  FF_PROFILE_VP9_3                           = 3;

  FF_PROFILE_HEVC_MAIN                       = 1;
  FF_PROFILE_HEVC_MAIN_10                    = 2;
  FF_PROFILE_HEVC_MAIN_STILL_PICTURE         = 3;
  FF_PROFILE_HEVC_REXT                       = 4;
  FF_PROFILE_HEVC_SCC                        = 9;

  FF_PROFILE_VVC_MAIN_10                     = 1;
  FF_PROFILE_VVC_MAIN_10_444                 = 33;

  FF_PROFILE_AV1_MAIN                        = 0;
  FF_PROFILE_AV1_HIGH                        = 1;
  FF_PROFILE_AV1_PROFESSIONAL                = 2;

  FF_PROFILE_MJPEG_HUFFMAN_BASELINE_DCT            = $c0;
  FF_PROFILE_MJPEG_HUFFMAN_EXTENDED_SEQUENTIAL_DCT = $c1;
  FF_PROFILE_MJPEG_HUFFMAN_PROGRESSIVE_DCT         = $c2;
  FF_PROFILE_MJPEG_HUFFMAN_LOSSLESS                = $c3;
  FF_PROFILE_MJPEG_JPEG_LS                         = $f7;

  FF_PROFILE_SBC_MSBC                        = 1;

  FF_PROFILE_PRORES_PROXY     = 0;
  FF_PROFILE_PRORES_LT        = 1;
  FF_PROFILE_PRORES_STANDARD  = 2;
  FF_PROFILE_PRORES_HQ        = 3;
  FF_PROFILE_PRORES_4444      = 4;
  FF_PROFILE_PRORES_XQ        = 5;

  FF_PROFILE_ARIB_PROFILE_A = 0;
  FF_PROFILE_ARIB_PROFILE_C = 1;

  FF_PROFILE_KLVA_SYNC  = 0;
  FF_PROFILE_KLVA_ASYNC = 1;

  FF_PROFILE_EVC_BASELINE            = 0;
  FF_PROFILE_EVC_MAIN                = 1;
{$ENDIF}

{$IFDEF FF_API_FF_PROFILE_LEVEL}
  // AVCodecContext.level
  (** @deprecated The following define is deprecated; use AV_LEVEL_UNKOWN
   * in defs.h instead. *)
  FF_LEVEL_UNKNOWN = -99;
{$ENDIF}

  // AVCodecContext.thread_type
  FF_THREAD_FRAME   = 1; ///< Decode more than one frame at once
  FF_THREAD_SLICE   = 2; ///< Decode more than one part of a single frame at once

  // AVCodecContext.sub_charenc_mode
  FF_SUB_CHARENC_MODE_DO_NOTHING  = -1; ///< do nothing (demuxer outputs a stream supposed to be already in UTF-8, or the codec is bitmap for instance)
  FF_SUB_CHARENC_MODE_AUTOMATIC   = 0;  ///< libavcodec will select the mode itself
  FF_SUB_CHARENC_MODE_PRE_DECODER = 1;  ///< the AVPacket data needs to be recoded to UTF-8 before being fed to the decoder, requires iconv
  FF_SUB_CHARENC_MODE_IGNORE      = 2;  ///< neither convert the subtitles, nor check them for valid UTF-8

  // AVFrame.decode_error_flags
  FF_DECODE_ERROR_INVALID_BITSTREAM = 1;
  FF_DECODE_ERROR_MISSING_REFERENCE = 2;

(**
 * HWAccel is experimental and is thus avoided in favor of non experimental
 * codecs
 *)
  AV_HWACCEL_CODEC_CAP_EXPERIMENTAL = $0200;

(**
 * Hardware acceleration should be used for decoding even if the codec level
 * used is unknown or higher than the maximum supported level reported by the
 * hardware driver.
 *
 * It's generally a good idea to pass this flag unless you have a specific
 * reason not to, as hardware tends to under-report supported levels.
 *)
  AV_HWACCEL_FLAG_IGNORE_LEVEL = (1 shl 0);

(**
 * Hardware acceleration can output YUV pixel formats with a different chroma
 * sampling than 4:2:0 and/or other than 8 bits per component.
 *)
  AV_HWACCEL_FLAG_ALLOW_HIGH_DEPTH = (1 shl 1);

(**
 * Hardware acceleration should still be attempted for decoding when the
 * codec profile does not match the reported capabilities of the hardware.
 *
 * For example, this can be used to try to decode baseline profile H.264
 * streams in hardware - it will often succeed, because many streams marked
 * as baseline profile actually conform to constrained baseline profile.
 *
 * @warning If the stream is actually not supported then the behaviour is
 *          undefined, and may include returning entirely incorrect output
 *          while indicating success.
 *)
  AV_HWACCEL_FLAG_ALLOW_PROFILE_MISMATCH = (1 shl 2);

(**
 * Some hardware decoders (namely nvdec) can either output direct decoder
 * surfaces, or make an on-device copy and return said copy.
 * There is a hard limit on how many decoder surfaces there can be, and it
 * cannot be accurately guessed ahead of time.
 * For some processing chains, this can be okay, but others will run into the
 * limit and in turn produce very confusing errors that require fine tuning of
 * more or less obscure options by the user, or in extreme cases cannot be
 * resolved at all without inserting an avfilter that forces a copy.
 *
 * Thus, the hwaccel will by default make a copy for safety and resilience.
 * If a users really wants to minimize the amount of copies, they can set this
 * flag and ensure their processing chain does not exhaust the surface pool.
 *)
  AV_HWACCEL_FLAG_UNSAFE_OUTPUT = (1 shl 3);

  AV_SUBTITLE_FLAG_FORCED = $00000001;

type
(**
 * main external API structure.
 * New fields can be added to the end with minor version bumps.
 * Removal, reordering and changes to existing fields require a major
 * version bump.
 * You can use AVOptions (av_opt* / av_set/get*()) to access these fields from user
 * applications.
 * The name string for AVOptions options matches the associated command line
 * parameter name and can be found in libavcodec/options_table.h
 * The AVOption/command line parameter names differ in some cases from the C
 * structure field names for historic reasons or brevity.
 * sizeof(AVCodecContext) must not be used outside libav*.
 *)
  PAVHWAccel = ^TAVHWAccel;
  PPAVCodecContext = ^PAVCodecContext;
  PAVCodecContext = ^TAVCodecContext;
  TexecuteCall = function (c2: PAVCodecContext; arg: Pointer): Integer; cdecl;
  Texecute2Call = function (c2: PAVCodecContext; arg: Pointer; jobnr, threadnr: Integer): Integer; cdecl;
  TAVCodecContext = record
    (**
     * information on struct for av_log
     * - set by avcodec_alloc_context3
     *)
    av_class: PAVClass;
    log_level_offset: Integer;

    codec_type: TAVMediaType; (* see AVMEDIA_TYPE_xxx *)
    codec: PAVCodec;
    codec_id: TAVCodecID; (* see AV_CODEC_ID_xxx *)

    (**
     * fourcc (LSB first, so "ABCD" -> ('D'<<24) + ('C'<<16) + ('B'<<8) + 'A').
     * This is used to work around some encoder bugs.
     * A demuxer should set this to what is stored in the field used to identify the codec.
     * If there are multiple such fields in a container then the demuxer should choose the one
     * which maximizes the information about the used codec.
     * If the codec tag field in a container is larger than 32 bits then the demuxer should
     * remap the longer ID to 32 bits with a table or other structure. Alternatively a new
     * extra_codec_tag + size could be added but for this a clear advantage must be demonstrated
     * first.
     * - encoding: Set by user, if not then the default based on codec_id will be used.
     * - decoding: Set by user, will be converted to uppercase by libavcodec during init.
     *)
    //unsigned int codec_tag;
    //codec_tag: Cardinal;
    //codec_tag: array[0..3] of AnsiChar;
    codec_tag: packed record
      case Integer of
        0: (tag: Cardinal);
        1: (fourcc: array[0..3] of AnsiChar);
        2: (fourbb: array[0..3] of Byte);
      end;

    priv_data: Pointer;

    (**
     * Private context used for internal data.
     *
     * Unlike priv_data, this is not codec-specific. It is used in general
     * libavcodec functions.
     *)
    internal: Pointer; // PAVCodecInternal

    (**
     * Private data of the user, can be used to carry app specific stuff.
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    opaque: Pointer;

    (**
     * the average bitrate
     * - encoding: Set by user; unused for constant quantizer encoding.
     * - decoding: Set by user, may be overwritten by libavcodec
     *             if this info is available in the stream
     *)
    bit_rate: Int64;

    (**
     * AV_CODEC_FLAG_*.
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    flags: Integer;

    (**
     * AV_CODEC_FLAG2_*
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    flags2: Integer;

    (**
     * some codecs need / can use extradata like Huffman tables.
     * MJPEG: Huffman tables
     * rv10: additional flags
     * MPEG-4: global headers (they can be in the bitstream or here)
     * The allocated memory should be AV_INPUT_BUFFER_PADDING_SIZE bytes larger
     * than extradata_size to avoid problems if it is read with the bitstream reader.
     * The bytewise contents of extradata must not depend on the architecture or CPU endianness.
     * Must be allocated with the av_malloc() family of functions.
     * - encoding: Set/allocated/freed by libavcodec.
     * - decoding: Set/allocated/freed by user.
     *)
    extradata: PByte;
    extradata_size: Integer;

    (**
     * This is the fundamental unit of time (in seconds) in terms
     * of which frame timestamps are represented. For fixed-fps content,
     * timebase should be 1/framerate and timestamp increments should be
     * identically 1.
     * This often, but not always is the inverse of the frame rate or field rate
     * for video. 1/time_base is not the average frame rate if the frame rate is not
     * constant.
     *
     * Like containers, elementary streams also can store timestamps, 1/time_base
     * is the unit in which these timestamps are specified.
     * As example of such codec time base see ISO/IEC 14496-2:2001(E)
     * vop_time_increment_resolution and fixed_vop_rate
     * (fixed_vop_rate == 0 implies that it is different from the framerate)
     *
     * - encoding: MUST be set by user.
     * - decoding: unused.
     *)
    time_base: TAVRational;

    (**
     * Timebase in which pkt_dts/pts and AVPacket.dts/pts are expressed.
     * - encoding: unused.
     * - decoding: set by user.
     *)
    pkt_timebase: TAVRational;

    (**
     * - decoding: For codecs that store a framerate value in the compressed
     *             bitstream, the decoder may export it here. { 0, 1} when
     *             unknown.
     * - encoding: May be used to signal the framerate of CFR content to an
     *             encoder.
     *)
    framerate: TAVRational;

{$IFDEF FF_API_TICKS_PER_FRAME}
    (**
     * For some codecs, the time base is closer to the field rate than the frame rate.
     * Most notably, H.264 and MPEG-2 specify time_base as half of frame duration
     * if no telecine is used ...
     *
     * Set to time_base ticks per frame. Default 1, e.g., H.264/MPEG-2 set it to 2.
     *
     * @deprecated
     * - decoding: Use AVCodecDescriptor.props & AV_CODEC_PROP_FIELDS
     * - encoding: Set AVCodecContext.framerate instead
     *
     *)
    ticks_per_frame: Integer;
{$ENDIF}

    (**
     * Codec delay.
     *
     * Encoding: Number of frames delay there will be from the encoder input to
     *           the decoder output. (we assume the decoder matches the spec)
     * Decoding: Number of frames delay in addition to what a standard decoder
     *           as specified in the spec would produce.
     *
     * Video:
     *   Number of frames the decoded output will be delayed relative to the
     *   encoded input.
     *
     * Audio:
     *   For encoding, this field is unused (see initial_padding).
     *
     *   For decoding, this is the number of samples the decoder needs to
     *   output before the decoder's output is valid. When seeking, you should
     *   start decoding this many samples prior to your desired seek point.
     *
     * - encoding: Set by libavcodec.
     * - decoding: Set by libavcodec.
     *)
    delay: Integer;


    (* video only *)
    (**
     * picture width / height.
     *
     * @note Those fields may not match the values of the last
     * AVFrame output by avcodec_receive_frame() due frame
     * reordering.
     *
     * - encoding: MUST be set by user.
     * - decoding: May be set by the user before opening the decoder if known e.g.
     *             from the container. Some decoders will require the dimensions
     *             to be set by the caller. During decoding, the decoder may
     *             overwrite those values as required while parsing the data.
     *)
    width, height: Integer;

    (**
     * Bitstream width / height, may be different from width/height e.g. when
     * the decoded frame is cropped before being output or lowres is enabled.
     *
     * @note Those field may not match the value of the last
     * AVFrame output by avcodec_receive_frame() due frame
     * reordering.
     *
     * - encoding: unused
     * - decoding: May be set by the user before opening the decoder if known
     *             e.g. from the container. During decoding, the decoder may
     *             overwrite those values as required while parsing the data.
     *)
    coded_width, coded_height: Integer;

    (**
     * sample aspect ratio (0 if unknown)
     * That is the width of a pixel divided by the height of the pixel.
     * Numerator and denominator must be relatively prime and smaller than 256 for some video standards.
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
    sample_aspect_ratio: TAVRational;

    (**
     * Pixel format, see AV_PIX_FMT_xxx.
     * May be set by the demuxer if known from headers.
     * May be overridden by the decoder if it knows better.
     *
     * @note This field may not match the value of the last
     * AVFrame output by avcodec_receive_frame() due frame
     * reordering.
     *
     * - encoding: Set by user.
     * - decoding: Set by user if known, overridden by libavcodec while
     *             parsing the data.
     *)
    pix_fmt: TAVPixelFormat;

    (**
     * Nominal unaccelerated pixel format, see AV_PIX_FMT_xxx.
     * - encoding: unused.
     * - decoding: Set by libavcodec before calling get_format()
     *)
    sw_pix_fmt: TAVPixelFormat;

    (**
     * Chromaticity coordinates of the source primaries.
     * - encoding: Set by user
     * - decoding: Set by libavcodec
     *)
    color_primaries: TAVColorPrimaries;

    (**
     * Color Transfer Characteristic.
     * - encoding: Set by user
     * - decoding: Set by libavcodec
     *)
    color_trc: TAVColorTransferCharacteristic;

    (**
     * YUV colorspace type.
     * - encoding: Set by user
     * - decoding: Set by libavcodec
     *)
    colorspace: TAVColorSpace;

    (**
     * MPEG vs JPEG YUV range.
     * - encoding: Set by user to override the default output color range value,
     *   If not specified, libavcodec sets the color range depending on the
     *   output format.
     * - decoding: Set by libavcodec, can be set by the user to propagate the
     *   color range to components reading from the decoder context.
     *)
    color_range: TAVColorRange;

    (**
     * This defines the location of chroma samples.
     * - encoding: Set by user
     * - decoding: Set by libavcodec
     *)
    chroma_sample_location: TAVChromaLocation;

    (** Field order
     * - encoding: set by libavcodec
     * - decoding: Set by user.
     *)
    field_order: TAVFieldOrder;

    (**
     * number of reference frames
     * - encoding: Set by user.
     * - decoding: Set by lavc.
     *)
    refs: Integer;

    (**
     * Size of the frame reordering buffer in the decoder.
     * For MPEG-2 it is 1 IPB or 0 low delay IP.
     * - encoding: Set by libavcodec.
     * - decoding: Set by libavcodec.
     *)
    has_b_frames: Integer;

    (**
     * slice flags
     * - encoding: unused
     * - decoding: Set by user.
     *)
    slice_flags: Integer;
//#define SLICE_FLAG_CODED_ORDER    0x0001 ///< draw_horiz_band() is called in coded order instead of display
//#define SLICE_FLAG_ALLOW_FIELD    0x0002 ///< allow draw_horiz_band() with field slices (MPEG-2 field pics)
//#define SLICE_FLAG_ALLOW_PLANE    0x0004 ///< allow draw_horiz_band() with 1 component at a time (SVQ1)

    (**
     * If non NULL, 'draw_horiz_band' is called by the libavcodec
     * decoder to draw a horizontal band. It improves cache usage. Not
     * all codecs can do that. You must check the codec capabilities
     * beforehand.
     * When multithreading is used, it may be called from multiple threads
     * at the same time; threads might draw different parts of the same AVFrame,
     * or multiple AVFrames, and there is no guarantee that slices will be drawn
     * in order.
     * The function is also used by hardware acceleration APIs.
     * It is called at least once during frame decoding to pass
     * the data needed for hardware render.
     * In that mode instead of pixel data, AVFrame points to
     * a structure specific to the acceleration API. The application
     * reads the structure and can change some fields to indicate progress
     * or mark state.
     * - encoding: unused
     * - decoding: Set by user.
     * @param height the height of the slice
     * @param y the y position of the slice
     * @param type 1->top field, 2->bottom field, 3->frame
     * @param offset offset into the AVFrame.data from which the slice should be read
     *)
    draw_horiz_band: procedure (s: PAVCodecContext;
                            const src: PAVFrame; offset: PInteger;{int offset[AV_NUM_DATA_POINTERS]}
                            y, type_, height: Integer); cdecl;

    (**
     * Callback to negotiate the pixel format. Decoding only, may be set by the
     * caller before avcodec_open2().
     *
     * Called by some decoders to select the pixel format that will be used for
     * the output frames. This is mainly used to set up hardware acceleration,
     * then the provided format list contains the corresponding hwaccel pixel
     * formats alongside the "software" one. The software pixel format may also
     * be retrieved from \ref sw_pix_fmt.
     *
     * This callback will be called when the coded frame properties (such as
     * resolution, pixel format, etc.) change and more than one output format is
     * supported for those new properties. If a hardware pixel format is chosen
     * and initialization for it fails, the callback may be called again
     * immediately.
     *
     * This callback may be called from different threads if the decoder is
     * multi-threaded, but not from more than one thread simultaneously.
     *
     * @param fmt list of formats which may be used in the current
     *            configuration, terminated by AV_PIX_FMT_NONE.
     * @warning Behavior is undefined if the callback returns a value other
     *          than one of the formats in fmt or AV_PIX_FMT_NONE.
     * @return the chosen format or AV_PIX_FMT_NONE
     *)
    get_format: function(s: PAVCodecContext; const fmt: PAVPixelFormat): TAVPixelFormat; cdecl;

    (**
     * maximum number of B-frames between non-B-frames
     * Note: The output will be delayed by max_b_frames+1 relative to the input.
     * - encoding: Set by user.
     * - decoding: unused
     *)
    max_b_frames: Integer;

    (**
     * qscale factor between IP and B-frames
     * If > 0 then the last P-frame quantizer will be used (q= lastp_q*factor+offset).
     * If < 0 then normal ratecontrol will be done (q= -normal_q*factor+offset).
     * - encoding: Set by user.
     * - decoding: unused
     *)
    b_quant_factor: Single;

    (**
     * qscale offset between IP and B-frames
     * - encoding: Set by user.
     * - decoding: unused
     *)
    b_quant_offset: Single;

    (**
     * qscale factor between P- and I-frames
     * If > 0 then the last P-frame quantizer will be used (q = lastp_q * factor + offset).
     * If < 0 then normal ratecontrol will be done (q= -normal_q*factor+offset).
     * - encoding: Set by user.
     * - decoding: unused
     *)
    i_quant_factor: Single;

    (**
     * qscale offset between P and I-frames
     * - encoding: Set by user.
     * - decoding: unused
     *)
    i_quant_offset: Single;

    (**
     * luminance masking (0-> disabled)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    lumi_masking: Single;

    (**
     * temporary complexity masking (0-> disabled)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    temporal_cplx_masking: Single;

    (**
     * spatial complexity masking (0-> disabled)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    spatial_cplx_masking: Single;

    (**
     * p block masking (0-> disabled)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    p_masking: Single;

    (**
     * darkness masking (0-> disabled)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    dark_masking: Single;

    (**
     * noise vs. sse weight for the nsse comparison function
     * - encoding: Set by user.
     * - decoding: unused
     *)
    nsse_weight: Integer;

    (**
     * motion estimation comparison function
     * - encoding: Set by user.
     * - decoding: unused
     *)
    me_cmp: Integer;
    (**
     * subpixel motion estimation comparison function
     * - encoding: Set by user.
     * - decoding: unused
     *)
    me_sub_cmp: Integer;
    (**
     * macroblock comparison function (not supported yet)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    mb_cmp: Integer;
    (**
     * interlaced DCT comparison function
     * - encoding: Set by user.
     * - decoding: unused
     *)
    ildct_cmp: Integer;
{
#define FF_CMP_SAD          0
#define FF_CMP_SSE          1
#define FF_CMP_SATD         2
#define FF_CMP_DCT          3
#define FF_CMP_PSNR         4
#define FF_CMP_BIT          5
#define FF_CMP_RD           6
#define FF_CMP_ZERO         7
#define FF_CMP_VSAD         8
#define FF_CMP_VSSE         9
#define FF_CMP_NSSE         10
#define FF_CMP_W53          11
#define FF_CMP_W97          12
#define FF_CMP_DCTMAX       13
#define FF_CMP_DCT264       14
#define FF_CMP_MEDIAN_SAD   15
#define FF_CMP_CHROMA       256
}

    (**
     * ME diamond size & shape
     * - encoding: Set by user.
     * - decoding: unused
     *)
    dia_size: Integer;

    (**
     * amount of previous MV predictors (2a+1 x 2a+1 square)
     * - encoding: Set by user.
     * - decoding: unused
     *)
    last_predictor_count: Integer;

    (**
     * motion estimation prepass comparison function
     * - encoding: Set by user.
     * - decoding: unused
     *)
    me_pre_cmp: Integer;

    (**
     * ME prepass diamond size & shape
     * - encoding: Set by user.
     * - decoding: unused
     *)
    pre_dia_size: Integer;

    (**
     * subpel ME quality
     * - encoding: Set by user.
     * - decoding: unused
     *)
    me_subpel_quality: Integer;

    (**
     * maximum motion estimation search range in subpel units
     * If 0 then no limit.
     *
     * - encoding: Set by user.
     * - decoding: unused
     *)
    me_range: Integer;

    (**
     * macroblock decision mode
     * - encoding: Set by user.
     * - decoding: unused
     *)
    mb_decision: Integer;
{
#define FF_MB_DECISION_SIMPLE 0        ///< uses mb_cmp
#define FF_MB_DECISION_BITS   1        ///< chooses the one which needs the fewest bits
#define FF_MB_DECISION_RD     2        ///< rate distortion
}

    (**
     * custom intra quantization matrix
     * Must be allocated with the av_malloc() family of functions, and will be freed in
     * avcodec_free_context().
     * - encoding: Set/allocated by user, freed by libavcodec. Can be NULL.
     * - decoding: Set/allocated/freed by libavcodec.
     *)
    intra_matrix: PWord;

    (**
     * custom inter quantization matrix
     * Must be allocated with the av_malloc() family of functions, and will be freed in
     * avcodec_free_context().
     * - encoding: Set/allocated by user, freed by libavcodec. Can be NULL.
     * - decoding: Set/allocated/freed by libavcodec.
     *)
    inter_matrix: PWord;

    (**
     * custom intra quantization matrix
     * - encoding: Set by user, can be NULL.
     * - decoding: unused.
     *)
    chroma_intra_matrix: PWord;

    (**
     * precision of the intra DC coefficient - 8
     * - encoding: Set by user.
     * - decoding: Set by libavcodec
     *)
    intra_dc_precision: Integer;

    (**
     * minimum MB Lagrange multiplier
     * - encoding: Set by user.
     * - decoding: unused
     *)
    mb_lmin: Integer;

    (**
     * maximum MB Lagrange multiplier
     * - encoding: Set by user.
     * - decoding: unused
     *)
    mb_lmax: Integer;

    (**
     * - encoding: Set by user.
     * - decoding: unused
     *)
    bidir_refine: Integer;

    (**
     * minimum GOP size
     * - encoding: Set by user.
     * - decoding: unused
     *)
    keyint_min: Integer;

    (**
     * the number of pictures in a group of pictures, or 0 for intra_only
     * - encoding: Set by user.
     * - decoding: unused
     *)
    gop_size: Integer;

    (**
     * Note: Value depends upon the compare function used for fullpel ME.
     * - encoding: Set by user.
     * - decoding: unused
     *)
    mv0_threshold: Integer;

    (**
     * Number of slices.
     * Indicates number of picture subdivisions. Used for parallelized
     * decoding.
     * - encoding: Set by user
     * - decoding: unused
     *)
    slices: Integer;

    (* audio only *)
    sample_rate: Integer; ///< samples per second

    (**
     * audio sample format
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
    sample_fmt: TAVSampleFormat;  ///< sample format

    (**
     * Audio channel layout.
     * - encoding: must be set by the caller, to one of AVCodec.ch_layouts.
     * - decoding: may be set by the caller if known e.g. from the container.
     *             The decoder can then override during decoding as needed.
     *)
    ch_layout: TAVChannelLayout;

    (* The following data should not be initialized. *)
    (**
     * Number of samples per channel in an audio frame.
     *
     * - encoding: set by libavcodec in avcodec_open2(). Each submitted frame
     *   except the last must contain exactly frame_size samples per channel.
     *   May be 0 when the codec has AV_CODEC_CAP_VARIABLE_FRAME_SIZE set, then the
     *   frame size is not restricted.
     * - decoding: may be set by some decoders to indicate constant frame size
     *)
    frame_size: Integer;

    (**
     * number of bytes per packet if constant and known or 0
     * Used by some WAV based audio codecs.
     *)
    block_align: Integer;

    (**
     * Audio cutoff bandwidth (0 means "automatic")
     * - encoding: Set by user.
     * - decoding: unused
     *)
    cutoff: Integer;

    (**
     * Type of service that the audio stream conveys.
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
     audio_service_type: TAVAudioServiceType;

    (**
     * desired sample format
     * - encoding: Not used.
     * - decoding: Set by user.
     * Decoder will decode to this format if it can.
     *)
    request_sample_fmt: TAVSampleFormat;

    (**
     * Audio only. The number of "priming" samples (padding) inserted by the
     * encoder at the beginning of the audio. I.e. this number of leading
     * decoded samples must be discarded by the caller to get the original audio
     * without leading padding.
     *
     * - decoding: unused
     * - encoding: Set by libavcodec. The timestamps on the output packets are
     *             adjusted by the encoder so that they always refer to the
     *             first sample of the data actually contained in the packet,
     *             including any added padding.  E.g. if the timebase is
     *             1/samplerate and the timestamp of the first input sample is
     *             0, the timestamp of the first output packet will be
     *             -initial_padding.
     *)
    initial_padding: Integer;

    (**
     * Audio only. The amount of padding (in samples) appended by the encoder to
     * the end of the audio. I.e. this number of decoded samples must be
     * discarded by the caller from the end of the stream to get the original
     * audio without any trailing padding.
     *
     * - decoding: unused
     * - encoding: unused
     *)
    trailing_padding: Integer;

    (**
     * Number of samples to skip after a discontinuity
     * - decoding: unused
     * - encoding: set by libavcodec
     *)
    seek_preroll: Integer;

    (**
     * This callback is called at the beginning of each frame to get data
     * buffer(s) for it. There may be one contiguous buffer for all the data or
     * there may be a buffer per each data plane or anything in between. What
     * this means is, you may set however many entries in buf[] you feel necessary.
     * Each buffer must be reference-counted using the AVBuffer API (see description
     * of buf[] below).
     *
     * The following fields will be set in the frame before this callback is
     * called:
     * - format
     * - width, height (video only)
     * - sample_rate, channel_layout, nb_samples (audio only)
     * Their values may differ from the corresponding values in
     * AVCodecContext. This callback must use the frame values, not the codec
     * context values, to calculate the required buffer size.
     *
     * This callback must fill the following fields in the frame:
     * - data[]
     * - linesize[]
     * - extended_data:
     *   * if the data is planar audio with more than 8 channels, then this
     *     callback must allocate and fill extended_data to contain all pointers
     *     to all data planes. data[] must hold as many pointers as it can.
     *     extended_data must be allocated with av_malloc() and will be freed in
     *     av_frame_unref().
     *   * otherwise extended_data must point to data
     * - buf[] must contain one or more pointers to AVBufferRef structures. Each of
     *   the frame's data and extended_data pointers must be contained in these. That
     *   is, one AVBufferRef for each allocated chunk of memory, not necessarily one
     *   AVBufferRef per data[] entry. See: av_buffer_create(), av_buffer_alloc(),
     *   and av_buffer_ref().
     * - extended_buf and nb_extended_buf must be allocated with av_malloc() by
     *   this callback and filled with the extra buffers if there are more
     *   buffers than buf[] can hold. extended_buf will be freed in
     *   av_frame_unref().
     *   Decoders will generally initialize the whole buffer before it is output
     *   but it can in rare error conditions happen that uninitialized data is passed
     *   through. \important The buffers returned by get_buffer* should thus not contain sensitive
     *   data.
     *
     * If AV_CODEC_CAP_DR1 is not set then get_buffer2() must call
     * avcodec_default_get_buffer2() instead of providing buffers allocated by
     * some other means.
     *
     * Each data plane must be aligned to the maximum required by the target
     * CPU.
     *
     * @see avcodec_default_get_buffer2()
     *
     * Video:
     *
     * If AV_GET_BUFFER_FLAG_REF is set in flags then the frame may be reused
     * (read and/or written to if it is writable) later by libavcodec.
     *
     * avcodec_align_dimensions2() should be used to find the required width and
     * height, as they normally need to be rounded up to the next multiple of 16.
     *
     * Some decoders do not support linesizes changing between frames.
     *
     * If frame multithreading is used, this callback may be called from a
     * different thread, but not from more than one at once. Does not need to be
     * reentrant.
     *
     * @see avcodec_align_dimensions2()
     *
     * Audio:
     *
     * Decoders request a buffer of a particular size by setting
     * AVFrame.nb_samples prior to calling get_buffer2(). The decoder may,
     * however, utilize only part of the buffer by setting AVFrame.nb_samples
     * to a smaller value in the output frame.
     *
     * As a convenience, av_samples_get_buffer_size() and
     * av_samples_fill_arrays() in libavutil may be used by custom get_buffer2()
     * functions to find the required data size and to fill data pointers and
     * linesize. In AVFrame.linesize, only linesize[0] may be set for audio
     * since all planes must be the same size.
     *
     * @see av_samples_get_buffer_size(), av_samples_fill_arrays()
     *
     * - encoding: unused
     * - decoding: Set by libavcodec, user can override.
     *)
    get_buffer2: function(s: PAVCodecContext; frame: PAVFrame; flags: Integer): Integer; cdecl;

    (* - encoding parameters *)
    (**
     * number of bits the bitstream is allowed to diverge from the reference.
     *           the reference can be CBR (for CBR pass1) or VBR (for pass2)
     * - encoding: Set by user; unused for constant quantizer encoding.
     * - decoding: unused
     *)
    bit_rate_tolerance: Integer;

    (**
     * Global quality for codecs which cannot change it per frame.
     * This should be proportional to MPEG-1/2/4 qscale.
     * - encoding: Set by user.
     * - decoding: unused
     *)
    global_quality: Integer;

    (**
     * - encoding: Set by user.
     * - decoding: unused
     *)
    compression_level: Integer;
//#define FF_COMPRESSION_DEFAULT -1

    qcompress: Single;  ///< amount of qscale change between easy & hard scenes (0.0-1.0)
    qblur: Single;      ///< amount of qscale smoothing over time (0.0-1.0)

    (**
     * minimum quantizer
     * - encoding: Set by user.
     * - decoding: unused
     *)
    qmin: Integer;

    (**
     * maximum quantizer
     * - encoding: Set by user.
     * - decoding: unused
     *)
    qmax: Integer;

    (**
     * maximum quantizer difference between frames
     * - encoding: Set by user.
     * - decoding: unused
     *)
    max_qdiff: Integer;

    (**
     * decoder bitstream buffer size
     * - encoding: Set by user.
     * - decoding: May be set by libavcodec.
     *)
    rc_buffer_size: Integer;

    (**
     * ratecontrol override, see RcOverride
     * - encoding: Allocated/set/freed by user.
     * - decoding: unused
     *)
    rc_override_count: Integer;
    rc_override: PRcOverride;

    (**
     * maximum bitrate
     * - encoding: Set by user.
     * - decoding: Set by user, may be overwritten by libavcodec.
     *)
    rc_max_rate: Int64;

    (**
     * minimum bitrate
     * - encoding: Set by user.
     * - decoding: unused
     *)
    rc_min_rate: Int64;

    (**
     * Ratecontrol attempt to use, at maximum, <value> of what can be used without an underflow.
     * - encoding: Set by user.
     * - decoding: unused.
     *)
    rc_max_available_vbv_use: Single;

    (**
     * Ratecontrol attempt to use, at least, <value> times the amount needed to prevent a vbv overflow.
     * - encoding: Set by user.
     * - decoding: unused.
     *)
    rc_min_vbv_overflow_use: Single;

    (**
     * Number of bits which should be loaded into the rc buffer before decoding starts.
     * - encoding: Set by user.
     * - decoding: unused
     *)
    rc_initial_buffer_occupancy: Integer;

    (**
     * trellis RD quantization
     * - encoding: Set by user.
     * - decoding: unused
     *)
    trellis: Integer;

    (**
     * pass1 encoding statistics output buffer
     * - encoding: Set by libavcodec.
     * - decoding: unused
     *)
    stats_out: PAnsiChar;

    (**
     * pass2 encoding statistics input buffer
     * Concatenated stuff from stats_out of pass1 should be placed here.
     * - encoding: Allocated/set/freed by user.
     * - decoding: unused
     *)
    stats_in: PAnsiChar;

    (**
     * Work around bugs in encoders which sometimes cannot be detected automatically.
     * - encoding: Set by user
     * - decoding: Set by user
     *)
    workaround_bugs: Integer;
{
#define FF_BUG_AUTODETECT       1  ///< autodetection
#define FF_BUG_XVID_ILACE       4
#define FF_BUG_UMP4             8
#define FF_BUG_NO_PADDING       16
#define FF_BUG_AMV              32
#define FF_BUG_QPEL_CHROMA      64
#define FF_BUG_STD_QPEL         128
#define FF_BUG_QPEL_CHROMA2     256
#define FF_BUG_DIRECT_BLOCKSIZE 512
#define FF_BUG_EDGE             1024
#define FF_BUG_HPEL_CHROMA      2048
#define FF_BUG_DC_CLIP          4096
#define FF_BUG_MS               8192 ///< Work around various bugs in Microsoft's broken decoders.
#define FF_BUG_TRUNCATED       16384
#define FF_BUG_IEDGE           32768
}

    (**
     * strictly follow the standard (MPEG-4, ...).
     * - encoding: Set by user.
     * - decoding: Set by user.
     * Setting this to STRICT or higher means the encoder and decoder will
     * generally do stupid things, whereas setting it to unofficial or lower
     * will mean the encoder might produce output that is not supported by all
     * spec-compliant decoders. Decoders don't differentiate between normal,
     * unofficial and experimental (that is, they always try to decode things
     * when they can) unless they are explicitly asked to behave stupidly
     * (=strictly conform to the specs)
     * This may only be set to one of the FF_COMPLIANCE_* values in defs.h.
     *)
    strict_std_compliance: Integer;

    (**
     * error concealment flags
     * - encoding: unused
     * - decoding: Set by user.
     *)
    error_concealment: Integer;
//#define FF_EC_GUESS_MVS   1
//#define FF_EC_DEBLOCK     2
//#define FF_EC_FAVOR_INTER 256

    (**
     * debug
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    debug: Integer;
{
#define FF_DEBUG_PICT_INFO   1
#define FF_DEBUG_RC          2
#define FF_DEBUG_BITSTREAM   4
#define FF_DEBUG_MB_TYPE     8
#define FF_DEBUG_QP          16
#define FF_DEBUG_DCT_COEFF   0x00000040
#define FF_DEBUG_SKIP        0x00000080
#define FF_DEBUG_STARTCODE   0x00000100
#define FF_DEBUG_ER          0x00000400
#define FF_DEBUG_MMCO        0x00000800
#define FF_DEBUG_BUGS        0x00001000
#define FF_DEBUG_BUFFERS     0x00008000
#define FF_DEBUG_THREADS     0x00010000
#define FF_DEBUG_GREEN_MD    0x00800000
#define FF_DEBUG_NOMC        0x01000000
}

    (**
     * Error recognition; may misdetect some more or less valid parts as errors.
     * This is a bitfield of the AV_EF_* values defined in defs.h.
     *
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    err_recognition: Integer;

    (**
     * Hardware accelerator in use
     * - encoding: unused.
     * - decoding: Set by libavcodec
     *)
    hwaccel: PAVHWAccel;

    (**
     * Legacy hardware accelerator context.
     *
     * For some hardware acceleration methods, the caller may use this field to
     * signal hwaccel-specific data to the codec. The struct pointed to by this
     * pointer is hwaccel-dependent and defined in the respective header. Please
     * refer to the FFmpeg HW accelerator documentation to know how to fill
     * this.
     *
     * In most cases this field is optional - the necessary information may also
     * be provided to libavcodec through @ref hw_frames_ctx or @ref
     * hw_device_ctx (see avcodec_get_hw_config()). However, in some cases it
     * may be the only method of signalling some (optional) information.
     *
     * The struct and its contents are owned by the caller.
     *
     * - encoding: May be set by the caller before avcodec_open2(). Must remain
     *             valid until avcodec_free_context().
     * - decoding: May be set by the caller in the get_format() callback.
     *             Must remain valid until the next get_format() call,
     *             or avcodec_free_context() (whichever comes first).
     *)
    hwaccel_context: Pointer;

    (**
     * A reference to the AVHWFramesContext describing the input (for encoding)
     * or output (decoding) frames. The reference is set by the caller and
     * afterwards owned (and freed) by libavcodec - it should never be read by
     * the caller after being set.
     *
     * - decoding: This field should be set by the caller from the get_format()
     *             callback. The previous reference (if any) will always be
     *             unreffed by libavcodec before the get_format() call.
     *
     *             If the default get_buffer2() is used with a hwaccel pixel
     *             format, then this AVHWFramesContext will be used for
     *             allocating the frame buffers.
     *
     * - encoding: For hardware encoders configured to use a hwaccel pixel
     *             format, this field should be set by the caller to a reference
     *             to the AVHWFramesContext describing input frames.
     *             AVHWFramesContext.format must be equal to
     *             AVCodecContext.pix_fmt.
     *
     *             This field should be set before avcodec_open2() is called.
     *)
    hw_frames_ctx: PAVBufferRef;

    (**
     * A reference to the AVHWDeviceContext describing the device which will
     * be used by a hardware encoder/decoder.  The reference is set by the
     * caller and afterwards owned (and freed) by libavcodec.
     *
     * This should be used if either the codec device does not require
     * hardware frames or any that are used are to be allocated internally by
     * libavcodec.  If the user wishes to supply any of the frames used as
     * encoder input or decoder output then hw_frames_ctx should be used
     * instead.  When hw_frames_ctx is set in get_format() for a decoder, this
     * field will be ignored while decoding the associated stream segment, but
     * may again be used on a following one after another get_format() call.
     *
     * For both encoders and decoders this field should be set before
     * avcodec_open2() is called and must not be written to thereafter.
     *
     * Note that some decoders may require this field to be set initially in
     * order to support hw_frames_ctx at all - in that case, all frames
     * contexts used must be created on the same device.
     *)
    hw_device_ctx: PAVBufferRef;

    (**
     * Bit set of AV_HWACCEL_FLAG_* flags, which affect hardware accelerated
     * decoding (if active).
     * - encoding: unused
     * - decoding: Set by user (either before avcodec_open2(), or in the
     *             AVCodecContext.get_format callback)
     *)
    hwaccel_flags: Integer;

    (**
     * Video decoding only.  Sets the number of extra hardware frames which
     * the decoder will allocate for use by the caller.  This must be set
     * before avcodec_open2() is called.
     *
     * Some hardware decoders require all frames that they will use for
     * output to be defined in advance before decoding starts.  For such
     * decoders, the hardware frame pool must therefore be of a fixed size.
     * The extra frames set here are on top of any number that the decoder
     * needs internally in order to operate normally (for example, frames
     * used as reference pictures).
     *)
    extra_hw_frames: Integer;

    (**
     * error
     * - encoding: Set by libavcodec if flags & AV_CODEC_FLAG_PSNR.
     * - decoding: unused
     *)
    error: array[0..AV_NUM_DATA_POINTERS-1] of Int64;

    (**
     * DCT algorithm, see FF_DCT_* below
     * - encoding: Set by user.
     * - decoding: unused
     *)
    dct_algo: Integer;
{
#define FF_DCT_AUTO    0
#define FF_DCT_FASTINT 1
#define FF_DCT_INT     2
#define FF_DCT_MMX     3
#define FF_DCT_ALTIVEC 5
#define FF_DCT_FAAN    6
#define FF_DCT_NEON    7
}

    (**
     * IDCT algorithm, see FF_IDCT_* below.
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    idct_algo: Integer;
{
#define FF_IDCT_AUTO          0
#define FF_IDCT_INT           1
#define FF_IDCT_SIMPLE        2
#define FF_IDCT_SIMPLEMMX     3
#define FF_IDCT_ARM           7
#define FF_IDCT_ALTIVEC       8
#define FF_IDCT_SIMPLEARM     10
#define FF_IDCT_XVID          14
#define FF_IDCT_SIMPLEARMV5TE 16
#define FF_IDCT_SIMPLEARMV6   17
#define FF_IDCT_FAAN          20
#define FF_IDCT_SIMPLENEON    22
#define FF_IDCT_SIMPLEAUTO    128
}

    (**
     * bits per sample/pixel from the demuxer (needed for huffyuv).
     * - encoding: Set by libavcodec.
     * - decoding: Set by user.
     *)
    bits_per_coded_sample: Integer;

    (**
     * Bits per sample/pixel of internal libavcodec pixel/sample format.
     * - encoding: set by user.
     * - decoding: set by libavcodec.
     *)
    bits_per_raw_sample: Integer;

    (**
     * thread count
     * is used to decide how many independent tasks should be passed to execute()
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    thread_count: Integer;

    (**
     * Which multithreading methods to use.
     * Use of FF_THREAD_FRAME will increase decoding delay by one frame per thread,
     * so clients which cannot provide future frames should not use it.
     *
     * - encoding: Set by user, otherwise the default is used.
     * - decoding: Set by user, otherwise the default is used.
     *)
    thread_type: Integer;
{
#define FF_THREAD_FRAME   1 ///< Decode more than one frame at once
#define FF_THREAD_SLICE   2 ///< Decode more than one part of a single frame at once
}

    (**
     * Which multithreading methods are in use by the codec.
     * - encoding: Set by libavcodec.
     * - decoding: Set by libavcodec.
     *)
    active_thread_type: Integer;

    (**
     * The codec may call this to execute several independent things.
     * It will return only after finishing all tasks.
     * The user may replace this with some multithreaded implementation,
     * the default implementation will execute the parts serially.
     * @param count the number of things to execute
     * - encoding: Set by libavcodec, user can override.
     * - decoding: Set by libavcodec, user can override.
     *)
    execute: function (c: PAVCodecContext; func: TexecuteCall; arg2: Pointer; ret: PInteger; count, size: Integer): Integer; cdecl;

    (**
     * The codec may call this to execute several independent things.
     * It will return only after finishing all tasks.
     * The user may replace this with some multithreaded implementation,
     * the default implementation will execute the parts serially.
     * @param c context passed also to func
     * @param count the number of things to execute
     * @param arg2 argument passed unchanged to func
     * @param ret return values of executed functions, must have space for "count" values. May be NULL.
     * @param func function that will be called count times, with jobnr from 0 to count-1.
     *             threadnr will be in the range 0 to c->thread_count-1 < MAX_THREADS and so that no
     *             two instances of func executing at the same time will have the same threadnr.
     * @return always 0 currently, but code should handle a future improvement where when any call to func
     *         returns < 0 no further calls to func may be done and < 0 is returned.
     * - encoding: Set by libavcodec, user can override.
     * - decoding: Set by libavcodec, user can override.
     *)
    execute2: function (c: PAVCodecContext; func: Texecute2Call; arg2: Pointer; ret: PInteger; count: Integer): Integer; cdecl;

    (**
     * profile
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     * See the AV_PROFILE_* defines in defs.h.
     *)
     profile: Integer;
{
#if FF_API_FF_PROFILE_LEVEL
    /** @deprecated The following defines are deprecated; use AV_PROFILE_*
     * in defs.h instead. */
#define FF_PROFILE_UNKNOWN -99
#define FF_PROFILE_RESERVED -100

#define FF_PROFILE_AAC_MAIN 0
#define FF_PROFILE_AAC_LOW  1
#define FF_PROFILE_AAC_SSR  2
#define FF_PROFILE_AAC_LTP  3
#define FF_PROFILE_AAC_HE   4
#define FF_PROFILE_AAC_HE_V2 28
#define FF_PROFILE_AAC_LD   22
#define FF_PROFILE_AAC_ELD  38
#define FF_PROFILE_MPEG2_AAC_LOW 128
#define FF_PROFILE_MPEG2_AAC_HE  131

#define FF_PROFILE_DNXHD         0
#define FF_PROFILE_DNXHR_LB      1
#define FF_PROFILE_DNXHR_SQ      2
#define FF_PROFILE_DNXHR_HQ      3
#define FF_PROFILE_DNXHR_HQX     4
#define FF_PROFILE_DNXHR_444     5

#define FF_PROFILE_DTS                20
#define FF_PROFILE_DTS_ES             30
#define FF_PROFILE_DTS_96_24          40
#define FF_PROFILE_DTS_HD_HRA         50
#define FF_PROFILE_DTS_HD_MA          60
#define FF_PROFILE_DTS_EXPRESS        70
#define FF_PROFILE_DTS_HD_MA_X        61
#define FF_PROFILE_DTS_HD_MA_X_IMAX   62


#define FF_PROFILE_EAC3_DDP_ATMOS         30

#define FF_PROFILE_TRUEHD_ATMOS           30

#define FF_PROFILE_MPEG2_422    0
#define FF_PROFILE_MPEG2_HIGH   1
#define FF_PROFILE_MPEG2_SS     2
#define FF_PROFILE_MPEG2_SNR_SCALABLE  3
#define FF_PROFILE_MPEG2_MAIN   4
#define FF_PROFILE_MPEG2_SIMPLE 5

#define FF_PROFILE_H264_CONSTRAINED  (1<<9)  // 8+1; constraint_set1_flag
#define FF_PROFILE_H264_INTRA        (1<<11) // 8+3; constraint_set3_flag

#define FF_PROFILE_H264_BASELINE             66
#define FF_PROFILE_H264_CONSTRAINED_BASELINE (66|FF_PROFILE_H264_CONSTRAINED)
#define FF_PROFILE_H264_MAIN                 77
#define FF_PROFILE_H264_EXTENDED             88
#define FF_PROFILE_H264_HIGH                 100
#define FF_PROFILE_H264_HIGH_10              110
#define FF_PROFILE_H264_HIGH_10_INTRA        (110|FF_PROFILE_H264_INTRA)
#define FF_PROFILE_H264_MULTIVIEW_HIGH       118
#define FF_PROFILE_H264_HIGH_422             122
#define FF_PROFILE_H264_HIGH_422_INTRA       (122|FF_PROFILE_H264_INTRA)
#define FF_PROFILE_H264_STEREO_HIGH          128
#define FF_PROFILE_H264_HIGH_444             144
#define FF_PROFILE_H264_HIGH_444_PREDICTIVE  244
#define FF_PROFILE_H264_HIGH_444_INTRA       (244|FF_PROFILE_H264_INTRA)
#define FF_PROFILE_H264_CAVLC_444            44

#define FF_PROFILE_VC1_SIMPLE   0
#define FF_PROFILE_VC1_MAIN     1
#define FF_PROFILE_VC1_COMPLEX  2
#define FF_PROFILE_VC1_ADVANCED 3

#define FF_PROFILE_MPEG4_SIMPLE                     0
#define FF_PROFILE_MPEG4_SIMPLE_SCALABLE            1
#define FF_PROFILE_MPEG4_CORE                       2
#define FF_PROFILE_MPEG4_MAIN                       3
#define FF_PROFILE_MPEG4_N_BIT                      4
#define FF_PROFILE_MPEG4_SCALABLE_TEXTURE           5
#define FF_PROFILE_MPEG4_SIMPLE_FACE_ANIMATION      6
#define FF_PROFILE_MPEG4_BASIC_ANIMATED_TEXTURE     7
#define FF_PROFILE_MPEG4_HYBRID                     8
#define FF_PROFILE_MPEG4_ADVANCED_REAL_TIME         9
#define FF_PROFILE_MPEG4_CORE_SCALABLE             10
#define FF_PROFILE_MPEG4_ADVANCED_CODING           11
#define FF_PROFILE_MPEG4_ADVANCED_CORE             12
#define FF_PROFILE_MPEG4_ADVANCED_SCALABLE_TEXTURE 13
#define FF_PROFILE_MPEG4_SIMPLE_STUDIO             14
#define FF_PROFILE_MPEG4_ADVANCED_SIMPLE           15

#define FF_PROFILE_JPEG2000_CSTREAM_RESTRICTION_0   1
#define FF_PROFILE_JPEG2000_CSTREAM_RESTRICTION_1   2
#define FF_PROFILE_JPEG2000_CSTREAM_NO_RESTRICTION  32768
#define FF_PROFILE_JPEG2000_DCINEMA_2K              3
#define FF_PROFILE_JPEG2000_DCINEMA_4K              4

#define FF_PROFILE_VP9_0                            0
#define FF_PROFILE_VP9_1                            1
#define FF_PROFILE_VP9_2                            2
#define FF_PROFILE_VP9_3                            3

#define FF_PROFILE_HEVC_MAIN                        1
#define FF_PROFILE_HEVC_MAIN_10                     2
#define FF_PROFILE_HEVC_MAIN_STILL_PICTURE          3
#define FF_PROFILE_HEVC_REXT                        4
#define FF_PROFILE_HEVC_SCC                         9

#define FF_PROFILE_VVC_MAIN_10                      1
#define FF_PROFILE_VVC_MAIN_10_444                 33

#define FF_PROFILE_AV1_MAIN                         0
#define FF_PROFILE_AV1_HIGH                         1
#define FF_PROFILE_AV1_PROFESSIONAL                 2

#define FF_PROFILE_MJPEG_HUFFMAN_BASELINE_DCT            0xc0
#define FF_PROFILE_MJPEG_HUFFMAN_EXTENDED_SEQUENTIAL_DCT 0xc1
#define FF_PROFILE_MJPEG_HUFFMAN_PROGRESSIVE_DCT         0xc2
#define FF_PROFILE_MJPEG_HUFFMAN_LOSSLESS                0xc3
#define FF_PROFILE_MJPEG_JPEG_LS                         0xf7

#define FF_PROFILE_SBC_MSBC                         1

#define FF_PROFILE_PRORES_PROXY     0
#define FF_PROFILE_PRORES_LT        1
#define FF_PROFILE_PRORES_STANDARD  2
#define FF_PROFILE_PRORES_HQ        3
#define FF_PROFILE_PRORES_4444      4
#define FF_PROFILE_PRORES_XQ        5

#define FF_PROFILE_ARIB_PROFILE_A 0
#define FF_PROFILE_ARIB_PROFILE_C 1

#define FF_PROFILE_KLVA_SYNC 0
#define FF_PROFILE_KLVA_ASYNC 1

#define FF_PROFILE_EVC_BASELINE             0
#define FF_PROFILE_EVC_MAIN                 1
#endif
}

    (**
     * Encoding level descriptor.
     * - encoding: Set by user, corresponds to a specific level defined by the
     *   codec, usually corresponding to the profile level, if not specified it
     *   is set to FF_LEVEL_UNKNOWN.
     * - decoding: Set by libavcodec.
     * See AV_LEVEL_* in defs.h.
     *)
     level: Integer;
{
#if FF_API_FF_PROFILE_LEVEL
    /** @deprecated The following define is deprecated; use AV_LEVEL_UNKOWN
     * in defs.h instead. */
#define FF_LEVEL_UNKNOWN -99
#endif
}

    (**
     * Properties of the stream that gets decoded
     * - encoding: unused
     * - decoding: set by libavcodec
     *)
    properties: Cardinal;
//#define FF_CODEC_PROPERTY_LOSSLESS        0x00000001
//#define FF_CODEC_PROPERTY_CLOSED_CAPTIONS 0x00000002
//#define FF_CODEC_PROPERTY_FILM_GRAIN      0x00000004

    (**
     * Skip loop filtering for selected frames.
     * - encoding: unused
     * - decoding: Set by user.
     *)
    skip_loop_filter: TAVDiscard;

    (**
     * Skip IDCT/dequantization for selected frames.
     * - encoding: unused
     * - decoding: Set by user.
     *)
    skip_idct: TAVDiscard;

    (**
     * Skip decoding for selected frames.
     * - encoding: unused
     * - decoding: Set by user.
     *)
    skip_frame: TAVDiscard;

    (**
     * Skip processing alpha if supported by codec.
     * Note that if the format uses pre-multiplied alpha (common with VP6,
     * and recommended due to better video quality/compression)
     * the image will look as if alpha-blended onto a black background.
     * However for formats that do not use pre-multiplied alpha
     * there might be serious artefacts (though e.g. libswscale currently
     * assumes pre-multiplied alpha anyway).
     *
     * - decoding: set by user
     * - encoding: unused
     *)
    skip_alpha: Integer;

    (**
     * Number of macroblock rows at the top which are skipped.
     * - encoding: unused
     * - decoding: Set by user.
     *)
    skip_top: Integer;

    (**
     * Number of macroblock rows at the bottom which are skipped.
     * - encoding: unused
     * - decoding: Set by user.
     *)
    skip_bottom: Integer;

    (**
     * low resolution decoding, 1-> 1/2 size, 2->1/4 size
     * - encoding: unused
     * - decoding: Set by user.
     *)
    lowres: Integer;

    (**
     * AVCodecDescriptor
     * - encoding: unused.
     * - decoding: set by libavcodec.
     *)
    codec_descriptor: PAVCodecDescriptor;

    (**
     * Character encoding of the input subtitles file.
     * - decoding: set by user
     * - encoding: unused
     *)
    sub_charenc: PAnsiChar;

    (**
     * Subtitles character encoding mode. Formats or codecs might be adjusting
     * this setting (if they are doing the conversion themselves for instance).
     * - decoding: set by libavcodec
     * - encoding: unused
     *)
    sub_charenc_mode: Integer;
{
#define FF_SUB_CHARENC_MODE_DO_NOTHING  -1  ///< do nothing (demuxer outputs a stream supposed to be already in UTF-8, or the codec is bitmap for instance)
#define FF_SUB_CHARENC_MODE_AUTOMATIC    0  ///< libavcodec will select the mode itself
#define FF_SUB_CHARENC_MODE_PRE_DECODER  1  ///< the AVPacket data needs to be recoded to UTF-8 before being fed to the decoder, requires iconv
#define FF_SUB_CHARENC_MODE_IGNORE       2  ///< neither convert the subtitles, nor check them for valid UTF-8
}

    (**
     * Header containing style information for text subtitles.
     * For SUBTITLE_ASS subtitle type, it should contain the whole ASS
     * [Script Info] and [V4+ Styles] section, plus the [Events] line and
     * the Format line following. It shouldn't include any Dialogue line.
     * - encoding: Set/allocated/freed by user (before avcodec_open2())
     * - decoding: Set/allocated/freed by libavcodec (by avcodec_open2())
     *)
    subtitle_header_size: Integer;
    subtitle_header: PByte;

    (**
     * dump format separator.
     * can be ", " or "\n      " or anything else
     * - encoding: Set by user.
     * - decoding: Set by user.
     *)
    dump_separator: PByte;

    (**
     * ',' separated list of allowed decoders.
     * If NULL then all are allowed
     * - encoding: unused
     * - decoding: set by user
     *)
    codec_whitelist: PAnsiChar;

    (**
     * Additional data associated with the entire coded stream.
     *
     * - decoding: may be set by user before calling avcodec_open2().
     * - encoding: may be set by libavcodec after avcodec_open2().
     *)
    coded_side_data: PAVPacketSideData;
    nb_coded_side_data: Integer;

    (**
     * Bit set of AV_CODEC_EXPORT_DATA_* flags, which affects the kind of
     * metadata exported in frame, packet, or coded stream side data by
     * decoders and encoders.
     *
     * - decoding: set by user
     * - encoding: set by user
     *)
    export_side_data: Integer;

    (**
     * The number of pixels per image to maximally accept.
     *
     * - decoding: set by user
     * - encoding: set by user
     *)
    max_pixels: Int64;

    (**
     * Video decoding only. Certain video codecs support cropping, meaning that
     * only a sub-rectangle of the decoded frame is intended for display.  This
     * option controls how cropping is handled by libavcodec.
     *
     * When set to 1 (the default), libavcodec will apply cropping internally.
     * I.e. it will modify the output frame width/height fields and offset the
     * data pointers (only by as much as possible while preserving alignment, or
     * by the full amount if the AV_CODEC_FLAG_UNALIGNED flag is set) so that
     * the frames output by the decoder refer only to the cropped area. The
     * crop_* fields of the output frames will be zero.
     *
     * When set to 0, the width/height fields of the output frames will be set
     * to the coded dimensions and the crop_* fields will describe the cropping
     * rectangle. Applying the cropping is left to the caller.
     *
     * @warning When hardware acceleration with opaque output frames is used,
     * libavcodec is unable to apply cropping from the top/left border.
     *
     * @note when this option is set to zero, the width/height fields of the
     * AVCodecContext and output AVFrames have different meanings. The codec
     * context fields store display dimensions (with the coded dimensions in
     * coded_width/height), while the frame fields store the coded dimensions
     * (with the display dimensions being determined by the crop_* fields).
     *)
    apply_cropping: Integer;

    (**
     * The percentage of damaged samples to discard a frame.
     *
     * - decoding: set by user
     * - encoding: unused
     *)
    discard_damaged_percentage: Integer;

    (**
     * The number of samples per frame to maximally accept.
     *
     * - decoding: set by user
     * - encoding: set by user
     *)
    max_samples: Int64;

    (**
     * This callback is called at the beginning of each packet to get a data
     * buffer for it.
     *
     * The following field will be set in the packet before this callback is
     * called:
     * - size
     * This callback must use the above value to calculate the required buffer size,
     * which must padded by at least AV_INPUT_BUFFER_PADDING_SIZE bytes.
     *
     * In some specific cases, the encoder may not use the entire buffer allocated by this
     * callback. This will be reflected in the size value in the packet once returned by
     * avcodec_receive_packet().
     *
     * This callback must fill the following fields in the packet:
     * - data: alignment requirements for AVPacket apply, if any. Some architectures and
     *   encoders may benefit from having aligned data.
     * - buf: must contain a pointer to an AVBufferRef structure. The packet's
     *   data pointer must be contained in it. See: av_buffer_create(), av_buffer_alloc(),
     *   and av_buffer_ref().
     *
     * If AV_CODEC_CAP_DR1 is not set then get_encode_buffer() must call
     * avcodec_default_get_encode_buffer() instead of providing a buffer allocated by
     * some other means.
     *
     * The flags field may contain a combination of AV_GET_ENCODE_BUFFER_FLAG_ flags.
     * They may be used for example to hint what use the buffer may get after being
     * created.
     * Implementations of this callback may ignore flags they don't understand.
     * If AV_GET_ENCODE_BUFFER_FLAG_REF is set in flags then the packet may be reused
     * (read and/or written to if it is writable) later by libavcodec.
     *
     * This callback must be thread-safe, as when frame threading is used, it may
     * be called from multiple threads simultaneously.
     *
     * @see avcodec_default_get_encode_buffer()
     *
     * - encoding: Set by libavcodec, user can override.
     * - decoding: unused
     *)
    get_encode_buffer: function(s: PAVCodecContext; pkt: PAVPacket; flags: Integer): Integer; cdecl;

    (**
     * Frame counter, set by libavcodec.
     *
     * - decoding: total number of frames returned from the decoder so far.
     * - encoding: total number of frames passed to the encoder so far.
     *
     *   @note the counter is not incremented if encoding/decoding resulted in
     *   an error.
     *)
    frame_num: Int64;

    (**
     * Decoding only. May be set by the caller before avcodec_open2() to an
     * av_malloc()'ed array (or via AVOptions). Owned and freed by the decoder
     * afterwards.
     *
     * Side data attached to decoded frames may come from several sources:
     * 1. coded_side_data, which the decoder will for certain types translate
     *    from packet-type to frame-type and attach to frames;
     * 2. side data attached to an AVPacket sent for decoding (same
     *    considerations as above);
     * 3. extracted from the coded bytestream.
     * The first two cases are supplied by the caller and typically come from a
     * container.
     *
     * This array configures decoder behaviour in cases when side data of the
     * same type is present both in the coded bytestream and in the
     * user-supplied side data (items 1. and 2. above). In all cases, at most
     * one instance of each side data type will be attached to output frames. By
     * default it will be the bytestream side data. Adding an
     * AVPacketSideDataType value to this array will flip the preference for
     * this type, thus making the decoder prefer user-supplied side data over
     * bytestream. In case side data of the same type is present both in
     * coded_data and attacked to a packet, the packet instance always has
     * priority.
     *
     * The array may also contain a single -1, in which case the preference is
     * switched for all side data types.
     *)
    side_data_prefer_packet: PInteger;

    (**
     * Number of entries in side_data_prefer_packet.
     *)
    nb_side_data_prefer_packet: Cardinal;

    (**
     * Array containing static side data, such as HDR10 CLL / MDCV structures.
     * Side data entries should be allocated by usage of helpers defined in
     * libavutil/frame.h.
     *
     * - encoding: may be set by user before calling avcodec_open2() for
     *             encoder configuration. Afterwards owned and freed by the
     *             encoder.
     * - decoding: may be set by libavcodec in avcodec_open2().
     *)
    decoded_side_data: PPAVFrameSideData;
    nb_decoded_side_data: Integer;
end;

(**
 * @defgroup lavc_hwaccel AVHWAccel
 *
 * @note  Nothing in this structure should be accessed by the user.  At some
 *        point in future it will not be externally visible at all.
 *
 * @{
 *)
  TAVHWAccel = record
    (**
     * Name of the hardware accelerated codec.
     * The name is globally unique among encoders and among decoders (but an
     * encoder and a decoder can share the same name).
     *)
    name: PAnsiChar;

    (**
     * Type of codec implemented by the hardware accelerator.
     *
     * See AVMEDIA_TYPE_xxx
     *)
    type_: TAVMediaType;

    (**
     * Codec implemented by the hardware accelerator.
     *
     * See AV_CODEC_ID_xxx
     *)
    id: TAVCodecID;

    (**
     * Supported pixel format.
     *
     * Only hardware accelerated formats are supported here.
     *)
    pix_fmt: TAVPixelFormat;

    (**
     * Hardware accelerated codec capabilities.
     * see AV_HWACCEL_CODEC_CAP_*
     *)
    capabilities: Integer;
  end;

(**
 * @}
 *)

(**
 * Picture data structure.
 *
 * Up to four components can be stored into it, the last component is
 * alpha.
 * @deprecated use AVFrame or imgutils functions instead
 *)
  PAVPicture = ^TAVPicture;
  TAVPicture = record
    data: array[0..AV_NUM_DATA_POINTERS-1] of PByte;        ///< pointers to the image data planes
    linesize: array[0..AV_NUM_DATA_POINTERS-1] of Integer;  ///< number of bytes per line
  end;

  TAVSubtitleType = (
    SUBTITLE_NONE,

    SUBTITLE_BITMAP,                ///< A bitmap, pict will be set

    (**
     * Plain text, the text field must be set by the decoder and is
     * authoritative. ass and pict fields may contain approximations.
     *)
    SUBTITLE_TEXT,

    (**
     * Formatted text, the ass field must be set by the decoder and is
     * authoritative. pict and text fields may contain approximations.
     *)
    SUBTITLE_ASS
  );

//#define AV_SUBTITLE_FLAG_FORCED 0x00000001

  PPAVSubtitleRect = ^PAVSubtitleRect;
  PAVSubtitleRect = ^TAVSubtitleRect;
  TAVSubtitleRect = record
    x: Integer;         ///< top left corner  of pict, undefined when pict is not set
    y: Integer;         ///< top left corner  of pict, undefined when pict is not set
    w: Integer;         ///< width            of pict, undefined when pict is not set
    h: Integer;         ///< height           of pict, undefined when pict is not set
    nb_colors: Integer; ///< number of colors in pict, undefined when pict is not set

    (**
     * data+linesize for the bitmap of this subtitle.
     * Can be set for text/ass as well once they are rendered.
     *)
    data: array[0..3] of PByte;
    linesize: array[0..3] of Integer;

    flags: Integer;
    type_: TAVSubtitleType;

    text: PAnsiChar;                     ///< 0 terminated plain UTF-8 text

    (**
     * 0 terminated ASS/SSA compatible event line.
     * The presentation of this is unaffected by the other values in this
     * struct.
     *)
    ass: PAnsiChar;
  end;

  PAVSubtitle = ^TAVSubtitle;
  TAVSubtitle = record
    format: Word; (* 0 = graphics *)
    start_display_time: Cardinal; (* relative to packet pts, in ms *)
    end_display_time: Cardinal; (* relative to packet pts, in ms *)
    num_rects: Cardinal;
    rects: PPAVSubtitleRect;
    pts: Int64;    ///< Same as packet pts, in AV_TIME_BASE
  end;

(**
 * Return the LIBAVCODEC_VERSION_INT constant.
 *)
function avcodec_version: Cardinal; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_version';

(**
 * Return the libavcodec build-time configuration.
 *)
function avcodec_configuration: PAnsiChar; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_configuration';

(**
 * Return the libavcodec license.
 *)
function avcodec_license: PAnsiChar; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_license';

(**
 * Allocate an AVCodecContext and set its fields to default values. The
 * resulting struct should be freed with avcodec_free_context().
 *
 * @param codec if non-NULL, allocate private data and initialize defaults
 *              for the given codec. It is illegal to then call avcodec_open2()
 *              with a different codec.
 *              If NULL, then the codec-specific defaults won't be initialized,
 *              which may result in suboptimal default settings (this is
 *              important mainly for encoders, e.g. libx264).
 *
 * @return An AVCodecContext filled with default values or NULL on failure.
 *)
function avcodec_alloc_context3(const codec: PAVCodec): PAVCodecContext; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_alloc_context3';

(**
 * Free the codec context and everything associated with it and write NULL to
 * the provided pointer.
 *)
procedure avcodec_free_context(avctx: PPAVCodecContext); cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_free_context';

(**
 * Get the AVClass for AVCodecContext. It can be used in combination with
 * AV_OPT_SEARCH_FAKE_OBJ for examining options.
 *
 * @see av_opt_find().
 *)
function avcodec_get_class(): PAVClass; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_get_class';

(**
 * Get the AVClass for AVSubtitleRect. It can be used in combination with
 * AV_OPT_SEARCH_FAKE_OBJ for examining options.
 *
 * @see av_opt_find().
 *)
function avcodec_get_subtitle_rect_class(): PAVClass; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_get_subtitle_rect_class';

(**
 * Fill the parameters struct based on the values from the supplied codec
 * context. Any allocated fields in par are freed and replaced with duplicates
 * of the corresponding fields in codec.
 *
 * @return >= 0 on success, a negative AVERROR code on failure
 *)
function avcodec_parameters_from_context(par: PAVCodecParameters; const codec: PAVCodecContext): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_parameters_from_context';

(**
 * Fill the codec context based on the values from the supplied codec
 * parameters. Any allocated fields in codec that have a corresponding field in
 * par are freed and replaced with duplicates of the corresponding field in par.
 * Fields in codec that do not have a counterpart in par are not touched.
 *
 * @return >= 0 on success, a negative AVERROR code on failure.
 *)
function avcodec_parameters_to_context(codec: PAVCodecContext; const par: PAVCodecParameters): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_parameters_to_context';

(**
 * Initialize the AVCodecContext to use the given AVCodec. Prior to using this
 * function the context has to be allocated with avcodec_alloc_context3().
 *
 * The functions avcodec_find_decoder_by_name(), avcodec_find_encoder_by_name(),
 * avcodec_find_decoder() and avcodec_find_encoder() provide an easy way for
 * retrieving a codec.
 *
 * Depending on the codec, you might need to set options in the codec context
 * also for decoding (e.g. width, height, or the pixel or audio sample format in
 * the case the information is not available in the bitstream, as when decoding
 * raw audio or video).
 *
 * Options in the codec context can be set either by setting them in the options
 * AVDictionary, or by setting the values in the context itself, directly or by
 * using the av_opt_set() API before calling this function.
 *
 * Example:
 * @code
 * av_dict_set(&opts, "b", "2.5M", 0);
 * codec = avcodec_find_decoder(AV_CODEC_ID_H264);
 * if (!codec)
 *     exit(1);
 *
 * context = avcodec_alloc_context3(codec);
 *
 * if (avcodec_open2(context, codec, opts) < 0)
 *     exit(1);
 * @endcode
 *
 * In the case AVCodecParameters are available (e.g. when demuxing a stream
 * using libavformat, and accessing the AVStream contained in the demuxer), the
 * codec parameters can be copied to the codec context using
 * avcodec_parameters_to_context(), as in the following example:
 *
 * @code
 * AVStream *stream = ...;
 * context = avcodec_alloc_context3(codec);
 * if (avcodec_parameters_to_context(context, stream->codecpar) < 0)
 *     exit(1);
 * if (avcodec_open2(context, codec, NULL) < 0)
 *     exit(1);
 * @endcode
 *
 * @note Always call this function before using decoding routines (such as
 * @ref avcodec_receive_frame()).
 *
 * @param avctx The context to initialize.
 * @param codec The codec to open this context for. If a non-NULL codec has been
 *              previously passed to avcodec_alloc_context3() or
 *              for this context, then this parameter MUST be either NULL or
 *              equal to the previously passed codec.
 * @param options A dictionary filled with AVCodecContext and codec-private
 *                options, which are set on top of the options already set in
 *                avctx, can be NULL. On return this object will be filled with
 *                options that were not found in the avctx codec context.
 *
 * @return zero on success, a negative value on error
 * @see avcodec_alloc_context3(), avcodec_find_decoder(), avcodec_find_encoder(),
 *      av_dict_set(), av_opt_set(), av_opt_find(), avcodec_parameters_to_context()
 *)
function avcodec_open2(avctx: PAVCodecContext; const codec: PAVCodec; options: PPAVDictionary): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_open2';

{$IFDEF FF_API_AVCODEC_CLOSE}
(**
 * Close a given AVCodecContext and free all the data associated with it
 * (but not the AVCodecContext itself).
 *
 * Calling this function on an AVCodecContext that hasn't been opened will free
 * the codec-specific data allocated in avcodec_alloc_context3() with a non-NULL
 * codec. Subsequent calls will do nothing.
 *
 * @deprecated Do not use this function. Use avcodec_free_context() to destroy a
 * codec context (either open or closed). Opening and closing a codec context
 * multiple times is not supported anymore -- use multiple codec contexts
 * instead.
 *)
function avcodec_close(avctx: PAVCodecContext): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_close';
{$ENDIF}

(**
 * Free all allocated data in the given subtitle struct.
 *
 * @param sub AVSubtitle to free.
 *)
procedure avsubtitle_free(sub: PAVSubtitle); cdecl; external AVCODEC_LIBNAME name _PU + 'avsubtitle_free';

(**
 * @}
 *)

(**
 * @addtogroup lavc_decoding
 * @{
 *)

(**
 * The default callback for AVCodecContext.get_buffer2(). It is made public so
 * it can be called by custom get_buffer2() implementations for decoders without
 * AV_CODEC_CAP_DR1 set.
 *)
function avcodec_default_get_buffer2(s: PAVCodecContext; frame: PAVFrame; flags: Integer): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_default_get_buffer2';

(**
 * The default callback for AVCodecContext.get_encode_buffer(). It is made public so
 * it can be called by custom get_encode_buffer() implementations for encoders without
 * AV_CODEC_CAP_DR1 set.
 *)
function avcodec_default_get_encode_buffer(s: PAVCodecContext; pkt: PAVPacket; flags: Integer): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_default_get_encode_buffer';

(**
 * Modify width and height values so that they will result in a memory
 * buffer that is acceptable for the codec if you do not use any horizontal
 * padding.
 *
 * May only be used if a codec with AV_CODEC_CAP_DR1 has been opened.
 *)
procedure avcodec_align_dimensions(s: PAVCodecContext; width, height: PInteger); cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_align_dimensions';

(**
 * Modify width and height values so that they will result in a memory
 * buffer that is acceptable for the codec if you also ensure that all
 * line sizes are a multiple of the respective linesize_align[i].
 *
 * May only be used if a codec with AV_CODEC_CAP_DR1 has been opened.
 *)
procedure avcodec_align_dimensions2(s: PAVCodecContext; width, height: PInteger;
                               linesize_align: PInteger{int linesize_align[AV_NUM_DATA_POINTERS]}); cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_align_dimensions2';

(**
 * Decode a subtitle message.
 * Return a negative value on error, otherwise return the number of bytes used.
 * If no subtitle could be decompressed, got_sub_ptr is zero.
 * Otherwise, the subtitle is stored in *sub.
 * Note that AV_CODEC_CAP_DR1 is not available for subtitle codecs. This is for
 * simplicity, because the performance difference is expected to be negligible
 * and reusing a get_buffer written for video codecs would probably perform badly
 * due to a potentially very different allocation pattern.
 *
 * Some decoders (those marked with AV_CODEC_CAP_DELAY) have a delay between input
 * and output. This means that for some packets they will not immediately
 * produce decoded output and need to be flushed at the end of decoding to get
 * all the decoded data. Flushing is done by calling this function with packets
 * with avpkt->data set to NULL and avpkt->size set to 0 until it stops
 * returning subtitles. It is safe to flush even those decoders that are not
 * marked with AV_CODEC_CAP_DELAY, then no subtitles will be returned.
 *
 * @note The AVCodecContext MUST have been opened with @ref avcodec_open2()
 * before packets may be fed to the decoder.
 *
 * @param avctx the codec context
 * @param[out] sub The preallocated AVSubtitle in which the decoded subtitle will be stored,
 *                 must be freed with avsubtitle_free if *got_sub_ptr is set.
 * @param[in,out] got_sub_ptr Zero if no subtitle could be decompressed, otherwise, it is nonzero.
 * @param[in] avpkt The input AVPacket containing the input buffer.
 *)
function avcodec_decode_subtitle2(avctx: PAVCodecContext; sub: PAVSubtitle;
                            got_sub_ptr: PInteger; const avpkt: PAVPacket): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_decode_subtitle2';

(**
 * Supply raw packet data as input to a decoder.
 *
 * Internally, this call will copy relevant AVCodecContext fields, which can
 * influence decoding per-packet, and apply them when the packet is actually
 * decoded. (For example AVCodecContext.skip_frame, which might direct the
 * decoder to drop the frame contained by the packet sent with this function.)
 *
 * @warning The input buffer, avpkt->data must be AV_INPUT_BUFFER_PADDING_SIZE
 *          larger than the actual read bytes because some optimized bitstream
 *          readers read 32 or 64 bits at once and could read over the end.
 *
 * @note The AVCodecContext MUST have been opened with @ref avcodec_open2()
 *       before packets may be fed to the decoder.
 *
 * @param avctx codec context
 * @param[in] avpkt The input AVPacket. Usually, this will be a single video
 *                  frame, or several complete audio frames.
 *                  Ownership of the packet remains with the caller, and the
 *                  decoder will not write to the packet. The decoder may create
 *                  a reference to the packet data (or copy it if the packet is
 *                  not reference-counted).
 *                  Unlike with older APIs, the packet is always fully consumed,
 *                  and if it contains multiple frames (e.g. some audio codecs),
 *                  will require you to call avcodec_receive_frame() multiple
 *                  times afterwards before you can send a new packet.
 *                  It can be NULL (or an AVPacket with data set to NULL and
 *                  size set to 0); in this case, it is considered a flush
 *                  packet, which signals the end of the stream. Sending the
 *                  first flush packet will return success. Subsequent ones are
 *                  unnecessary and will return AVERROR_EOF. If the decoder
 *                  still has frames buffered, it will return them after sending
 *                  a flush packet.
 *
 * @retval 0                 success
 * @retval AVERROR(EAGAIN)   input is not accepted in the current state - user
 *                           must read output with avcodec_receive_frame() (once
 *                           all output is read, the packet should be resent,
 *                           and the call will not fail with EAGAIN).
 * @retval AVERROR_EOF       the decoder has been flushed, and no new packets can be
 *                           sent to it (also returned if more than 1 flush
 *                           packet is sent)
 * @retval AVERROR(EINVAL)   codec not opened, it is an encoder, or requires flush
 * @retval AVERROR(ENOMEM)   failed to add packet to internal queue, or similar
 * @retval "another negative error code" legitimate decoding errors
 *)
function avcodec_send_packet(avctx: PAVCodecContext; const avpkt: PAVPacket): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_send_packet';

(**
 * Return decoded output data from a decoder or encoder (when the
 * @ref AV_CODEC_FLAG_RECON_FRAME flag is used).
 *
 * @param avctx codec context
 * @param frame This will be set to a reference-counted video or audio
 *              frame (depending on the decoder type) allocated by the
 *              codec. Note that the function will always call
 *              av_frame_unref(frame) before doing anything else.
 *
 * @retval 0                success, a frame was returned
 * @retval AVERROR(EAGAIN)  output is not available in this state - user must
 *                          try to send new input
 * @retval AVERROR_EOF      the codec has been fully flushed, and there will be
 *                          no more output frames
 * @retval AVERROR(EINVAL)  codec not opened, or it is an encoder without the
 *                          @ref AV_CODEC_FLAG_RECON_FRAME flag enabled
 * @retval "other negative error code" legitimate decoding errors
 *)
function avcodec_receive_frame(avctx: PAVCodecContext; frame: PAVFrame): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_receive_frame';

(**
 * Supply a raw video or audio frame to the encoder. Use avcodec_receive_packet()
 * to retrieve buffered output packets.
 *
 * @param avctx     codec context
 * @param[in] frame AVFrame containing the raw audio or video frame to be encoded.
 *                  Ownership of the frame remains with the caller, and the
 *                  encoder will not write to the frame. The encoder may create
 *                  a reference to the frame data (or copy it if the frame is
 *                  not reference-counted).
 *                  It can be NULL, in which case it is considered a flush
 *                  packet.  This signals the end of the stream. If the encoder
 *                  still has packets buffered, it will return them after this
 *                  call. Once flushing mode has been entered, additional flush
 *                  packets are ignored, and sending frames will return
 *                  AVERROR_EOF.
 *
 *                  For audio:
 *                  If AV_CODEC_CAP_VARIABLE_FRAME_SIZE is set, then each frame
 *                  can have any number of samples.
 *                  If it is not set, frame->nb_samples must be equal to
 *                  avctx->frame_size for all frames except the last.
 *                  The final frame may be smaller than avctx->frame_size.
 * @retval 0                 success
 * @retval AVERROR(EAGAIN)   input is not accepted in the current state - user must
 *                           read output with avcodec_receive_packet() (once all
 *                           output is read, the packet should be resent, and the
 *                           call will not fail with EAGAIN).
 * @retval AVERROR_EOF       the encoder has been flushed, and no new frames can
 *                           be sent to it
 * @retval AVERROR(EINVAL)   codec not opened, it is a decoder, or requires flush
 * @retval AVERROR(ENOMEM)   failed to add packet to internal queue, or similar
 * @retval "another negative error code" legitimate encoding errors
 *)
function avcodec_send_frame(avctx: PAVCodecContext; const frame: PAVFrame): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_send_frame';

(**
 * Read encoded data from the encoder.
 *
 * @param avctx codec context
 * @param avpkt This will be set to a reference-counted packet allocated by the
 *              encoder. Note that the function will always call
 *              av_packet_unref(avpkt) before doing anything else.
 * @retval 0               success
 * @retval AVERROR(EAGAIN) output is not available in the current state - user must
 *                         try to send input
 * @retval AVERROR_EOF     the encoder has been fully flushed, and there will be no
 *                         more output packets
 * @retval AVERROR(EINVAL) codec not opened, or it is a decoder
 * @retval "another negative error code" legitimate encoding errors
 *)
function avcodec_receive_packet(avctx: PAVCodecContext; avpkt: PAVPacket): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_receive_packet';

(**
 * Create and return a AVHWFramesContext with values adequate for hardware
 * decoding. This is meant to get called from the get_format callback, and is
 * a helper for preparing a AVHWFramesContext for AVCodecContext.hw_frames_ctx.
 * This API is for decoding with certain hardware acceleration modes/APIs only.
 *
 * The returned AVHWFramesContext is not initialized. The caller must do this
 * with av_hwframe_ctx_init().
 *
 * Calling this function is not a requirement, but makes it simpler to avoid
 * codec or hardware API specific details when manually allocating frames.
 *
 * Alternatively to this, an API user can set AVCodecContext.hw_device_ctx,
 * which sets up AVCodecContext.hw_frames_ctx fully automatically, and makes
 * it unnecessary to call this function or having to care about
 * AVHWFramesContext initialization at all.
 *
 * There are a number of requirements for calling this function:
 *
 * - It must be called from get_format with the same avctx parameter that was
 *   passed to get_format. Calling it outside of get_format is not allowed, and
 *   can trigger undefined behavior.
 * - The function is not always supported (see description of return values).
 *   Even if this function returns successfully, hwaccel initialization could
 *   fail later. (The degree to which implementations check whether the stream
 *   is actually supported varies. Some do this check only after the user's
 *   get_format callback returns.)
 * - The hw_pix_fmt must be one of the choices suggested by get_format. If the
 *   user decides to use a AVHWFramesContext prepared with this API function,
 *   the user must return the same hw_pix_fmt from get_format.
 * - The device_ref passed to this function must support the given hw_pix_fmt.
 * - After calling this API function, it is the user's responsibility to
 *   initialize the AVHWFramesContext (returned by the out_frames_ref parameter),
 *   and to set AVCodecContext.hw_frames_ctx to it. If done, this must be done
 *   before returning from get_format (this is implied by the normal
 *   AVCodecContext.hw_frames_ctx API rules).
 * - The AVHWFramesContext parameters may change every time time get_format is
 *   called. Also, AVCodecContext.hw_frames_ctx is reset before get_format. So
 *   you are inherently required to go through this process again on every
 *   get_format call.
 * - It is perfectly possible to call this function without actually using
 *   the resulting AVHWFramesContext. One use-case might be trying to reuse a
 *   previously initialized AVHWFramesContext, and calling this API function
 *   only to test whether the required frame parameters have changed.
 * - Fields that use dynamically allocated values of any kind must not be set
 *   by the user unless setting them is explicitly allowed by the documentation.
 *   If the user sets AVHWFramesContext.free and AVHWFramesContext.user_opaque,
 *   the new free callback must call the potentially set previous free callback.
 *   This API call may set any dynamically allocated fields, including the free
 *   callback.
 *
 * The function will set at least the following fields on AVHWFramesContext
 * (potentially more, depending on hwaccel API):
 *
 * - All fields set by av_hwframe_ctx_alloc().
 * - Set the format field to hw_pix_fmt.
 * - Set the sw_format field to the most suited and most versatile format. (An
 *   implication is that this will prefer generic formats over opaque formats
 *   with arbitrary restrictions, if possible.)
 * - Set the width/height fields to the coded frame size, rounded up to the
 *   API-specific minimum alignment.
 * - Only _if_ the hwaccel requires a pre-allocated pool: set the initial_pool_size
 *   field to the number of maximum reference surfaces possible with the codec,
 *   plus 1 surface for the user to work (meaning the user can safely reference
 *   at most 1 decoded surface at a time), plus additional buffering introduced
 *   by frame threading. If the hwaccel does not require pre-allocation, the
 *   field is left to 0, and the decoder will allocate new surfaces on demand
 *   during decoding.
 * - Possibly AVHWFramesContext.hwctx fields, depending on the underlying
 *   hardware API.
 *
 * Essentially, out_frames_ref returns the same as av_hwframe_ctx_alloc(), but
 * with basic frame parameters set.
 *
 * The function is stateless, and does not change the AVCodecContext or the
 * device_ref AVHWDeviceContext.
 *
 * @param avctx The context which is currently calling get_format, and which
 *              implicitly contains all state needed for filling the returned
 *              AVHWFramesContext properly.
 * @param device_ref A reference to the AVHWDeviceContext describing the device
 *                   which will be used by the hardware decoder.
 * @param hw_pix_fmt The hwaccel format you are going to return from get_format.
 * @param out_frames_ref On success, set to a reference to an _uninitialized_
 *                       AVHWFramesContext, created from the given device_ref.
 *                       Fields will be set to values required for decoding.
 *                       Not changed if an error is returned.
 * @return zero on success, a negative value on error. The following error codes
 *         have special semantics:
 *      AVERROR(ENOENT): the decoder does not support this functionality. Setup
 *                       is always manual, or it is a decoder which does not
 *                       support setting AVCodecContext.hw_frames_ctx at all,
 *                       or it is a software format.
 *      AVERROR(EINVAL): it is known that hardware decoding is not supported for
 *                       this configuration, or the device_ref is not supported
 *                       for the hwaccel referenced by hw_pix_fmt.
 *)
function avcodec_get_hw_frames_parameters(avctx: PAVCodecContext;
                                     device_ref: PAVBufferRef;
                                     hw_pix_fmt: TAVPixelFormat;
                                     out_frames_ref: PPAVBufferRef): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_get_hw_frames_parameters';

type
  TAVCodecConfig = (
    AV_CODEC_CONFIG_PIX_FORMAT,     ///< AVPixelFormat, terminated by AV_PIX_FMT_NONE
    AV_CODEC_CONFIG_FRAME_RATE,     ///< AVRational, terminated by begin 0, 0 end
    AV_CODEC_CONFIG_SAMPLE_RATE,    ///< int, terminated by 0
    AV_CODEC_CONFIG_SAMPLE_FORMAT,  ///< AVSampleFormat, terminated by AV_SAMPLE_FMT_NONE
    AV_CODEC_CONFIG_CHANNEL_LAYOUT, ///< AVChannelLayout, terminated by begin 0 end
    AV_CODEC_CONFIG_COLOR_RANGE,    ///< AVColorRange, terminated by AVCOL_RANGE_UNSPECIFIED
    AV_CODEC_CONFIG_COLOR_SPACE     ///< AVColorSpace, terminated by AVCOL_SPC_UNSPECIFIED
  );

(**
 * Retrieve a list of all supported values for a given configuration type.
 *
 * @param avctx An optional context to use. Values such as
 *              `strict_std_compliance` may affect the result. If NULL,
 *              default values are used.
 * @param codec The codec to query, or NULL to use avctx->codec.
 * @param config The configuration to query.
 * @param flags Currently unused; should be set to zero.
 * @param out_configs On success, set to a list of configurations, terminated
 *                    by a config-specific terminator, or NULL if all
 *                    possible values are supported.
 * @param out_num_configs On success, set to the number of elements in
                          *out_configs, excluding the terminator. Optional.
 *)
function avcodec_get_supported_config(const avctx: PAVCodecContext;
                                 const codec: PAVCodec; config: TAVCodecConfig;
                                 flags: Cardinal; const out_configs: PPointer;
                                 out_num_configs: PInteger): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_get_supported_config';


(**
 * @defgroup lavc_parsing Frame parsing
 * @{
 *)

const
  AV_PARSER_PTS_NB = 4;
  PARSER_FLAG_COMPLETE_FRAMES = $0001;
  PARSER_FLAG_ONCE            = $0002;
  PARSER_FLAG_FETCHED_OFFSET  = $0004;
  PARSER_FLAG_USE_CODEC_TS    = $1000;

type
  TAVPictureStructure = (
    AV_PICTURE_STRUCTURE_UNKNOWN,      ///< unknown
    AV_PICTURE_STRUCTURE_TOP_FIELD,    ///< coded as top field
    AV_PICTURE_STRUCTURE_BOTTOM_FIELD, ///< coded as bottom field
    AV_PICTURE_STRUCTURE_FRAME         ///< coded as frame
  );

  PAVCodecParserContext = ^TAVCodecParserContext;
  PAVCodecParser = ^TAVCodecParser;
  TAVCodecParserContext = record
    priv_data: Pointer;
    parser: PAVCodecParser;
    frame_offset: Int64; (* offset of the current frame *)
    cur_offset: Int64; (* current offset
                           (incremented by each av_parser_parse()) *)
    next_frame_offset: Int64; (* offset of the next frame *)
    (* video info *)
    pict_type: Integer; (* XXX: Put it back in AVCodecContext. *)
    (**
     * This field is used for proper frame duration computation in lavf.
     * It signals, how much longer the frame duration of the current frame
     * is compared to normal frame duration.
     *
     * frame_duration = (1 + repeat_pict) * time_base
     *
     * It is used by codecs like H.264 to display telecined material.
     *)
    repeat_pict: Integer; (* XXX: Put it back in AVCodecContext. *)
    pts: Int64;     (* pts of the current frame *)
    dts: Int64;     (* dts of the current frame *)

    (* private data *)
    last_pts: Int64;
    last_dts: Int64;
    fetch_timestamp: Integer;

//#define AV_PARSER_PTS_NB 4
    cur_frame_start_index: Integer;
    cur_frame_offset: array[0..AV_PARSER_PTS_NB-1] of Int64;
    cur_frame_pts: array[0..AV_PARSER_PTS_NB-1] of Int64;
    cur_frame_dts: array[0..AV_PARSER_PTS_NB-1] of Int64;

    flags: Integer;
//#define PARSER_FLAG_COMPLETE_FRAMES           0x0001
//#define PARSER_FLAG_ONCE                      0x0002
/// Set if the parser has a valid file offset
//#define PARSER_FLAG_FETCHED_OFFSET            0x0004
//#define PARSER_FLAG_USE_CODEC_TS              0x1000

    offset: Int64;      ///< byte offset from starting packet start
    cur_frame_end: array[0..AV_PARSER_PTS_NB-1] of Int64;

    (**
     * Set by parser to 1 for key frames and 0 for non-key frames.
     * It is initialized to -1, so if the parser doesn't set this flag,
     * old-style fallback using AV_PICTURE_TYPE_I picture type as key frames
     * will be used.
     *)
    key_frame: Integer;

    // Timestamp generation support:
    (**
     * Synchronization point for start of timestamp generation.
     *
     * Set to >0 for sync point, 0 for no sync point and <0 for undefined
     * (default).
     *
     * For example, this corresponds to presence of H.264 buffering period
     * SEI message.
     *)
    dts_sync_point: Integer;

    (**
     * Offset of the current timestamp against last timestamp sync point in
     * units of AVCodecContext.time_base.
     *
     * Set to INT_MIN when dts_sync_point unused. Otherwise, it must
     * contain a valid timestamp offset.
     *
     * Note that the timestamp of sync point has usually a nonzero
     * dts_ref_dts_delta, which refers to the previous sync point. Offset of
     * the next frame after timestamp sync point will be usually 1.
     *
     * For example, this corresponds to H.264 cpb_removal_delay.
     *)
    dts_ref_dts_delta: Integer;

    (**
     * Presentation delay of current frame in units of AVCodecContext.time_base.
     *
     * Set to INT_MIN when dts_sync_point unused. Otherwise, it must
     * contain valid non-negative timestamp delta (presentation time of a frame
     * must not lie in the past).
     *
     * This delay represents the difference between decoding and presentation
     * time of the frame.
     *
     * For example, this corresponds to H.264 dpb_output_delay.
     *)
    pts_dts_delta: Integer;

    (**
     * Position of the packet in file.
     *
     * Analogous to cur_frame_pts/dts
     *)
    cur_frame_pos: array[0..AV_PARSER_PTS_NB-1] of Int64;

    (**
     * Byte position of currently parsed frame in stream.
     *)
    pos: Int64;

    (**
     * Previous frame byte position.
     *)
    last_pos: Int64;

    (**
     * Duration of the current frame.
     * For audio, this is in units of 1 / AVCodecContext.sample_rate.
     * For all other types, this is in units of AVCodecContext.time_base.
     *)
    duration: Integer;

    field_order: TAVFieldOrder;

    (**
     * Indicate whether a picture is coded as a frame, top field or bottom field.
     *
     * For example, H.264 field_pic_flag equal to 0 corresponds to
     * AV_PICTURE_STRUCTURE_FRAME. An H.264 picture with field_pic_flag
     * equal to 1 and bottom_field_flag equal to 0 corresponds to
     * AV_PICTURE_STRUCTURE_TOP_FIELD.
     *)
    picture_structure: TAVPictureStructure;

    (**
     * Picture number incremented in presentation or output order.
     * This field may be reinitialized at the first picture of a new sequence.
     *
     * For example, this corresponds to H.264 PicOrderCnt.
     *)
    output_picture_number: Integer;

    (**
     * Dimensions of the decoded video intended for presentation.
     *)
    width: Integer;
    height: Integer;

    (**
     * Dimensions of the coded video.
     *)
    coded_width: Integer;
    coded_height: Integer;

    (**
     * The format of the coded data, corresponds to enum AVPixelFormat for video
     * and for enum AVSampleFormat for audio.
     *
     * Note that a decoder can have considerable freedom in how exactly it
     * decodes the data, so the format reported here might be different from the
     * one returned by a decoder.
     *)
    format: Integer;
  end;

  TAVCodecParser = record
    codec_ids: array[0..6] of Integer; (* several codec IDs are permitted *)
    priv_data_size: Integer;
    parser_init: function(s: PAVCodecParserContext): Integer; cdecl;
    (* This callback never returns an error, a negative value means that
     * the frame start was in a previous packet. *)
    parser_parse: function(s: PAVCodecParserContext;
                        avctx: PAVCodecContext;
                        const poutbuf: PPByte; poutbuf_size: PInteger;
                        const buf: PByte; buf_size: Integer): Integer; cdecl;
    parser_close: procedure(s: PAVCodecParserContext); cdecl;
    split: function(avctx: PAVCodecContext; const buf: PByte; buf_size: Integer): Integer; cdecl;
  end;

(**
 * Iterate over all registered codec parsers.
 *
 * @param opaque a pointer where libavcodec will store the iteration state. Must
 *               point to NULL to start the iteration.
 *
 * @return the next registered codec parser or NULL when the iteration is
 *         finished
 *)
function av_parser_iterate(opaque: PPointer): PAVCodecParser; cdecl; external AVCODEC_LIBNAME name _PU + 'av_parser_iterate';

function av_parser_init(codec_id: Integer): PAVCodecParserContext; cdecl; external AVCODEC_LIBNAME name _PU + 'av_parser_init';

(**
 * Parse a packet.
 *
 * @param s             parser context.
 * @param avctx         codec context.
 * @param poutbuf       set to pointer to parsed buffer or NULL if not yet finished.
 * @param poutbuf_size  set to size of parsed buffer or zero if not yet finished.
 * @param buf           input buffer.
 * @param buf_size      buffer size in bytes without the padding. I.e. the full buffer
                        size is assumed to be buf_size + AV_INPUT_BUFFER_PADDING_SIZE.
                        To signal EOF, this should be 0 (so that the last frame
                        can be output).
 * @param pts           input presentation timestamp.
 * @param dts           input decoding timestamp.
 * @param pos           input byte position in stream.
 * @return the number of bytes of the input bitstream used.
 *
 * Example:
 * @code
 *   while(in_len){
 *       len = av_parser_parse2(myparser, AVCodecContext, &data, &size,
 *                                        in_data, in_len,
 *                                        pts, dts, pos);
 *       in_data += len;
 *       in_len  -= len;
 *
 *       if(size)
 *          decode_frame(data, size);
 *   }
 * @endcode
 *)
function av_parser_parse2(s: PAVCodecParserContext;
                     avctx: PAVCodecContext;
                     poutbuf: PPByte; poutbuf_size: PInteger;
                     const buf: PByte; buf_size: Integer;
                     pts, dts,
                     pos: Int64): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'av_parser_parse2';

procedure av_parser_close(s: PAVCodecParserContext); cdecl; external AVCODEC_LIBNAME name _PU + 'av_parser_close';

(**
 * @}
 * @}
 *)

(**
 * @addtogroup lavc_encoding
 * @{
 *)

function avcodec_encode_subtitle(avctx: PAVCodecContext; buf: PByte; buf_size: Integer;
                            const sub: PAVSubtitle): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_encode_subtitle';


(**
 * @}
 *)

(**
 * @defgroup lavc_misc Utility functions
 * @ingroup libavc
 *
 * Miscellaneous utility functions related to both encoding and decoding
 * (or neither).
 * @{
 *)

(**
 * @defgroup lavc_misc_pixfmt Pixel formats
 *
 * Functions for working with pixel formats.
 * @{
 *)

(**
 * Return a value representing the fourCC code associated to the
 * pixel format pix_fmt, or 0 if no associated fourCC code can be
 * found.
 *)
function avcodec_pix_fmt_to_codec_tag(pix_fmt: TAVPixelFormat): Cardinal; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_pix_fmt_to_codec_tag';

(**
 * Find the best pixel format to convert to given a certain source pixel
 * format.  When converting from one pixel format to another, information loss
 * may occur.  For example, when converting from RGB24 to GRAY, the color
 * information will be lost. Similarly, other losses occur when converting from
 * some formats to other formats. avcodec_find_best_pix_fmt_of_2() searches which of
 * the given pixel formats should be used to suffer the least amount of loss.
 * The pixel formats from which it chooses one, are determined by the
 * pix_fmt_list parameter.
 *
 *
 * @param[in] pix_fmt_list AV_PIX_FMT_NONE terminated array of pixel formats to choose from
 * @param[in] src_pix_fmt source pixel format
 * @param[in] has_alpha Whether the source pixel format alpha channel is used.
 * @param[out] loss_ptr Combination of flags informing you what kind of losses will occur.
 * @return The best pixel format to convert to or -1 if none was found.
 *)
function avcodec_find_best_pix_fmt_of_list(const pix_fmt_list: PAVPixelFormat;
                                            src_pix_fmt: TAVPixelFormat;
                                            has_alpha: Integer; loss_ptr: PInteger): TAVPixelFormat; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_find_best_pix_fmt_of_list';

function avcodec_default_get_format(s: PAVCodecContext; const fmt: PAVPixelFormat): TAVPixelFormat; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_default_get_format';

(**
 * @}
 *)

procedure avcodec_string(buf: PAnsiChar; buf_size: Integer; enc: PAVCodecContext; encode: Integer); cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_string';

function avcodec_default_execute(c: PAVCodecContext; func: TexecuteCall; arg: Pointer; ret: PInteger; count, size: Integer): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_default_execute';
function avcodec_default_execute2(c: PAVCodecContext; func: Texecute2Call; arg: Pointer; ret: PInteger; count: Integer): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_default_execute2';
//FIXME func typedef

(**
 * Fill AVFrame audio data and linesize pointers.
 *
 * The buffer buf must be a preallocated buffer with a size big enough
 * to contain the specified samples amount. The filled AVFrame data
 * pointers will point to this buffer.
 *
 * AVFrame extended_data channel pointers are allocated if necessary for
 * planar audio.
 *
 * @param frame       the AVFrame
 *                    frame->nb_samples must be set prior to calling the
 *                    function. This function fills in frame->data,
 *                    frame->extended_data, frame->linesize[0].
 * @param nb_channels channel count
 * @param sample_fmt  sample format
 * @param buf         buffer to use for frame data
 * @param buf_size    size of buffer
 * @param align       plane size sample alignment (0 = default)
 * @return            >=0 on success, negative error code on failure
 * @todo return the size in bytes required to store the samples in
 * case of success, at the next libavutil bump
 *)
function avcodec_fill_audio_frame(frame: PAVFrame; nb_channels: Integer;
                             sample_fmt: TAVSampleFormat; const buf: PByte;
                             buf_size, align: Integer): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_fill_audio_frame';

(**
 * Reset the internal codec state / flush internal buffers. Should be called
 * e.g. when seeking or when switching to a different stream.
 *
 * @note for decoders, this function just releases any references the decoder
 * might keep internally, but the caller's references remain valid.
 *
 * @note for encoders, this function will only do something if the encoder
 * declares support for AV_CODEC_CAP_ENCODER_FLUSH. When called, the encoder
 * will drain any remaining packets, and can then be re-used for a different
 * stream (as opposed to sending a null frame which will leave the encoder
 * in a permanent EOF state after draining). This can be desirable if the
 * cost of tearing down and replacing the encoder instance is high.
 *)
procedure avcodec_flush_buffers(avctx: PAVCodecContext); cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_flush_buffers';

(**
 * Return audio frame duration.
 *
 * @param avctx        codec context
 * @param frame_bytes  size of the frame, or 0 if unknown
 * @return             frame duration, in samples, if known. 0 if not able to
 *                     determine.
 *)
function av_get_audio_frame_duration(avctx: PAVCodecContext; frame_bytes: Integer): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'av_get_audio_frame_duration';

(* memory *)

(**
 * Same behaviour av_fast_malloc but the buffer has additional
 * AV_INPUT_BUFFER_PADDING_SIZE at the end which will always be 0.
 *
 * In addition the whole buffer will initially and after resizes
 * be 0-initialized so that no uninitialized data will ever appear.
 *)
procedure av_fast_padded_malloc(ptr: Pointer; size: PCardinal; min_size: Size_t); cdecl; external AVCODEC_LIBNAME name _PU + 'av_fast_padded_malloc';

(**
 * Same behaviour av_fast_padded_malloc except that buffer will always
 * be 0-initialized after call.
 *)
procedure av_fast_padded_mallocz(ptr: Pointer; size: PCardinal; min_size: Size_t); cdecl; external AVCODEC_LIBNAME name _PU + 'av_fast_padded_mallocz';

(**
 * @return a positive value if s is open (i.e. avcodec_open2() was called on it
 * with no corresponding avcodec_close()), 0 otherwise.
 *)
function avcodec_is_open(s: PAVCodecContext): Integer; cdecl; external AVCODEC_LIBNAME name _PU + 'avcodec_is_open';

(**
 * @}
 *)

implementation

end.
