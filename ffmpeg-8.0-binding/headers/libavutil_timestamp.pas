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
 * timestamp utils, mostly useful for debugging/logging purposes
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/timestamp.h
 * Ported by CodeCoolie@CNSW 2014/07/21 -> $Date:: 2024-07-28 #$
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

unit libavutil_timestamp;

interface

{$I CompilerDefines.inc}

uses
{$IFDEF VCL_XE2_OR_ABOVE}
  System.SysUtils,
  {$IF Defined(VCL_XE4_OR_ABOVE)}
    System.AnsiStrings, // StrLen
  {$IFEND}
{$ELSE}
  SysUtils,
{$ENDIF}
  libavutil,
  libavutil_rational;

{$I libversion.inc}


const
  AV_TS_MAX_STRING_SIZE = 32;

(**
 * Fill the provided buffer with a string containing a timestamp
 * representation.
 *
 * @param buf a buffer with size in bytes of at least AV_TS_MAX_STRING_SIZE
 * @param ts the timestamp to represent
 * @return the buffer in input
 *)
function av_ts_make_string(buf: PAnsiChar; ts: Int64): PAnsiChar; {$IFDEF USE_INLINE}inline;{$ENDIF}
{
    if (ts == AV_NOPTS_VALUE) snprintf(buf, AV_TS_MAX_STRING_SIZE, "NOPTS");
    else                      snprintf(buf, AV_TS_MAX_STRING_SIZE, "%" PRId64, ts);
    return buf;
}

(**
 * Convenience macro, the return value should be used only directly in
 * function arguments but never stand-alone.
 *)
//#define av_ts2str(ts) av_ts_make_string((char[AV_TS_MAX_STRING_SIZE]){0}, ts)
function av_ts2str(ts: Int64): PAnsiChar;

(**
 * Fill the provided buffer with a string containing a timestamp time
 * representation.
 *
 * @param buf a buffer with size in bytes of at least AV_TS_MAX_STRING_SIZE
 * @param ts the timestamp to represent
 * @param tb the timebase of the timestamp
 * @return the buffer in input
 *)
function av_ts_make_time_string2(buf: PAnsiChar; ts: Int64; tb: TAVRational): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_ts_make_time_string2';

(**
 * Fill the provided buffer with a string containing a timestamp
 * representation.
 *
 * @see av_ts_make_time_string2
 *)
function av_ts_make_time_string(buf: PAnsiChar; ts: Int64; tb: PAVRational): PAnsiChar; {$IFDEF USE_INLINE}inline;{$ENDIF}
{
    return av_ts_make_time_string2(buf, ts, *tb);
}

(**
 * Convenience macro, the return value should be used only directly in
 * function arguments but never stand-alone.
 *)
//#define av_ts2timestr(ts, tb) av_ts_make_time_string((char[AV_TS_MAX_STRING_SIZE]){0}, ts, tb)
function av_ts2timestr(ts: Int64; tb: PAVRational): PAnsiChar;

function MyStrLen(const Str: PAnsiChar): Cardinal; {$IFDEF USE_INLINE}inline;{$ENDIF}

implementation


function MyStrLen(const Str: PAnsiChar): Cardinal;
begin
{$IFDEF VCL_XE4_OR_ABOVE}
  Result := System.AnsiStrings.StrLen(Str);
{$ELSE}
  Result := StrLen(Str);
{$ENDIF}
end;

function av_ts_make_string(buf: PAnsiChar; ts: Int64): PAnsiChar;
var
  s: string;
  p: PAnsiChar;
begin
  if ts = AV_NOPTS_VALUE then
    s := 'NOPTS'
  else
    s := IntToStr(ts);
  p := PAnsiChar(AnsiString(s));
  Move(p^, buf^, MyStrLen(p));
  buf[MyStrLen(p)] := #0;
  Result := buf;
end;

var
  buf: array[0..AV_TS_MAX_STRING_SIZE - 1] of AnsiChar;

function av_ts2str(ts: Int64): PAnsiChar;
begin
  Result := av_ts_make_string(@buf[0], ts);
end;

function av_ts_make_time_string(buf: PAnsiChar; ts: Int64; tb: PAVRational): PAnsiChar;
//var
//  s: string;
//  p: PAnsiChar;
begin
{
  if ts = AV_NOPTS_VALUE then
    s := 'NOPTS'
  else
    s := Format('%.6g', [av_q2d(tb^) * ts]);
  p := PAnsiChar(AnsiString(s));
  Move(p^, buf^, MyStrLen(p));
  buf[MyStrLen(p)] := #0;
  Result := buf;
}
  Result := av_ts_make_time_string2(buf, ts, tb^);
end;

function av_ts2timestr(ts: Int64; tb: PAVRational): PAnsiChar;
begin
  Result := av_ts_make_time_string(@buf[0], ts, tb);
end;

end.
