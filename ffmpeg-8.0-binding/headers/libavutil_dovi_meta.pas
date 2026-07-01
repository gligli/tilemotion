(*
 * Copyright (c) 2020 Vacing Fang <vacingfang@tencent.com>
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
 * DOVI configuration
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/dovi_meta.h
 * Ported by CodeCoolie@CNSW 2023/11/28 -> $Date:: 2025-01-17 #$
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

unit libavutil_dovi_meta;

interface

{$I CompilerDefines.inc}

uses
  libavutil_rational,
  FFTypes;

{$I libversion.inc}

const
  AV_DOVI_MAX_PIECES = 8;
  AV_DOVI_MAX_EXT_BLOCKS = 32;

(*
 * DOVI configuration
 * ref: dolby-vision-bitstreams-within-the-iso-base-media-file-format-v2.1.2
        dolby-vision-bitstreams-in-mpeg-2-transport-stream-multiplex-v1.2
 * @code
 * uint8_t  dv_version_major, the major version number that the stream complies with
 * uint8_t  dv_version_minor, the minor version number that the stream complies with
 * uint8_t  dv_profile, the Dolby Vision profile
 * uint8_t  dv_level, the Dolby Vision level
 * uint8_t  rpu_present_flag
 * uint8_t  el_present_flag
 * uint8_t  bl_present_flag
 * uint8_t  dv_bl_signal_compatibility_id
 * uint8_t  dv_md_compression, the compression method in use
 * @endcode
 *
 * @note The struct must be allocated with av_dovi_alloc() and
 *       its size is not a part of the public ABI.
 *)
type
  PAVDOVIDecoderConfigurationRecord = ^TAVDOVIDecoderConfigurationRecord;
  TAVDOVIDecoderConfigurationRecord = record
    dv_version_major: Byte;
    dv_version_minor: Byte;
    dv_profile: Byte;
    dv_level: Byte;
    rpu_present_flag: Byte;
    el_present_flag: Byte;
    bl_present_flag: Byte;
    dv_bl_signal_compatibility_id: Byte;
    dv_md_compression: Byte;
  end;

  TAVDOVICompression = (
    AV_DOVI_COMPRESSION_NONE     = 0,
    AV_DOVI_COMPRESSION_LIMITED  = 1,
    AV_DOVI_COMPRESSION_RESERVED = 2,
    AV_DOVI_COMPRESSION_EXTENDED = 3
  );

(**
 * Allocate a AVDOVIDecoderConfigurationRecord structure and initialize its
 * fields to default values.
 *
 * @return the newly allocated struct or NULL on failure
 *)
function av_dovi_alloc(size: PSize_t): PAVDOVIDecoderConfigurationRecord; cdecl; external AVUTIL_LIBNAME name _PU + 'av_dovi_alloc';

(**
 * Dolby Vision RPU data header.
 *
 * @note sizeof(AVDOVIRpuDataHeader) is not part of the public ABI.
 *)
type
  PAVDOVIRpuDataHeader = ^TAVDOVIRpuDataHeader;
  TAVDOVIRpuDataHeader = record
    rpu_type: Byte;
    rpu_format: Word;
    vdr_rpu_profile: Byte;
    vdr_rpu_level: Byte;
    chroma_resampling_explicit_filter_flag: Byte;
    coef_data_type: Byte; (* informative, lavc always converts to fixed *)
    coef_log2_denom: Byte;
    vdr_rpu_normalized_idc: Byte;
    bl_video_full_range_flag: Byte;
    bl_bit_depth: Byte; (* [8, 16] *)
    el_bit_depth: Byte; (* [8, 16] *)
    vdr_bit_depth: Byte; (* [8, 16] *)
    spatial_resampling_filter_flag: Byte;
    el_spatial_resampling_filter_flag: Byte;
    disable_residual_flag: Byte;
    ext_mapping_idc_0_4: Byte; (* extended base layer inverse mapping indicator *)
    ext_mapping_idc_5_7: Byte; (* reserved *)
  end;

  TAVDOVIMappingMethod = (
    AV_DOVI_MAPPING_POLYNOMIAL = 0,
    AV_DOVI_MAPPING_MMR = 1
  );

(**
 * Coefficients of a piece-wise function. The pieces of the function span the
 * value ranges between two adjacent pivot values.
 *)
  TAVDOVIReshapingCurve = record
    num_pivots: Byte;                         (* [2, 9] *)
    pivots: array[0..AV_DOVI_MAX_PIECES] of Word;    (* sorted ascending *)
    mapping_idc: array[0..AV_DOVI_MAX_PIECES - 1] of TAVDOVIMappingMethod;
    (* AV_DOVI_MAPPING_POLYNOMIAL *)
    poly_order: array[0..AV_DOVI_MAX_PIECES - 1] of Byte;     (* [1, 2] *)
    poly_coef: array[0..AV_DOVI_MAX_PIECES - 1, 0..2] of Int64;   (* x^0, x^1, x^2 *)
    (* AV_DOVI_MAPPING_MMR *)
    mmr_order: array[0..AV_DOVI_MAX_PIECES - 1] of Byte;      (* [1, 3] *)
    mmr_constant: array[0..AV_DOVI_MAX_PIECES - 1] of Int64;
    mmr_coef: array[0..AV_DOVI_MAX_PIECES - 1, 0..2(* order - 1 *), 0..6] of Int64;
  end;

  TAVDOVINLQMethod = (
    AV_DOVI_NLQ_NONE = -1,
    AV_DOVI_NLQ_LINEAR_DZ = 0
  );

(**
 * Coefficients of the non-linear inverse quantization. For the interpretation
 * of these, see ETSI GS CCM 001.
 *)
  TAVDOVINLQParams = record
    nlq_offset: Word;
    vdr_in_max: UInt64;
    (* AV_DOVI_NLQ_LINEAR_DZ *)
    linear_deadzone_slope: UInt64;
    linear_deadzone_threshold: UInt64;
  end;

(**
 * Dolby Vision RPU data mapping parameters.
 *
 * @note sizeof(AVDOVIDataMapping) is not part of the public ABI.
 *)
  PAVDOVIDataMapping = ^TAVDOVIDataMapping;
  TAVDOVIDataMapping = record
    vdr_rpu_id: Byte;
    mapping_color_space: Byte;
    mapping_chroma_format_idc: Byte;
    curves: array[0..2] of TAVDOVIReshapingCurve; (* per component *)

    (* Non-linear inverse quantization *)
    nlq_method_idc: TAVDOVINLQMethod;
    num_x_partitions: Cardinal;
    num_y_partitions: Cardinal;
    nlq: array[0..2] of TAVDOVINLQParams; (* per component *)
    nlq_pivots: array[0..1] of Word;
  end;

(**
 * Dolby Vision RPU colorspace metadata parameters.
 *
 * @note sizeof(AVDOVIColorMetadata) is not part of the public ABI.
 *)
  PAVDOVIColorMetadata = ^TAVDOVIColorMetadata;
  TAVDOVIColorMetadata = record
    dm_metadata_id: Byte;
    scene_refresh_flag: Byte;

    (**
     * Coefficients of the custom Dolby Vision IPT-PQ matrices. These are to be
     * used instead of the matrices indicated by the frame's colorspace tags.
     * The output of rgb_to_lms_matrix is to be fed into a BT.2020 LMS->RGB
     * matrix based on a Hunt-Pointer-Estevez transform, but without any
     * crosstalk. (See the definition of the ICtCp colorspace for more
     * information.)
     *)
    ycc_to_rgb_matrix: array[0..8] of TAVRational; (* before PQ linearization *)
    ycc_to_rgb_offset: array[0..2] of TAVRational; (* input offset of neutral value *)
    rgb_to_lms_matrix: array[0..8] of TAVRational; (* after PQ linearization *)

    (**
     * Extra signal metadata (see Dolby patents for more info).
     *)
    signal_eotf: Word;
    signal_eotf_param0: Word;
    signal_eotf_param1: Word;
    signal_eotf_param2: Cardinal;
    signal_bit_depth: Byte;
    signal_color_space: Byte;
    signal_chroma_format: Byte;
    signal_full_range_flag: Byte; (* [0, 3] *)
    source_min_pq: Word;
    source_max_pq: Word;
    source_diagonal: Word;
  end;

  TAVColorPrimariesDesc = record
    // need {$ALIGN 8}
    // defined in libavutil/csp.h
  end;

  TAVDOVIDmLevel1 = record
    (* Per-frame brightness metadata *)
    min_pq: Word;
    max_pq: Word;
    avg_pq: Word;
  end;

  TAVDOVIDmLevel2 = record
    (* Usually derived from level 8 (at different levels) *)
    target_max_pq: Word;
    trim_slope: Word;
    trim_offset: Word;
    trim_power: Word;
    trim_chroma_weight: Word;
    trim_saturation_gain: Word;
    ms_weight: SmallInt;
  end;

  TAVDOVIDmLevel3 = record
    min_pq_offset: Word;
    max_pq_offset: Word;
    avg_pq_offset: Word;
  end;

  TAVDOVIDmLevel4 = record
    anchor_pq: Word;
    anchor_power: Word;
  end;

  TAVDOVIDmLevel5 = record
    (* Active area definition *)
    left_offset: Word;
    right_offset: Word;
    top_offset: Word;
    bottom_offset: Word;
  end;

  TAVDOVIDmLevel6 = record
    (* Static HDR10 metadata *)
    max_luminance: Word;
    min_luminance: Word;
    max_cll: Word;
    max_fall: Word;
  end;

  TAVDOVIDmLevel8 = record
    (* Extended version of level 2 *)
    target_display_index: Byte;
    trim_slope: Word;
    trim_offset: Word;
    trim_power: Word;
    trim_chroma_weight: Word;
    trim_saturation_gain: Word;
    ms_weight: Word;
    target_mid_contrast: Word;
    clip_trim: Word;
    saturation_vector_field: array[0..5] of Byte;
    hue_vector_field: array[0..5] of Byte;
  end;

  TAVDOVIDmLevel9 = record
    (* Source display characteristics *)
    source_primary_index: Byte;
    source_display_primaries: TAVColorPrimariesDesc;
  end;

  TAVDOVIDmLevel10 = record
    (* Target display characteristics *)
    target_display_index: Byte;
    target_max_pq: Word;
    target_min_pq: Word;
    target_primary_index: Byte;
    target_display_primaries: TAVColorPrimariesDesc;
  end;

  TAVDOVIDmLevel11 = record
    content_type: Byte;
    whitepoint: Byte;
    reference_mode_flag: Byte;
    sharpness: Byte;
    noise_reduction: Byte;
    mpeg_noise_reduction: Byte;
    frame_rate_conversion: Byte;
    brightness: Byte;
    color: Byte;
  end;

  TAVDOVIDmLevel254 = record
    (* DMv2 info block, always present in samples with DMv2 metadata *)
    dm_mode: Byte;
    dm_version_index: Byte;
  end;

  TAVDOVIDmLevel255 = record
    (* Debug block, not really used in samples *)
    dm_run_mode: Byte;
    dm_run_version: Byte;
    dm_debug: array[0..3] of Byte;
  end;

(**
 * Dolby Vision metadata extension block. Dynamic extension blocks may change
 * from frame to frame, while static blocks are constant throughout the entire
 * sequence.
 *
 * @note sizeof(AVDOVIDmData) is not part of the public API.
 *)
  TAVDOVIDmUnion = record
    case Integer of
      0: (l1: TAVDOVIDmLevel1; ); (* dynamic *)
      1: (l2: TAVDOVIDmLevel2; ); (* dynamic, may appear multiple times *)
      2: (l3: TAVDOVIDmLevel3; ); (* dynamic *)
      3: (l4: TAVDOVIDmLevel4; ); (* dynamic *)
      4: (l5: TAVDOVIDmLevel5; ); (* dynamic *)
      5: (l6: TAVDOVIDmLevel6; ); (* static *)
      //6: ((* level 7 is currently unused *)
      6: (l8: TAVDOVIDmLevel8; ); (* dynamic, may appear multiple times *)
      7: (l9: TAVDOVIDmLevel9; ); (* dynamic *)
      8: (l10: TAVDOVIDmLevel10; ); (* static, may appear multiple times *)
      9: (l11: TAVDOVIDmLevel11; ); (* dynamic *)
      10: (l254: TAVDOVIDmLevel254; ); (* static *)
      11: (l255: TAVDOVIDmLevel255; ); (* static *)
  end;
  PAVDOVIDmData = ^TAVDOVIDmData;
  TAVDOVIDmData = record
    level: Byte; (* [1, 255] *)
    levels: TAVDOVIDmUnion;
  end;

(**
 * Combined struct representing a combination of header, mapping and color
 * metadata, for attaching to frames as side data.
 *
 * @note The struct must be allocated with av_dovi_metadata_alloc() and
 *       its size is not a part of the public ABI.
 *)
  PAVDOVIMetadata = ^TAVDOVIMetadata;
  TAVDOVIMetadata = record
    (**
     * Offset in bytes from the beginning of this structure at which the
     * respective structs start.
     *)
    header_offset: Size_t;   (* AVDOVIRpuDataHeader *)
    mapping_offset: Size_t;  (* AVDOVIDataMapping *)
    color_offset: Size_t;    (* AVDOVIColorMetadata *)

    ext_block_offset: Size_t; (* offset to start of ext blocks array *)
    ext_block_size: Size_t; (* size per element *)
    num_ext_blocks: Integer; (* number of extension blocks *)

    (* static limit on num_ext_blocks, derived from bitstream limitations *)
//#define AV_DOVI_MAX_EXT_BLOCKS 32
  end;

(**
 * Find an extension block with a given level, or NULL. In the case of
 * multiple extension blocks, only the first is returned.
 *)
function av_dovi_find_level(const data: PAVDOVIMetadata; level: Byte): PAVDOVIDmData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_dovi_find_level';

(**
 * Allocate an AVDOVIMetadata structure and initialize its
 * fields to default values.
 *
 * @param size If this parameter is non-NULL, the size in bytes of the
 *             allocated struct will be written here on success
 *
 * @return the newly allocated struct or NULL on failure
 *)
function av_dovi_metadata_alloc(size: PSize_t): PAVDOVIMetadata; cdecl; external AVUTIL_LIBNAME name _PU + 'av_dovi_metadata_alloc';

function av_dovi_get_header(const data: PAVDOVIMetadata): PAVDOVIRpuDataHeader; {$IFDEF USE_INLINE}inline;{$ENDIF}
function av_dovi_get_mapping(const data: PAVDOVIMetadata): PAVDOVIDataMapping; {$IFDEF USE_INLINE}inline;{$ENDIF}
function av_dovi_get_color(const data: PAVDOVIMetadata): PAVDOVIColorMetadata; {$IFDEF USE_INLINE}inline;{$ENDIF}
function av_dovi_get_ext(const data: PAVDOVIMetadata; index: Integer): PAVDOVIDmData; {$IFDEF USE_INLINE}inline;{$ENDIF}

implementation

function av_dovi_get_header(const data: PAVDOVIMetadata): PAVDOVIRpuDataHeader;
var
  P: PByte;
begin
  P := PByte(data);
  Inc(P, data.header_offset);
  Result := PAVDOVIRpuDataHeader(P);
end;

function av_dovi_get_mapping(const data: PAVDOVIMetadata): PAVDOVIDataMapping;
var
  P: PByte;
begin
  P := PByte(data);
  Inc(P, data.mapping_offset);
  Result := PAVDOVIDataMapping(P);
end;

function av_dovi_get_color(const data: PAVDOVIMetadata): PAVDOVIColorMetadata;
var
  P: PByte;
begin
  P := PByte(data);
  Inc(P, data.color_offset);
  Result := PAVDOVIColorMetadata(P);
end;

function av_dovi_get_ext(const data: PAVDOVIMetadata; index: Integer): PAVDOVIDmData;
begin
  Result := PAVDOVIDmData(PAnsiChar(data) + data.ext_block_offset +
                          data.ext_block_size * Size_t(index));
end;

end.
