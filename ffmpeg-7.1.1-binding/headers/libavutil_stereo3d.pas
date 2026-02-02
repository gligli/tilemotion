(*
 * Copyright (c) 2013 Vittorio Giovara <vittorio.giovara@gmail.com>
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
 * @ingroup lavu_video_stereo3d
 * Stereoscopic video
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/stereo3d.h
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

unit libavutil_stereo3d;

interface

{$I CompilerDefines.inc}

uses
  libavutil_frame,
  libavutil_rational,
  FFTypes;

{$I libversion.inc}

(**
 * @defgroup lavu_video_stereo3d Stereo3D types and functions
 * @ingroup lavu_video
 *
 * A stereoscopic video file consists in multiple views embedded in a single
 * frame, usually describing two views of a scene. This file describes all
 * possible codec-independent view arrangements.
 *
 * @{
 *)

(**
 * List of possible 3D Types
 *)
type
  TAVStereo3DType = (
    (**
     * Video is not stereoscopic (and metadata has to be there).
     *)
    AV_STEREO3D_2D,

    (**
     * Views are next to each other.
     *
     * @code{.unparsed}
     *    LLLLRRRR
     *    LLLLRRRR
     *    LLLLRRRR
     *    ...
     * @endcode
     *)
    AV_STEREO3D_SIDEBYSIDE,

    (**
     * Views are on top of each other.
     *
     * @code{.unparsed}
     *    LLLLLLLL
     *    LLLLLLLL
     *    RRRRRRRR
     *    RRRRRRRR
     * @endcode
     *)
    AV_STEREO3D_TOPBOTTOM,

    (**
     * Views are alternated temporally.
     *
     * @code{.unparsed}
     *     frame0   frame1   frame2   ...
     *    LLLLLLLL RRRRRRRR LLLLLLLL
     *    LLLLLLLL RRRRRRRR LLLLLLLL
     *    LLLLLLLL RRRRRRRR LLLLLLLL
     *    ...      ...      ...
     * @endcode
     *)
    AV_STEREO3D_FRAMESEQUENCE,

    (**
     * Views are packed in a checkerboard-like structure per pixel.
     *
     * @code{.unparsed}
     *    LRLRLRLR
     *    RLRLRLRL
     *    LRLRLRLR
     *    ...
     * @endcode
     *)
    AV_STEREO3D_CHECKERBOARD,

    (**
     * Views are next to each other, but when upscaling
     * apply a checkerboard pattern.
     *
     * @code{.unparsed}
     *     LLLLRRRR          L L L L    R R R R
     *     LLLLRRRR    =>     L L L L  R R R R
     *     LLLLRRRR          L L L L    R R R R
     *     LLLLRRRR           L L L L  R R R R
     * @endcode
     *)
    AV_STEREO3D_SIDEBYSIDE_QUINCUNX,

    (**
     * Views are packed per line, as if interlaced.
     *
     * @code{.unparsed}
     *    LLLLLLLL
     *    RRRRRRRR
     *    LLLLLLLL
     *    ...
     * @endcode
     *)
    AV_STEREO3D_LINES,

    (**
     * Views are packed per column.
     *
     * @code{.unparsed}
     *    LRLRLRLR
     *    LRLRLRLR
     *    LRLRLRLR
     *    ...
     * @endcode
     *)
    AV_STEREO3D_COLUMNS,

    (**
     * Video is stereoscopic but the packing is unspecified.
     *)
    AV_STEREO3D_UNSPEC
  );

(**
 * List of possible view types.
 *)
  TAVStereo3DView = (
    (**
     * Frame contains two packed views.
     *)
    AV_STEREO3D_VIEW_PACKED,

    (**
     * Frame contains only the left view.
     *)
    AV_STEREO3D_VIEW_LEFT,

    (**
     * Frame contains only the right view.
     *)
    AV_STEREO3D_VIEW_RIGHT,

    (**
     * Content is unspecified.
     *)
    AV_STEREO3D_VIEW_UNSPEC
  );

(**
 * List of possible primary eyes.
 *)
  TAVStereo3DPrimaryEye = (
    (**
     * Neither eye.
     *)
    AV_PRIMARY_EYE_NONE,

    (**
     * Left eye.
     *)
    AV_PRIMARY_EYE_LEFT,

    (**
     * Right eye
     *)
    AV_PRIMARY_EYE_RIGHT
  );

(**
 * Inverted views, Right/Bottom represents the left view.
 *)
const
  AV_STEREO3D_FLAG_INVERT    = (1 shl 0);

(**
 * Stereo 3D type: this structure describes how two videos are packed
 * within a single video surface, with additional information as needed.
 *
 * @note The struct must be allocated with av_stereo3d_alloc() and
 *       its size is not a part of the public ABI.
 *)
type
  PAVStereo3D = ^TAVStereo3D;
  TAVStereo3D = record
    (**
     * How views are packed within the video.
     *)
    type_: TAVStereo3DType;

    (**
     * Additional information about the frame packing.
     *)
    flags: Integer;

    (**
     * Determines which views are packed.
     *)
    view: TAVStereo3DView;

    (**
     * Which eye is the primary eye when rendering in 2D.
     *)
    primary_eye: TAVStereo3DPrimaryEye;

    (**
     * The distance between the centres of the lenses of the camera system,
     * in micrometers. Zero if unset.
     *)
    baseline: Cardinal;

    (**
     * Relative shift of the left and right images, which changes the zero parallax plane.
     * Range is -1.0 to 1.0. Zero if unset.
     *)
    horizontal_disparity_adjustment: TAVRational;

    (**
     * Horizontal field of view, in degrees. Zero if unset.
     *)
    horizontal_field_of_view: TAVRational;
  end;

(**
 * Allocate an AVStereo3D structure and set its fields to default values.
 * The resulting struct can be freed using av_freep().
 *
 * @return An AVStereo3D filled with default values or NULL on failure.
 *)
function av_stereo3d_alloc: PAVStereo3D; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_alloc';

(**
 * Allocate an AVStereo3D structure and set its fields to default values.
 * The resulting struct can be freed using av_freep().
 *
 * @return An AVStereo3D filled with default values or NULL on failure.
 *)
function av_stereo3d_alloc_size(size: PSize_t): PAVStereo3D; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_alloc_size';

(**
 * Allocate a complete AVFrameSideData and add it to the frame.
 *
 * @param frame The frame which side data is added to.
 *
 * @return The AVStereo3D structure to be filled by caller.
 *)
function av_stereo3d_create_side_data(frame: PAVFrame): PAVStereo3D; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_create_side_data';

(**
 * Provide a human-readable name of a given stereo3d type.
 *
 * @param type The input stereo3d type value.
 *
 * @return The name of the stereo3d value, or "unknown".
 *)
function av_stereo3d_type_name(type_: Cardinal): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_type_name';

(**
 * Get the AVStereo3DType form a human-readable name.
 *
 * @param name The input string.
 *
 * @return The AVStereo3DType value, or -1 if not found.
 *)
function av_stereo3d_from_name(const name: PAnsiChar): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_from_name';

(**
 * Provide a human-readable name of a given stereo3d view.
 *
 * @param type The input stereo3d view value.
 *
 * @return The name of the stereo3d view value, or "unknown".
 *)
function av_stereo3d_view_name(view: Cardinal): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_view_name';

(**
 * Get the AVStereo3DView form a human-readable name.
 *
 * @param name The input string.
 *
 * @return The AVStereo3DView value, or -1 if not found.
 *)
function av_stereo3d_view_from_name(const name: PAnsiChar): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_view_from_name';

(**
 * Provide a human-readable name of a given stereo3d primary eye.
 *
 * @param type The input stereo3d primary eye value.
 *
 * @return The name of the stereo3d primary eye value, or "unknown".
 *)
function av_stereo3d_primary_eye_name(eye: Cardinal): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_primary_eye_name';

(**
 * Get the AVStereo3DPrimaryEye form a human-readable name.
 *
 * @param name The input string.
 *
 * @return The AVStereo3DPrimaryEye value, or -1 if not found.
 *)
function av_stereo3d_primary_eye_from_name(const name: PAnsiChar): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_stereo3d_primary_eye_from_name';

(**
 * @}
 *)

implementation

end.
