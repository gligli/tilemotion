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

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/container_fifo.h
 * Ported by CodeCoolie@CNSW 2025/09/26 -> $Date:: 2025-11-04 #$
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

unit libavutil_container_fifo;

interface

{$I CompilerDefines.inc}

uses
  FFTypes;

{$I libversion.inc}

type
(**
 * AVContainerFifo is a FIFO for "containers" - dynamically allocated reusable
 * structs (e.g. AVFrame or AVPacket). AVContainerFifo uses an internal pool of
 * such containers to avoid allocating and freeing them repeatedly.
 *)
  PPAVContainerFifo = ^PAVContainerFifo;
  PAVContainerFifo = ^TAVContainerFifo;
  TAVContainerFifo = record
    // need {$ALIGN 8}
    // defined in container_fifo.c
  end;

  TAVContainerFifoFlags = (
    (**
     * Signal to av_container_fifo_write() that it should make a new reference
     * to data in src rather than consume its contents.
     *
     * @note you must handle this flag manually in your own fifo_transfer()
     *       callback
     *)
    AV_CONTAINER_FIFO_FLAG_REF  = (1 shl 0),

    (**
     * This and all higher bits in flags may be set to any value by the caller
     * and are guaranteed to be passed through to the fifo_transfer() callback
     * and not be interpreted by AVContainerFifo code.
     *)
    AV_CONTAINER_FIFO_FLAG_USER = (1 shl 16)
  );

(**
 * Allocate a new AVContainerFifo for the container type defined by provided
 * callbacks.
 *
 * @param opaque user data that will be passed to the callbacks provided to this
 *               function
 * @param container_alloc allocate a new container instance and return a pointer
 *                        to it, or NULL on failure
 * @param container_reset reset the provided container instance to a clean state
 * @param container_free free the provided container instance
 * @param fifo_transfer Transfer the contents of container src to dst.
 * @param flags currently unused
 *
 * @return newly allocated AVContainerFifo, or NULL on failure
 *)
function av_container_fifo_alloc(opaque: Pointer;
                        container_alloc,
                        container_reset,
                        container_free,
                        fifo_transfer: Pointer;
                        flags: Cardinal): PAVContainerFifo; cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_alloc';

(**
 * Allocate an AVContainerFifo instance for AVFrames.
 *
 * @param flags currently unused
 *)
function av_container_fifo_alloc_avframe(flags: Cardinal): PAVContainerFifo; cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_alloc_avframe';

(**
 * Free a AVContainerFifo and everything in it.
 *)
procedure av_container_fifo_free(cf: PPAVContainerFifo); cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_free';

(**
 * Write the contents of obj to the FIFO.
 *
 * The fifo_transfer() callback previously provided to av_container_fifo_alloc()
 * will be called with obj as src in order to perform the actual transfer.
 *)
function av_container_fifo_write(cf: PAVContainerFifo; obj: Pointer; flags: Cardinal): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_write';

(**
 * Read the next available object from the FIFO into obj.
 *
 * The fifo_read() callback previously provided to av_container_fifo_alloc()
 * will be called with obj as dst in order to perform the actual transfer.
 *)
function av_container_fifo_read(cf: PAVContainerFifo; obj: Pointer; flags: Cardinal): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_read';

(**
 * Access objects stored in the FIFO without retrieving them. The
 * fifo_transfer() callback will NOT be invoked and the FIFO state will not be
 * modified.
 *
 * @param pobj Pointer to the object stored in the FIFO will be written here on
 *             success. The object remains owned by the FIFO and the caller may
 *             only access it as long as the FIFO is not modified.
 * @param offset Position of the object to retrieve - 0 is the next item that
 *               would be read, 1 the one after, etc. Must be smaller than
 *               av_container_fifo_can_read().
 *
 * @retval 0 success, a pointer was written into pobj
 * @retval AVERROR(EINVAL) invalid offset value
 *)
function av_container_fifo_peek(cf: PAVContainerFifo; pobj: PPointer; offset: Size_t): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_peek';

(**
 * Discard the specified number of elements from the FIFO.
 *
 * @param nb_elems number of elements to discard, MUST NOT be larger than
 *                 av_fifo_can_read(f)
 *)
procedure av_container_fifo_drain(cf: PAVContainerFifo; nb_elems: Size_t); cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_drain';

(**
 * @return number of objects available for reading
 *)
function av_container_fifo_can_read(const cf: PAVContainerFifo): Size_t; cdecl; external AVUTIL_LIBNAME name _PU + 'av_container_fifo_can_read';

implementation

end.
