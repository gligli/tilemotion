(*
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with FFmpeg; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/threadmessage.h
 * Ported by CodeCoolie@CNSW 2023/03/06 -> $Date:: 2023-04-18 #$
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

unit libavutil_threadmessage;

interface

{$I CompilerDefines.inc}

{$I libversion.inc}

const
//  TAVThreadMessageFlags = (
    (**
     * Perform non-blocking operation.
     * If this flag is set, send and recv operations are non-blocking and
     * return AVERROR(EAGAIN) immediately if they can not proceed.
     *)
    AV_THREAD_MESSAGE_NONBLOCK = 1;
//  );

type
  PPAVThreadMessageQueue = ^PAVThreadMessageQueue;
  PAVThreadMessageQueue = ^TAVThreadMessageQueue;
  TAVThreadMessageQueue = record
    // need {$ALIGN 8}
  end;

  Tfree_funcCall = procedure(msg: Pointer); cdecl;

(**
 * Allocate a new message queue.
 *
 * @param mq      pointer to the message queue
 * @param nelem   maximum number of elements in the queue
 * @param elsize  size of each element in the queue
 * @return  >=0 for success; <0 for error, in particular AVERROR(ENOSYS) if
 *          lavu was built without thread support
 *)
function av_thread_message_queue_alloc(mq: PPAVThreadMessageQueue;
                                  nelem, elsize: Cardinal): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_alloc';

(**
 * Free a message queue.
 *
 * The message queue must no longer be in use by another thread.
 *)
procedure av_thread_message_queue_free(mq: PPAVThreadMessageQueue); cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_free';

(**
 * Send a message on the queue.
 *)
function av_thread_message_queue_send(mq: PAVThreadMessageQueue;
                                 msg: Pointer; flags: Cardinal): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_send';

(**
 * Receive a message from the queue.
 *)
function av_thread_message_queue_recv(mq: PAVThreadMessageQueue;
                                 msg: Pointer; flags: Cardinal): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_recv';

(**
 * Set the sending error code.
 *
 * If the error code is set to non-zero, av_thread_message_queue_send() will
 * return it immediately. Conventional values, such as AVERROR_EOF or
 * AVERROR(EAGAIN), can be used to cause the sending thread to stop or
 * suspend its operation.
 *)
procedure av_thread_message_queue_set_err_send(mq: PAVThreadMessageQueue; err: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_set_err_send';

(**
 * Set the receiving error code.
 *
 * If the error code is set to non-zero, av_thread_message_queue_recv() will
 * return it immediately when there are no longer available messages.
 * Conventional values, such as AVERROR_EOF or AVERROR(EAGAIN), can be used
 * to cause the receiving thread to stop or suspend its operation.
 *)
procedure av_thread_message_queue_set_err_recv(mq: PAVThreadMessageQueue; err: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_set_err_recv';

(**
 * Set the optional free message callback function which will be called if an
 * operation is removing messages from the queue.
 *)
procedure av_thread_message_queue_set_free_func(mq: PAVThreadMessageQueue; free_func: Tfree_funcCall); cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_set_free_func';

(**
 * Return the current number of messages in the queue.
 *
 * @return the current number of messages or AVERROR(ENOSYS) if lavu was built
 *         without thread support
 *)
function av_thread_message_queue_nb_elems(mq: PAVThreadMessageQueue): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_queue_nb_elems';

(**
 * Flush the message queue
 *
 * This function is mostly equivalent to reading and free-ing every message
 * except that it will be done in a single operation (no lock/unlock between
 * reads).
 *)
procedure av_thread_message_flush(mq: PAVThreadMessageQueue); cdecl; external AVUTIL_LIBNAME name _PU + 'av_thread_message_flush';

implementation

end.
