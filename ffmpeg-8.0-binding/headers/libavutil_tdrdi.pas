(*
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
 * @ingroup lavu_video_3d_reference_displays_info
 * Spherical video
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/tdrdi.h
 * Ported by CodeCoolie@CNSW 2025/10/26 -> $Date:: 2025-11-04 #$
 *)

(*
FFmpeg Delphi/Pascal Headers and Examples License Agreement

A modified part of FFVCL - Delphi FFmpeg VCL Components.
Copyright (c) 2008-2026 DelphiFFmpeg.com
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

unit libavutil_tdrdi;

interface

{$I CompilerDefines.inc}

uses
  FFTypes;

{$I libversion.inc}

(**
 * @defgroup lavu_video_3d_reference_displays_info 3D Reference Displays Information
 * @ingroup lavu_video
 *
 * The 3D Reference Displays Information describes information about the reference display
 * width(s) and reference viewing distance(s) as well as information about the corresponding
 * reference stereo pair(s).
 * @ begin
 *)
const
  AV_TDRDI_MAX_NUM_REF_DISPLAY = 32;

(**
 * This structure describes information about the reference display width(s) and reference
 * viewing distance(s) as well as information about the corresponding reference stereo pair(s).
 * See section G.14.3.2.3 of ITU-T H.265 for more information.
 *
 * @note The struct must be allocated with av_tdrdi_alloc() and
 *       its size is not a part of the public ABI.
 *)
type
  PAV3DReferenceDisplaysInfo = ^TAV3DReferenceDisplaysInfo;
  TAV3DReferenceDisplaysInfo = record
    (**
     * The exponent of the maximum allowable truncation error for
     * begin exponent,mantissa end _ref_display_width as given by 2<sup>(-prec_ref_display_width)</sup>.
     *)
    prec_ref_display_width: Byte;

    (**
     * A flag to indicate the presence of reference viewing distance.
     * If false, the values of prec_ref_viewing_dist, exponent_ref_viewing_distance,
     * and mantissa_ref_viewing_distance are undefined.
     *)
    ref_viewing_distance_flag: Byte;

    (**
     * The exponent of the maximum allowable truncation error for
     * begin exponent,mantissa end _ref_viewing_distance as given by 2<sup>^(-prec_ref_viewing_dist)</sup>.
     * The value of prec_ref_viewing_dist shall be in the range of 0 to 31, inclusive.
     *)
    prec_ref_viewing_dist: Byte;

    (**
     * The number of reference displays that are signalled in this struct.
     * Allowed range is 1 to 32, inclusive.
     *)
    num_ref_displays: Byte;

    (**
     * Offset in bytes from the beginning of this structure at which the array
     * of reference displays starts.
     *)
    entries_offset: Size_t;

    (**
     * Size of each entry in bytes. May not match sizeof(AV3DReferenceDisplay).
     *)
    entry_size: Size_t;
  end;

(**
 * Data structure for single deference display information.
 * It is allocated as a part of AV3DReferenceDisplaysInfo and should be retrieved with
 * av_tdrdi_get_display().
 *
 * sizeof(AV3DReferenceDisplay) is not a part of the ABI and new fields may be
 * added to it.
*)
  PAV3DReferenceDisplay = ^TAV3DReferenceDisplay;
  TAV3DReferenceDisplay = record
    (**
     * The ViewId of the left view of a stereo pair corresponding to the n-th reference display.
     *)
    left_view_id: Word;

    (**
     * The ViewId of the left view of a stereo pair corresponding to the n-th reference display.
     *)
    right_view_id: Word;

    (**
     * The exponent part of the reference display width of the n-th reference display.
     *)
    exponent_ref_display_width: Byte;

    (**
     * The mantissa part of the reference display width of the n-th reference display.
     *)
    mantissa_ref_display_width: Byte;

    (**
     * The exponent part of the reference viewing distance of the n-th reference display.
     *)
    exponent_ref_viewing_distance: Byte;

    (**
     * The mantissa part of the reference viewing distance of the n-th reference display.
     *)
    mantissa_ref_viewing_distance: Byte;

    (**
     * An array of flags to indicates that the information about additional horizontal shift of
     * the left and right views for the n-th reference display is present.
     *)
    additional_shift_present_flag: Byte;

    (**
     * The recommended additional horizontal shift for a stereo pair corresponding to the n-th
     * reference baseline and the n-th reference display.
     *)
    num_sample_shift: SmallInt;
  end;

(**
 * Allocate a AV3DReferenceDisplaysInfo structure and initialize its fields to default
 * values.
 *
 * @return the newly allocated struct or NULL on failure
 *)
function av_tdrdi_alloc(nb_displays: Cardinal; size: PSize_t): PAV3DReferenceDisplaysInfo; cdecl; external AVUTIL_LIBNAME name _PU + 'av_tdrdi_alloc';

function av_tdrdi_get_display(tdrdi: PAV3DReferenceDisplaysInfo; idx: Cardinal): PAV3DReferenceDisplay;

(**
 * @}
 *)

implementation

function av_tdrdi_get_display(tdrdi: PAV3DReferenceDisplaysInfo; idx: Cardinal): PAV3DReferenceDisplay;
begin
  Assert(idx < tdrdi.num_ref_displays);
  Result := PAV3DReferenceDisplay(PAnsiChar(tdrdi) + tdrdi.entries_offset +
                                  idx * tdrdi.entry_size);
end;

end.
