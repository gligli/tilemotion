(*
 * Copyright (c) 2006 Smartjog S.A.S, Baptiste Coudurier <baptiste.coudurier@gmail.com>
 * Copyright (c) 2011-2012 Smartjog S.A.S, Clément Bœsch <clement.boesch@smartjog.com>
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
 * Timecode helpers header
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/timecode.h
 * Ported by CodeCoolie@CNSW 2023/11/28 -> $Date:: 2024-07-28 #$
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

unit libavutil_timecode;

interface

{$I CompilerDefines.inc}

uses
  libavutil_rational;

{$I libversion.inc}

const
  AV_TIMECODE_STR_SIZE = 23;

type
  TAVTimecodeFlag = (
    AV_TIMECODE_FLAG_DROPFRAME      = 1 shl 0, ///< timecode is drop frame
    AV_TIMECODE_FLAG_24HOURSMAX     = 1 shl 1, ///< timecode wraps after 24 hours
    AV_TIMECODE_FLAG_ALLOWNEGATIVE  = 1 shl 2  ///< negative time values are allowed
  );

  PAVTimecode = ^TAVTimecode;
  TAVTimecode = record
    start: Integer;         ///< timecode frame start (first base frame number)
    flags: Cardinal;        ///< flags such as drop frame, +24 hours support, ...
    rate: TAVRational;      ///< frame rate in rational form
    fps: Cardinal;          ///< frame per second; must be consistent with the rate field
  end;

(**
 * Adjust frame number for NTSC drop frame time code.
 *
 * @param framenum frame number to adjust
 * @param fps      frame per second, multiples of 30
 * @return         adjusted frame number
 * @warning        adjustment is only valid for multiples of NTSC 29.97
 *)
function av_timecode_adjust_ntsc_framenum2(framenum, fps: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_adjust_ntsc_framenum2';

(**
 * Convert frame number to SMPTE 12M binary representation.
 *
 * @param tc       timecode data correctly initialized
 * @param framenum frame number
 * @return         the SMPTE binary representation
 *
 * See SMPTE ST 314M-2005 Sec 4.4.2.2.1 "Time code pack (TC)"
 * the format description as follows:
 * bits 0-5:   hours, in BCD(6bits)
 * bits 6:     BGF1
 * bits 7:     BGF2 (NTSC) or FIELD (PAL)
 * bits 8-14:  minutes, in BCD(7bits)
 * bits 15:    BGF0 (NTSC) or BGF2 (PAL)
 * bits 16-22: seconds, in BCD(7bits)
 * bits 23:    FIELD (NTSC) or BGF0 (PAL)
 * bits 24-29: frames, in BCD(6bits)
 * bits 30:    drop  frame flag (0: non drop,    1: drop)
 * bits 31:    color frame flag (0: unsync mode, 1: sync mode)
 * @note BCD numbers (6 or 7 bits): 4 or 5 lower bits for units, 2 higher bits for tens.
 * @note Frame number adjustment is automatically done in case of drop timecode,
 *       you do NOT have to call av_timecode_adjust_ntsc_framenum2().
 * @note The frame number is relative to tc->start.
 * @note Color frame (CF) and binary group flags (BGF) bits are set to zero.
 *)
function av_timecode_get_smpte_from_framenum(const tc: PAVTimecode; framenum: Integer): Cardinal; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_get_smpte_from_framenum';

(**
 * Convert sei info to SMPTE 12M binary representation.
 *
 * @param rate     frame rate in rational form
 * @param drop     drop flag
 * @param hh       hour
 * @param mm       minute
 * @param ss       second
 * @param ff       frame number
 * @return         the SMPTE binary representation
 *)
function av_timecode_get_smpte(rate: PAVRational; drop, hh, mm, ss, ff: Integer): Cardinal; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_get_smpte';

(**
 * Load timecode string in buf.
 *
 * @param tc       timecode data correctly initialized
 * @param buf      destination buffer, must be at least AV_TIMECODE_STR_SIZE long
 * @param framenum frame number
 * @return         the buf parameter
 *
 * @note Timecode representation can be a negative timecode and have more than
 *       24 hours, but will only be honored if the flags are correctly set.
 * @note The frame number is relative to tc->start.
 *)
function av_timecode_make_string(const tc: PAVTimecode; buf: PAnsiChar; framenum: Integer): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_make_string';

(**
 * Get the timecode string from the SMPTE timecode format.
 *
 * In contrast to av_timecode_make_smpte_tc_string this function supports 50/60
 * fps timecodes by using the field bit.
 *
 * @param buf        destination buffer, must be at least AV_TIMECODE_STR_SIZE long
 * @param rate       frame rate of the timecode
 * @param tcsmpte    the 32-bit SMPTE timecode
 * @param prevent_df prevent the use of a drop flag when it is known the DF bit
 *                   is arbitrary
 * @param skip_field prevent the use of a field flag when it is known the field
 *                   bit is arbitrary (e.g. because it is used as PC flag)
 * @return           the buf parameter
 *)
function av_timecode_make_smpte_tc_string2(buf: PAnsiChar; rate: TAVRational; tcsmpte: Cardinal; prevent_df, skip_field: Integer): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_make_smpte_tc_string2';

(**
 * Get the timecode string from the SMPTE timecode format.
 *
 * @param buf        destination buffer, must be at least AV_TIMECODE_STR_SIZE long
 * @param tcsmpte    the 32-bit SMPTE timecode
 * @param prevent_df prevent the use of a drop flag when it is known the DF bit
 *                   is arbitrary
 * @return           the buf parameter
 *)
function av_timecode_make_smpte_tc_string(buf: PAnsiChar; tcsmpte: Cardinal; prevent_df: Integer): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_make_smpte_tc_string';

(**
 * Get the timecode string from the 25-bit timecode format (MPEG GOP format).
 *
 * @param buf     destination buffer, must be at least AV_TIMECODE_STR_SIZE long
 * @param tc25bit the 25-bits timecode
 * @return        the buf parameter
 *)
function av_timecode_make_mpeg_tc_string(buf: PAnsiChar; tc25bit: Cardinal): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_make_mpeg_tc_string';

(**
 * Init a timecode struct with the passed parameters.
 *
 * @param tc          pointer to an allocated AVTimecode
 * @param rate        frame rate in rational form
 * @param flags       miscellaneous flags such as drop frame, +24 hours, ...
 *                    (see AVTimecodeFlag)
 * @param frame_start the first frame number
 * @param log_ctx     a pointer to an arbitrary struct of which the first field
 *                    is a pointer to an AVClass struct (used for av_log)
 * @return            0 on success, AVERROR otherwise
 *)
function av_timecode_init(tc: PAVTimecode; rate: TAVRational; flags, frame_start: Integer; log_ctx: Pointer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_init';

(**
 * Init a timecode struct from the passed timecode components.
 *
 * @param tc          pointer to an allocated AVTimecode
 * @param rate        frame rate in rational form
 * @param flags       miscellaneous flags such as drop frame, +24 hours, ...
 *                    (see AVTimecodeFlag)
 * @param hh          hours
 * @param mm          minutes
 * @param ss          seconds
 * @param ff          frames
 * @param log_ctx     a pointer to an arbitrary struct of which the first field
 *                    is a pointer to an AVClass struct (used for av_log)
 * @return            0 on success, AVERROR otherwise
 *)
function av_timecode_init_from_components(tc: PAVTimecode; rate: TAVRational; flags, hh, mm, ss, ff: Integer; log_ctx: Pointer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_init_from_components';

(**
 * Parse timecode representation (hh:mm:ss[:;.]ff).
 *
 * @param tc      pointer to an allocated AVTimecode
 * @param rate    frame rate in rational form
 * @param str     timecode string which will determine the frame start
 * @param log_ctx a pointer to an arbitrary struct of which the first field is a
 *                pointer to an AVClass struct (used for av_log).
 * @return        0 on success, AVERROR otherwise
 *)
function av_timecode_init_from_string(tc: PAVTimecode; rate: TAVRational; const str: PAnsiChar; log_ctx: Pointer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_init_from_string';

(**
 * Check if the timecode feature is available for the given frame rate
 *
 * @return 0 if supported, <0 otherwise
 *)
function av_timecode_check_frame_rate(rate: TAVRational): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_timecode_check_frame_rate';

implementation

end.
