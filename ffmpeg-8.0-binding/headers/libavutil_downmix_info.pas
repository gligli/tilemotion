(*
 * Copyright (c) 2014 Tim Walker <tdskywalker@gmail.com>
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
 * audio downmix medatata
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/downmix_info.h
 * Ported by CodeCoolie@CNSW 2025/09/27 -> $Date:: 2025-11-04 #$
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

unit libavutil_downmix_info;

interface

{$I CompilerDefines.inc}

uses
  libavutil_frame;

{$I libversion.inc}

(**
 * @addtogroup lavu_audio
 * @ begin
 *)

(**
 * @defgroup downmix_info Audio downmix metadata
 * @ begin
 *)

type
(**
 * Possible downmix types.
 *)
  TAVDownmixType = (
    AV_DOWNMIX_TYPE_UNKNOWN, (**< Not indicated. *)
    AV_DOWNMIX_TYPE_LORO,    (**< Lo/Ro 2-channel downmix (Stereo). *)
    AV_DOWNMIX_TYPE_LTRT,    (**< Lt/Rt 2-channel downmix, Dolby Surround compatible. *)
    AV_DOWNMIX_TYPE_DPLII,   (**< Lt/Rt 2-channel downmix, Dolby Pro Logic II compatible. *)
    AV_DOWNMIX_TYPE_NB       (**< Number of downmix types. Not part of ABI. *)
  );

(**
 * This structure describes optional metadata relevant to a downmix procedure.
 *
 * All fields are set by the decoder to the value indicated in the audio
 * bitstream (if present), or to a "sane" default otherwise.
 *)
  PAVDownmixInfo = ^TAVDownmixInfo;
  TAVDownmixInfo = record
    (**
     * Type of downmix preferred by the mastering engineer.
     *)
    preferred_downmix_type: TAVDownmixType;

    (**
     * Absolute scale factor representing the nominal level of the center
     * channel during a regular downmix.
     *)
    center_mix_level: Double;

    (**
     * Absolute scale factor representing the nominal level of the center
     * channel during an Lt/Rt compatible downmix.
     *)
    center_mix_level_ltrt: Double;

    (**
     * Absolute scale factor representing the nominal level of the surround
     * channels during a regular downmix.
     *)
    surround_mix_level: Double;

    (**
     * Absolute scale factor representing the nominal level of the surround
     * channels during an Lt/Rt compatible downmix.
     *)
    surround_mix_level_ltrt: Double;

    (**
     * Absolute scale factor representing the level at which the LFE data is
     * mixed into L/R channels during downmixing.
     *)
    lfe_mix_level: Double;
  end;

(**
 * Get a frame's AV_FRAME_DATA_DOWNMIX_INFO side data for editing.
 *
 * If the side data is absent, it is created and added to the frame.
 *
 * @param frame the frame for which the side data is to be obtained or created
 *
 * @return the AVDownmixInfo structure to be edited by the caller, or NULL if
 *         the structure cannot be allocated.
 *)
function av_downmix_info_update_side_data(frame: PAVFrame): PAVDownmixInfo; cdecl; external AVUTIL_LIBNAME name _PU + 'av_downmix_info_update_side_data';

(**
 * @}
 *)

(**
 * @}
 *)

implementation

end.
