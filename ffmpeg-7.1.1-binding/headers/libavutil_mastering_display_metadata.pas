(*
 * Copyright (c) 2016 Neil Birkbeck <neil.birkbeck@gmail.com>
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
 * Original file: libavutil/mastering_display_metadata.h
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

unit libavutil_mastering_display_metadata;

interface

{$I CompilerDefines.inc}

uses
  libavutil_frame,
  libavutil_rational,
  FFTypes;

{$I libversion.inc}

(**
 * Mastering display metadata capable of representing the color volume of
 * the display used to master the content (SMPTE 2086:2014).
 *
 * To be used as payload of a AVFrameSideData or AVPacketSideData with the
 * appropriate type.
 *
 * @note The struct should be allocated with av_mastering_display_metadata_alloc()
 *       and its size is not a part of the public ABI.
 *)
type
  PAVMasteringDisplayMetadata = ^TAVMasteringDisplayMetadata;
  TAVMasteringDisplayMetadata = record
    (**
     * CIE 1931 xy chromaticity coords of color primaries (r, g, b order).
     *)
    display_primaries: array[0..2, 0..1] of TAVRational;

    (**
     * CIE 1931 xy chromaticity coords of white point.
     *)
    white_point: array[0..1] of TAVRational;

    (**
     * Min luminance of mastering display (cd/m^2).
     *)
    min_luminance: TAVRational;

    (**
     * Max luminance of mastering display (cd/m^2).
     *)
    max_luminance: TAVRational;

    (**
     * Flag indicating whether the display primaries (and white point) are set.
     *)
    has_primaries: Integer;

    (**
     * Flag indicating whether the luminance (min_ and max_) have been set.
     *)
    has_luminance: Integer;
  end;

(**
 * Allocate an AVMasteringDisplayMetadata structure and set its fields to
 * default values. The resulting struct can be freed using av_freep().
 *
 * @return An AVMasteringDisplayMetadata filled with default values or NULL
 *         on failure.
 *)
function av_mastering_display_metadata_alloc: PAVMasteringDisplayMetadata; cdecl; external AVUTIL_LIBNAME name _PU + 'av_mastering_display_metadata_alloc';

(**
 * Allocate an AVMasteringDisplayMetadata structure and set its fields to
 * default values. The resulting struct can be freed using av_freep().
 *
 * @return An AVMasteringDisplayMetadata filled with default values or NULL
 *         on failure.
 *)
function av_mastering_display_metadata_alloc_size(size: PSize_t): PAVMasteringDisplayMetadata; cdecl; external AVUTIL_LIBNAME name _PU + 'av_mastering_display_metadata_alloc_size';

(**
 * Allocate a complete AVMasteringDisplayMetadata and add it to the frame.
 *
 * @param frame The frame which side data is added to.
 *
 * @return The AVMasteringDisplayMetadata structure to be filled by caller.
 *)
function av_mastering_display_metadata_create_side_data(frame: PAVFrame): PAVMasteringDisplayMetadata; cdecl; external AVUTIL_LIBNAME name _PU + 'av_mastering_display_metadata_create_side_data';

(**
 * Content light level needed by to transmit HDR over HDMI (CTA-861.3).
 *
 * To be used as payload of a AVFrameSideData or AVPacketSideData with the
 * appropriate type.
 *
 * @note The struct should be allocated with av_content_light_metadata_alloc()
 *       and its size is not a part of the public ABI.
 *)
type
  PAVContentLightMetadata = ^TAVContentLightMetadata;
  TAVContentLightMetadata = record
    (**
     * Max content light level (cd/m^2).
     *)
    MaxCLL: Cardinal;

    (**
     * Max average light level per frame (cd/m^2).
     *)
    MaxFALL: Cardinal;
  end;

(**
 * Allocate an AVContentLightMetadata structure and set its fields to
 * default values. The resulting struct can be freed using av_freep().
 *
 * @return An AVContentLightMetadata filled with default values or NULL
 *         on failure.
 *)
function av_content_light_metadata_alloc(size: Size_t): PAVContentLightMetadata; cdecl; external AVUTIL_LIBNAME name _PU + 'av_content_light_metadata_alloc';

(**
 * Allocate a complete AVContentLightMetadata and add it to the frame.
 *
 * @param frame The frame which side data is added to.
 *
 * @return The AVContentLightMetadata structure to be filled by caller.
 *)
function av_content_light_metadata_create_side_data(frame: PAVFrame): PAVContentLightMetadata; cdecl; external AVUTIL_LIBNAME name _PU + 'av_content_light_metadata_create_side_data';

implementation

end.
