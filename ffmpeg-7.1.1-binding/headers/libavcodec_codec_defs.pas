(*
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

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavcodec/defs.h
 * Ported by CodeCoolie@CNSW 2022/02/09 -> $Date:: 2024-01-27 #$
 *)

(*
FFmpeg Delphi/Pascal Headers and Examples License Agreement

A modified part of FFVCL - Delphi FFmpeg VCL Components.
Copyright (c) 2008-2024 DelphiFFmpeg.com
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

unit libavcodec_codec_defs;

interface

{$I CompilerDefines.inc}

uses
  FFTypes;

{$I libversion.inc}

(**
 * @file
 * @ingroup libavc
 * Misc types and constants that do not belong anywhere else.
 *)

(**
 * @ingroup lavc_decoding
 * Required number of additionally allocated bytes at the end of the input bitstream for decoding.
 * This is mainly needed because some optimized bitstream readers read
 * 32 or 64 bit at once and could read over the end.<br>
 * Note: If the first 23 bits of the additional bytes are not 0, then damaged
 * MPEG bitstreams could cause overread and segfault.
 *)
const
  AV_INPUT_BUFFER_PADDING_SIZE = 64;

(**
 * Verify checksums embedded in the bitstream (could be of either encoded or
 * decoded data, depending on the format) and print an error message on mismatch.
 * If AV_EF_EXPLODE is also set, a mismatching checksum will result in the
 * decoder/demuxer returning an error.
 *)
  AV_EF_CRCCHECK      = (1 shl 0);
  AV_EF_BITSTREAM     = (1 shl 1);  ///< detect bitstream specification deviations
  AV_EF_BUFFER        = (1 shl 2);  ///< detect improper bitstream length
  AV_EF_EXPLODE       = (1 shl 3);  ///< abort decoding on minor error detection

  AV_EF_IGNORE_ERR    = (1 shl 15); ///< ignore errors and continue
  AV_EF_CAREFUL       = (1 shl 16); ///< consider things that violate the spec, are fast to calculate and have not been seen in the wild as errors
  AV_EF_COMPLIANT     = (1 shl 17); ///< consider all spec non compliances as errors
  AV_EF_AGGRESSIVE    = (1 shl 18); ///< consider things that a sane encoder/muxer should not do as an error

  FF_COMPLIANCE_VERY_STRICT   =  2; ///< Strictly conform to an older more strict version of the spec or reference software.
  FF_COMPLIANCE_STRICT        =  1; ///< Strictly conform to all the things in the spec no matter what consequences.
  FF_COMPLIANCE_NORMAL        =  0;
  FF_COMPLIANCE_UNOFFICIAL    = -1; ///< Allow unofficial extensions
  FF_COMPLIANCE_EXPERIMENTAL  = -2; ///< Allow nonstandardized experimental things.


  AV_PROFILE_UNKNOWN       =  -99;
  AV_PROFILE_RESERVED      = -100;

  AV_PROFILE_AAC_MAIN      =   0;
  AV_PROFILE_AAC_LOW       =   1;
  AV_PROFILE_AAC_SSR       =   2;
  AV_PROFILE_AAC_LTP       =   3;
  AV_PROFILE_AAC_HE        =   4;
  AV_PROFILE_AAC_HE_V2     =  28;
  AV_PROFILE_AAC_LD        =  22;
  AV_PROFILE_AAC_ELD       =  38;
  AV_PROFILE_MPEG2_AAC_LOW = 128;
  AV_PROFILE_MPEG2_AAC_HE  = 131;

  AV_PROFILE_DNXHD         = 0;
  AV_PROFILE_DNXHR_LB      = 1;
  AV_PROFILE_DNXHR_SQ      = 2;
  AV_PROFILE_DNXHR_HQ      = 3;
  AV_PROFILE_DNXHR_HQX     = 4;
  AV_PROFILE_DNXHR_444     = 5;

  AV_PROFILE_DTS                = 20;
  AV_PROFILE_DTS_ES             = 30;
  AV_PROFILE_DTS_96_24          = 40;
  AV_PROFILE_DTS_HD_HRA         = 50;
  AV_PROFILE_DTS_HD_MA          = 60;
  AV_PROFILE_DTS_EXPRESS        = 70;
  AV_PROFILE_DTS_HD_MA_X        = 61;
  AV_PROFILE_DTS_HD_MA_X_IMAX   = 62;

  AV_PROFILE_EAC3_DDP_ATMOS     = 30;

  AV_PROFILE_TRUEHD_ATMOS       = 30;

  AV_PROFILE_MPEG2_422          = 0;
  AV_PROFILE_MPEG2_HIGH         = 1;
  AV_PROFILE_MPEG2_SS           = 2;
  AV_PROFILE_MPEG2_SNR_SCALABLE = 3;
  AV_PROFILE_MPEG2_MAIN         = 4;
  AV_PROFILE_MPEG2_SIMPLE       = 5;

  AV_PROFILE_H264_CONSTRAINED   = (1 shl 9);  // 8+1; constraint_set1_flag
  AV_PROFILE_H264_INTRA         = (1 shl 11); // 8+3; constraint_set3_flag

  AV_PROFILE_H264_BASELINE             = 66;
  AV_PROFILE_H264_CONSTRAINED_BASELINE = (66 or AV_PROFILE_H264_CONSTRAINED);
  AV_PROFILE_H264_MAIN                 = 77;
  AV_PROFILE_H264_EXTENDED             = 88;
  AV_PROFILE_H264_HIGH                 = 100;
  AV_PROFILE_H264_HIGH_10              = 110;
  AV_PROFILE_H264_HIGH_10_INTRA        = (110 or AV_PROFILE_H264_INTRA);
  AV_PROFILE_H264_MULTIVIEW_HIGH       = 118;
  AV_PROFILE_H264_HIGH_422             = 122;
  AV_PROFILE_H264_HIGH_422_INTRA       = (122 or AV_PROFILE_H264_INTRA);
  AV_PROFILE_H264_STEREO_HIGH          = 128;
  AV_PROFILE_H264_HIGH_444             = 144;
  AV_PROFILE_H264_HIGH_444_PREDICTIVE  = 244;
  AV_PROFILE_H264_HIGH_444_INTRA       = (244 or AV_PROFILE_H264_INTRA);
  AV_PROFILE_H264_CAVLC_444            = 44;

  AV_PROFILE_VC1_SIMPLE   = 0;
  AV_PROFILE_VC1_MAIN     = 1;
  AV_PROFILE_VC1_COMPLEX  = 2;
  AV_PROFILE_VC1_ADVANCED = 3;

  AV_PROFILE_MPEG4_SIMPLE                    =  0;
  AV_PROFILE_MPEG4_SIMPLE_SCALABLE           =  1;
  AV_PROFILE_MPEG4_CORE                      =  2;
  AV_PROFILE_MPEG4_MAIN                      =  3;
  AV_PROFILE_MPEG4_N_BIT                     =  4;
  AV_PROFILE_MPEG4_SCALABLE_TEXTURE          =  5;
  AV_PROFILE_MPEG4_SIMPLE_FACE_ANIMATION     =  6;
  AV_PROFILE_MPEG4_BASIC_ANIMATED_TEXTURE    =  7;
  AV_PROFILE_MPEG4_HYBRID                    =  8;
  AV_PROFILE_MPEG4_ADVANCED_REAL_TIME        =  9;
  AV_PROFILE_MPEG4_CORE_SCALABLE             = 10;
  AV_PROFILE_MPEG4_ADVANCED_CODING           = 11;
  AV_PROFILE_MPEG4_ADVANCED_CORE             = 12;
  AV_PROFILE_MPEG4_ADVANCED_SCALABLE_TEXTURE = 13;
  AV_PROFILE_MPEG4_SIMPLE_STUDIO             = 14;
  AV_PROFILE_MPEG4_ADVANCED_SIMPLE           = 15;

  AV_PROFILE_JPEG2000_CSTREAM_RESTRICTION_0  = 1;
  AV_PROFILE_JPEG2000_CSTREAM_RESTRICTION_1  = 2;
  AV_PROFILE_JPEG2000_CSTREAM_NO_RESTRICTION = 32768;
  AV_PROFILE_JPEG2000_DCINEMA_2K             = 3;
  AV_PROFILE_JPEG2000_DCINEMA_4K             = 4;

  AV_PROFILE_VP9_0                           = 0;
  AV_PROFILE_VP9_1                           = 1;
  AV_PROFILE_VP9_2                           = 2;
  AV_PROFILE_VP9_3                           = 3;

  AV_PROFILE_HEVC_MAIN                       = 1;
  AV_PROFILE_HEVC_MAIN_10                    = 2;
  AV_PROFILE_HEVC_MAIN_STILL_PICTURE         = 3;
  AV_PROFILE_HEVC_REXT                       = 4;
  AV_PROFILE_HEVC_SCC                        = 9;

  AV_PROFILE_VVC_MAIN_10                     = 1;
  AV_PROFILE_VVC_MAIN_10_444                 = 33;

  AV_PROFILE_AV1_MAIN                        = 0;
  AV_PROFILE_AV1_HIGH                        = 1;
  AV_PROFILE_AV1_PROFESSIONAL                = 2;

  AV_PROFILE_MJPEG_HUFFMAN_BASELINE_DCT            = $c0;
  AV_PROFILE_MJPEG_HUFFMAN_EXTENDED_SEQUENTIAL_DCT = $c1;
  AV_PROFILE_MJPEG_HUFFMAN_PROGRESSIVE_DCT         = $c2;
  AV_PROFILE_MJPEG_HUFFMAN_LOSSLESS                = $c3;
  AV_PROFILE_MJPEG_JPEG_LS                         = $f7;

  AV_PROFILE_SBC_MSBC                        = 1;

  AV_PROFILE_PRORES_PROXY     = 0;
  AV_PROFILE_PRORES_LT        = 1;
  AV_PROFILE_PRORES_STANDARD  = 2;
  AV_PROFILE_PRORES_HQ        = 3;
  AV_PROFILE_PRORES_4444      = 4;
  AV_PROFILE_PRORES_XQ        = 5;

  AV_PROFILE_ARIB_PROFILE_A   = 0;
  AV_PROFILE_ARIB_PROFILE_C   = 1;

  AV_PROFILE_KLVA_SYNC        = 0;
  AV_PROFILE_KLVA_ASYNC       = 1;

  AV_PROFILE_EVC_BASELINE     = 0;
  AV_PROFILE_EVC_MAIN         = 1;


  AV_LEVEL_UNKNOWN            = -99;

type
  TAVFieldOrder = (
    AV_FIELD_UNKNOWN,
    AV_FIELD_PROGRESSIVE,
    AV_FIELD_TT,          ///< Top coded_first, top displayed first
    AV_FIELD_BB,          ///< Bottom coded first, bottom displayed first
    AV_FIELD_TB,          ///< Top coded first, bottom displayed first
    AV_FIELD_BT           ///< Bottom coded first, top displayed first
  );

(**
 * @ingroup lavc_decoding
 *)
  TAVDiscard = (
    (* We leave some space between them for extensions (drop some
     * keyframes for intra-only or drop just some bidir frames). *)
    AVDISCARD_NONE    =-16, ///< discard nothing
    AVDISCARD_DEFAULT =  0, ///< discard useless packets like 0 size packets in avi
    AVDISCARD_NONREF  =  8, ///< discard all non reference
    AVDISCARD_BIDIR   = 16, ///< discard all bidirectional frames
    AVDISCARD_NONINTRA= 24, ///< discard all non intra frames
    AVDISCARD_NONKEY  = 32, ///< discard all frames except keyframes
    AVDISCARD_ALL     = 48  ///< discard all
  );

  PAVAudioServiceType = ^TAVAudioServiceType;
  TAVAudioServiceType = (
    AV_AUDIO_SERVICE_TYPE_MAIN              = 0,
    AV_AUDIO_SERVICE_TYPE_EFFECTS           = 1,
    AV_AUDIO_SERVICE_TYPE_VISUALLY_IMPAIRED = 2,
    AV_AUDIO_SERVICE_TYPE_HEARING_IMPAIRED  = 3,
    AV_AUDIO_SERVICE_TYPE_DIALOGUE          = 4,
    AV_AUDIO_SERVICE_TYPE_COMMENTARY        = 5,
    AV_AUDIO_SERVICE_TYPE_EMERGENCY         = 6,
    AV_AUDIO_SERVICE_TYPE_VOICE_OVER        = 7,
    AV_AUDIO_SERVICE_TYPE_KARAOKE           = 8,
    AV_AUDIO_SERVICE_TYPE_NB                     ///< Not part of ABI
  );

(**
 * Pan Scan area.
 * This specifies the area which should be displayed.
 * Note there may be multiple such areas for one frame.
 *)
  TAVPanScan = record
    (**
     * id
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
    id: Integer;

    (**
     * width and height in 1/16 pel
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
    width: Integer;
    height: Integer;

    (**
     * position of the top left corner in 1/16 pel for up to 3 fields/frames
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
    //int16_t position[3][2];
    position: array[0..2] of array[0..1] of SmallInt; // int16_t
  end;

(**
 * This structure describes the bitrate properties of an encoded bitstream. It
 * roughly corresponds to a subset the VBV parameters for MPEG-2 or HRD
 * parameters for H.264/HEVC.
 *)
  PAVCPBProperties = ^TAVCPBProperties;
  TAVCPBProperties = record
    (**
     * Maximum bitrate of the stream, in bits per second.
     * Zero if unknown or unspecified.
     *)
    max_bitrate: Int64;
    (**
     * Minimum bitrate of the stream, in bits per second.
     * Zero if unknown or unspecified.
     *)
    min_bitrate: Int64;
    (**
     * Average bitrate of the stream, in bits per second.
     * Zero if unknown or unspecified.
     *)
    avg_bitrate: Int64;

    (**
     * The size of the buffer to which the ratecontrol is applied, in bits.
     * Zero if unknown or unspecified.
     *)
    buffer_size: Int64;

    (**
     * The delay between the time the packet this structure is associated with
     * is received and the time when it should be decoded, in periods of a 27MHz
     * clock.
     *
     * UINT64_MAX when unknown or unspecified.
     *)
    vbv_delay: Int64;
  end;

(**
 * Allocate a CPB properties structure and initialize its fields to default
 * values.
 *
 * @param size if non-NULL, the size of the allocated struct will be written
 *             here. This is useful for embedding it in side data.
 *
 * @return the newly allocated struct or NULL on failure
 *)
function av_cpb_properties_alloc(size: Size_t): PAVCPBProperties; cdecl; external AVCODEC_LIBNAME name _PU + 'av_cpb_properties_alloc';

type
(**
 * This structure supplies correlation between a packet timestamp and a wall clock
 * production time. The definition follows the Producer Reference Time ('prft')
 * as defined in ISO/IEC 14496-12
 *)
  TAVProducerReferenceTime = record
    (**
     * A UTC timestamp, in microseconds, since Unix epoch (e.g, av_gettime()).
     *)
    wallclock: Int64;
    flags: Integer;
  end;

(**
 * Encode extradata length to a buffer. Used by xiph codecs.
 *
 * @param s buffer to write to; must be at least (v/255+1) bytes long
 * @param v size of extradata in bytes
 * @return number of bytes written to the buffer.
 *)
function av_xiphlacing(s: Byte; v: Cardinal): Cardinal; cdecl; external AVCODEC_LIBNAME name _PU + 'av_xiphlacing';

implementation

end.
