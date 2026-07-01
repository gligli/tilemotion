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
 * @ingroup lavfi_buffersink
 * memory buffer sink API for audio and video
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavfilter/buffersink.h
 * Ported by CodeCoolie@CNSW 2014/07/21 -> $Date:: 2025-11-04 #$
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

unit libavfilter_buffersink;

interface

{$I CompilerDefines.inc}

uses
  libavfilter,
  libavutil,
  libavutil_buffer,
  libavutil_channel_layout,
  libavutil_frame,
  libavutil_pixfmt,
  libavutil_rational;

{$I libversion.inc}

(**
 * @defgroup lavfi_buffersink Buffer sink API
 * @ingroup lavfi
 * @{
 *
 * The buffersink and abuffersink filters are there to connect filter graphs
 * to applications. They have a single input, connected to the graph, and no
 * output. Frames must be extracted using av_buffersink_get_frame() or
 * av_buffersink_get_samples().
 *
 * The format negotiated by the graph during configuration can be obtained
 * using the accessor functions:
 * - av_buffersink_get_time_base(),
 * - av_buffersink_get_format(),
 * - av_buffersink_get_frame_rate(),
 * - av_buffersink_get_w(),
 * - av_buffersink_get_h(),
 * - av_buffersink_get_sample_aspect_ratio(),
 * - av_buffersink_get_channels(),
 * - av_buffersink_get_ch_layout(),
 * - av_buffersink_get_sample_rate().
 * - av_buffersink_get_side_data().
 *
 * The layout returned by av_buffersink_get_ch_layout() must de uninitialized
 * by the caller.
 *
 * The format can be constrained by setting options, using av_opt_set() and
 * related functions with the AV_OPT_SEARCH_CHILDREN flag.
 *  - pixel_formats (array of pixel formats),
 *  - colorspaces (array of int),
 *  - colorranges (array of int),
 *  - sample_formats (array of sample formats),
 *  - samplerates (array of int),
 *  - channel_layouts (array of channel layouts)
 * If an option is not set, all corresponding formats are accepted.
 *)

(**
 * Get a frame with filtered data from sink and put it in frame.
 *
 * @param ctx    pointer to a buffersink or abuffersink filter context.
 * @param frame  pointer to an allocated frame that will be filled with data.
 *               The data must be freed using av_frame_unref() / av_frame_free()
 * @param flags  a combination of AV_BUFFERSINK_FLAG_* flags
 *
 * @return  >= 0 in for success, a negative AVERROR code for failure.
 *)
function av_buffersink_get_frame_flags(ctx: PAVFilterContext; frame: PAVFrame; flags: Integer): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_frame_flags';

(**
 * Tell av_buffersink_get_buffer_ref() to read video/samples buffer
 * reference, but not remove it from the buffer. This is useful if you
 * need only to read a video/samples buffer, without to fetch it.
 *)
const
  AV_BUFFERSINK_FLAG_PEEK = 1;

(**
 * Tell av_buffersink_get_buffer_ref() not to request a frame from its input.
 * If a frame is already buffered, it is read (and removed from the buffer),
 * but if no frame is present, return AVERROR(EAGAIN).
 *)
  AV_BUFFERSINK_FLAG_NO_REQUEST = 2;

(**
 * Set the frame size for an audio buffer sink.
 *
 * All calls to av_buffersink_get_buffer_ref will return a buffer with
 * exactly the specified number of samples, or AVERROR(EAGAIN) if there is
 * not enough. The last buffer at EOF will be padded with 0.
 *)
procedure av_buffersink_set_frame_size(ctx: PAVFilterContext; frame_size: Cardinal); cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_set_frame_size';

(**
 * @defgroup lavfi_buffersink_accessors Buffer sink accessors
 * Get the properties of the stream
 * @{
 *)

function av_buffersink_get_type(const ctx: PAVFilterContext): TAVMediaType; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_type';
//AVRational       av_buffersink_get_time_base           (const AVFilterContext *ctx);
function av_buffersink_get_format(const ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_format';

//AVRational       av_buffersink_get_frame_rate          (const AVFilterContext *ctx);
function av_buffersink_get_w(const ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_w';
function av_buffersink_get_h(const ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_h';
//AVRational       av_buffersink_get_sample_aspect_ratio (const AVFilterContext *ctx);
function av_buffersink_get_colorspace(const ctx: PAVFilterContext): TAVColorSpace; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_colorspace';
function av_buffersink_get_color_range(const ctx: PAVFilterContext): TAVColorRange; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_color_range';

function av_buffersink_get_channels(const ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_channels';
function av_buffersink_get_ch_layout(const ctx: PAVFilterContext; ch_layout: PAVChannelLayout): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_ch_layout';
function av_buffersink_get_sample_rate(const ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_sample_rate';

function av_buffersink_get_hw_frames_ctx(const ctx: PAVFilterContext): PAVBufferRef; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_hw_frames_ctx';

function av_buffersink_get_side_data(const ctx: PAVFilterContext; nb_side_data: PInteger): PPAVFrameSideData; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_side_data';

(** @} *)

(**
 * Get a frame with filtered data from sink and put it in frame.
 *
 * @param ctx pointer to a context of a buffersink or abuffersink AVFilter.
 * @param frame pointer to an allocated frame that will be filled with data.
 *              The data must be freed using av_frame_unref() / av_frame_free()
 *
 * @return
 *         - >= 0 if a frame was successfully returned.
 *         - AVERROR(EAGAIN) if no frames are available at this point; more
 *           input frames must be added to the filtergraph to get more output.
 *         - AVERROR_EOF if there will be no more output frames on this sink.
 *         - A different negative AVERROR code in other failure cases.
 *)
function av_buffersink_get_frame(ctx: PAVFilterContext; frame: PAVFrame): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_frame';

(**
 * Same as av_buffersink_get_frame(), but with the ability to specify the number
 * of samples read. This function is less efficient than
 * av_buffersink_get_frame(), because it copies the data around.
 *
 * @param ctx pointer to a context of the abuffersink AVFilter.
 * @param frame pointer to an allocated frame that will be filled with data.
 *              The data must be freed using av_frame_unref() / av_frame_free()
 *              frame will contain exactly nb_samples audio samples, except at
 *              the end of stream, when it can contain less than nb_samples.
 *
 * @return The return codes have the same meaning as for
 *         av_buffersink_get_frame().
 *
 * @warning do not mix this function with av_buffersink_get_frame(). Use only one or
 * the other with a single sink, not both.
 *)
function av_buffersink_get_samples(ctx: PAVFilterContext; frame: PAVFrame; nb_samples: Integer): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'av_buffersink_get_samples';

(**
 * @}
 *)

function av_buffersink_get_time_base          (const ctx: PAVFilterContext): TAVRational;
function av_buffersink_get_frame_rate         (const ctx: PAVFilterContext): TAVRational;
function av_buffersink_get_sample_aspect_ratio(const ctx: PAVFilterContext): TAVRational;

implementation

(*
#define MAKE_AVFILTERLINK_ACCESSOR(type, field) \
type av_buffersink_get_##field(const AVFilterContext *ctx) { \
    av_assert0(fffilter(ctx->filter)->activate == activate); \
    return ctx->inputs[0]->field; \
}
*)

(****** TODO: check from libavfilter/buffersink.c **************)
//MAKE_AVFILTERLINK_ACCESSOR(AVRational       , time_base          )
function av_buffersink_get_time_base(const ctx: PAVFilterContext): TAVRational;
begin
  //Assert(PFFFilter(ctx.filter).activate = activate);
  // fffilter() -> PFFFilter in filters.h
  Result := ctx.inputs^^.time_base;
end;

(****** TODO: check from libavfilter/buffersink.c **************)
function av_buffersink_get_frame_rate(const ctx: PAVFilterContext): TAVRational;
begin
  //Assert(PFFFilter(ctx.filter).activate = activate);
  // fffilter() -> PFFFilter in filters.h
  //FilterLink *l = ff_filter_link(ctx->inputs[0]);
  //ff_filter_link() -> PFilterLink in filters.h
  Result := PFilterLink(ctx.inputs^)^.frame_rate;
end;

(****** TODO: check from libavfilter/buffersink.c **************)
//MAKE_AVFILTERLINK_ACCESSOR(AVRational       , sample_aspect_ratio)
function av_buffersink_get_sample_aspect_ratio(const ctx: PAVFilterContext): TAVRational;
begin
  //Assert(PFFFilter(ctx.filter).activate = activate);
  // fffilter() -> PFFFilter in filters.h
  Result := ctx.inputs^^.sample_aspect_ratio;
end;

end.
