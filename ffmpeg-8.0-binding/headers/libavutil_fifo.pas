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
 * @ingroup lavu_fifo
 * A generic FIFO API
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/fifo.h
 * Ported by CodeCoolie@CNSW 2008/03/25 -> $Date:: 2024-07-28 #$
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

unit libavutil_fifo;

interface

{$I CompilerDefines.inc}

uses
  FFTypes;

{$I libversion.inc}

(**
 * @defgroup lavu_fifo AVFifo
 * @ingroup lavu_data
 *
 * @{
 * A generic FIFO API
 *)

(**
 * Automatically resize the FIFO on writes, so that the data fits. This
 * automatic resizing happens up to a limit that can be modified with
 * av_fifo_auto_grow_limit().
 *)
const
  AV_FIFO_FLAG_AUTO_GROW     = (1 shl 0);

type
  PPAVFifo = ^PAVFifo;
  PAVFifo = ^TAVFifo;
  TAVFifo = record
    // need {$ALIGN 8}
    // defined in libavutil/fifo.c
  end;

(**
 * Callback for writing or reading from a FIFO, passed to (and invoked from) the
 * av_fifo_*_cb() functions. It may be invoked multiple times from a single
 * av_fifo_*_cb() call and may process less data than the maximum size indicated
 * by nb_elems.
 *
 * @param opaque the opaque pointer provided to the av_fifo_*_cb() function
 * @param buf the buffer for reading or writing the data, depending on which
 *            av_fifo_*_cb function is called
 * @param nb_elems On entry contains the maximum number of elements that can be
 *                 read from / written into buf. On success, the callback should
 *                 update it to contain the number of elements actually written.
 *
 * @return 0 on success, a negative error code on failure (will be returned from
 *         the invoking av_fifo_*_cb() function)
 *)
  TAVFifoCB = function(opaque: Pointer; buf: Pointer; nb_elems: PSize_t): Integer; cdecl;

(**
 * Allocate and initialize an AVFifo with a given element size.
 *
 * @param elems     initial number of elements that can be stored in the FIFO
 * @param elem_size Size in bytes of a single element. Further operations on
 *                  the returned FIFO will implicitly use this element size.
 * @param flags a combination of AV_FIFO_FLAG_*
 *
 * @return newly-allocated AVFifo on success, a negative error code on failure
 *)
function av_fifo_alloc2(elems, elem_size: Size_t;
                       flags: Cardinal): PAVFifo; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_alloc2';

(**
 * @return Element size for FIFO operations. This element size is set at
 *         FIFO allocation and remains constant during its lifetime
 *)
function av_fifo_elem_size(const f: PAVFifo): Size_t; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_elem_size';

(**
 * Set the maximum size (in elements) to which the FIFO can be resized
 * automatically. Has no effect unless AV_FIFO_FLAG_AUTO_GROW is used.
 *)
procedure av_fifo_auto_grow_limit(f: PAVFifo; max_elems: Size_t); cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_auto_grow_limit';

(**
 * @return number of elements available for reading from the given FIFO.
 *)
function av_fifo_can_read(const f: PAVFifo): Size_t; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_can_read';

(**
 * @return Number of elements that can be written into the given FIFO without
 *         growing it.
 *
 *         In other words, this number of elements or less is guaranteed to fit
 *         into the FIFO. More data may be written when the
 *         AV_FIFO_FLAG_AUTO_GROW flag was specified at FIFO creation, but this
 *         may involve memory allocation, which can fail.
 *)
function av_fifo_can_write(const f: PAVFifo): Size_t; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_can_write';

(**
 * Enlarge an AVFifo.
 *
 * On success, the FIFO will be large enough to hold exactly
 * inc + av_fifo_can_read() + av_fifo_can_write()
 * elements. In case of failure, the old FIFO is kept unchanged.
 *
 * @param f AVFifo to resize
 * @param inc number of elements to allocate for, in addition to the current
 *            allocated size
 * @return a non-negative number on success, a negative error code on failure
 *)
function av_fifo_grow2(f: PAVFifo; inc: Size_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_grow2';

(**
 * Write data into a FIFO.
 *
 * In case nb_elems > av_fifo_can_write(f) and the AV_FIFO_FLAG_AUTO_GROW flag
 * was not specified at FIFO creation, nothing is written and an error
 * is returned.
 *
 * Calling function is guaranteed to succeed if nb_elems <= av_fifo_can_write(f).
 *
 * @param f the FIFO buffer
 * @param buf Data to be written. nb_elems * av_fifo_elem_size(f) bytes will be
 *            read from buf on success.
 * @param nb_elems number of elements to write into FIFO
 *
 * @return a non-negative number on success, a negative error code on failure
 *)
function av_fifo_write(f: PAVFifo; const buf: Pointer; nb_elems: Size_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_write';

(**
 * Write data from a user-provided callback into a FIFO.
 *
 * @param f the FIFO buffer
 * @param read_cb Callback supplying the data to the FIFO. May be called
 *                multiple times.
 * @param opaque opaque user data to be provided to read_cb
 * @param nb_elems Should point to the maximum number of elements that can be
 *                 written. Will be updated to contain the number of elements
 *                 actually written.
 *
 * @return non-negative number on success, a negative error code on failure
 *)
function av_fifo_write_from_cb(f: PAVFifo; read_cb: TAVFifoCB;
                          opaque: Pointer; nb_elems: PSize_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_write_from_cb';

(**
 * Read data from a FIFO.
 *
 * In case nb_elems > av_fifo_can_read(f), nothing is read and an error
 * is returned.
 *
 * @param f the FIFO buffer
 * @param buf Buffer to store the data. nb_elems * av_fifo_elem_size(f) bytes
 *            will be written into buf on success.
 * @param nb_elems number of elements to read from FIFO
 *
 * @return a non-negative number on success, a negative error code on failure
 *)
function av_fifo_read(f: PAVFifo; buf: Pointer; nb_elems: Size_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_read';

(**
 * Feed data from a FIFO into a user-provided callback.
 *
 * @param f the FIFO buffer
 * @param write_cb Callback the data will be supplied to. May be called
 *                 multiple times.
 * @param opaque opaque user data to be provided to write_cb
 * @param nb_elems Should point to the maximum number of elements that can be
 *                 read. Will be updated to contain the total number of elements
 *                 actually sent to the callback.
 *
 * @return non-negative number on success, a negative error code on failure
 *)
function av_fifo_read_to_cb(f: PAVFifo; write_cb: TAVFifoCB;
                       opaque: Pointer; nb_elems: PSize_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_read_to_cb';

(**
 * Read data from a FIFO without modifying FIFO state.
 *
 * Returns an error if an attempt is made to peek to nonexistent elements
 * (i.e. if offset + nb_elems is larger than av_fifo_can_read(f)).
 *
 * @param f the FIFO buffer
 * @param buf Buffer to store the data. nb_elems * av_fifo_elem_size(f) bytes
 *            will be written into buf.
 * @param nb_elems number of elements to read from FIFO
 * @param offset number of initial elements to skip.
 *
 * @return a non-negative number on success, a negative error code on failure
 *)
function av_fifo_peek(const f: PAVFifo; buf: Pointer; nb_elems, offset: Size_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_peek';

(**
 * Feed data from a FIFO into a user-provided callback.
 *
 * @param f the FIFO buffer
 * @param write_cb Callback the data will be supplied to. May be called
 *                 multiple times.
 * @param opaque opaque user data to be provided to write_cb
 * @param nb_elems Should point to the maximum number of elements that can be
 *                 read. Will be updated to contain the total number of elements
 *                 actually sent to the callback.
 * @param offset number of initial elements to skip; offset + *nb_elems must not
 *               be larger than av_fifo_can_read(f).
 *
 * @return a non-negative number on success, a negative error code on failure
 *)
function av_fifo_peek_to_cb(const f: PAVFifo; write_cb: TAVFifoCB; opaque: Pointer;
                       nb_elems: PSize_t; offset: Size_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_peek_to_cb';

(**
 * Discard the specified amount of data from an AVFifo.
 * @param size number of elements to discard, MUST NOT be larger than
 *             av_fifo_can_read(f)
 *)
procedure av_fifo_drain2(f: PAVFifo; size: Size_t); cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_drain2';

(*
 * Empty the AVFifo.
 * @param f AVFifo to reset
 *)
procedure av_fifo_reset2(f: PAVFifo); cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_reset2';

(**
 * Free an AVFifo and reset pointer to NULL.
 * @param f Pointer to an AVFifo to free. *f == NULL is allowed.
 *)
procedure av_fifo_freep2(f: PPAVFifo); cdecl; external AVUTIL_LIBNAME name _PU + 'av_fifo_freep2';

(**
 * @}
 *)

implementation

end.
