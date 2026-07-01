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
 * Original file: libavfilter/formats.h
 * Ported by CodeCoolie@CNSW 2014/07/21 -> $Date:: 2025-01-17 #$
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

unit libavfilter_formats;

interface

{$I CompilerDefines.inc}

uses
  libavfilter,
  libavutil,
  libavutil_channel_layout;

{$I libversion.inc}

const
  //* format is software, non-planar with sub-sampling
  FF_PIX_FMT_FLAG_SW_FLAT_SUB = (1 shl 24);

type
(**
 * A list of supported formats for one end of a filter link. This is used
 * during the format negotiation process to try to pick the best format to
 * use to minimize the number of necessary conversions. Each filter gives a
 * list of the formats supported by each input and output pad. The list
 * given for each pad need not be distinct - they may be references to the
 * same list of formats, as is often the case when a filter supports multiple
 * formats, but will always output the same format as it is given in input.
 *
 * In this way, a list of possible input formats and a list of possible
 * output formats are associated with each link. When a set of formats is
 * negotiated over a link, the input and output lists are merged to form a
 * new list containing only the common elements of each list. In the case
 * that there were no common elements, a format conversion is necessary.
 * Otherwise, the lists are merged, and all other links which reference
 * either of the format lists involved in the merge are also affected.
 *
 * For example, consider the filter chain:
 * filter (a) --> (b) filter (b) --> (c) filter
 *
 * where the letters in parenthesis indicate a list of formats supported on
 * the input or output of the link. Suppose the lists are as follows:
 * (a) = {A, B}
 * (b) = {A, B, C}
 * (c) = {B, C}
 *
 * First, the first link's lists are merged, yielding:
 * filter (a) --> (a) filter (a) --> (c) filter
 *
 * Notice that format list (b) now refers to the same list as filter list (a).
 * Next, the lists for the second link are merged, yielding:
 * filter (a) --> (a) filter (a) --> (a) filter
 *
 * where (a) = {B}.
 *
 * Unfortunately, when the format lists at the two ends of a link are merged,
 * we must ensure that all links which reference either pre-merge format list
 * get updated as well. Therefore, we have the format list structure store a
 * pointer to each of the pointers to itself.
 *)
  PPPAVFilterFormats = ^PPAVFilterFormats;
  PPAVFilterFormats = ^PAVFilterFormats;
  PAVFilterFormats = ^TAVFilterFormats;
  TAVFilterFormats = record
    nb_formats: Cardinal;         ///< number of formats
    formats: PInteger;            ///< list of media formats

    refcount: Cardinal;           ///< number of references to this list
    refs: PPPAVFilterFormats;     ///< references to this list
  end;

(**
 * A list of supported channel layouts.
 *
 * The list works the same as AVFilterFormats, except for the following
 * differences:
 * - A list with all_layouts = 1 means all channel layouts with a known
 *   disposition; nb_channel_layouts must then be 0.
 * - A list with all_counts = 1 means all channel counts, with a known or
 *   unknown disposition; nb_channel_layouts must then be 0 and all_layouts 1.
 * - The list must not contain a layout with a known disposition and a
 *   channel count with unknown disposition with the same number of channels
 *   (e.g. AV_CH_LAYOUT_STEREO and FF_COUNT2LAYOUT(2).
 *)
  PPPAVFilterChannelLayouts = ^PPAVFilterChannelLayouts;
  PPAVFilterChannelLayouts = ^PAVFilterChannelLayouts;
  PAVFilterChannelLayouts = ^TAVFilterChannelLayouts;
  TAVFilterChannelLayouts = record
    channel_layouts: PAVChannelLayout; ///< list of channel layouts
    nb_channel_layouts: Integer;      ///< number of channel layouts
    all_layouts: AnsiChar;            ///< accept any known channel layout
    all_counts: AnsiChar;             ///< accept any channel layout or count

    refcount: Cardinal;               ///< number of references to this list
    refs: PPPAVFilterChannelLayouts;  ///< references to this list
  end;

(**
 * Encode a channel count as a channel layout.
 * FF_COUNT2LAYOUT(c) means any channel layout with c channels, with a known
 * or unknown disposition.
 * The result is only valid inside AVFilterChannelLayouts and immediately
 * related functions.
 *)
//#define FF_COUNT2LAYOUT(c) ((AVChannelLayout) { .order = AV_CHANNEL_ORDER_UNSPEC, .nb_channels = c })

(**
 * Decode a channel count encoded as a channel layout.
 * Return 0 if the channel layout was a real one.
 *)
//#define FF_LAYOUT2COUNT(l) (((l)->order == AV_CHANNEL_ORDER_UNSPEC) ? \
//                            (l)->nb_channels : 0)

//#define KNOWN(l) (!FF_LAYOUT2COUNT(l)) /* for readability */

(**
 * Construct an empty AVFilterChannelLayouts/AVFilterFormats struct --
 * representing any channel layout (with known disposition)/sample rate.
 *)
function ff_all_channel_layouts: PAVFilterChannelLayouts; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_all_channel_layouts';

function ff_all_samplerates: PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_all_samplerates';

(**
 * Construct an AVFilterChannelLayouts coding for any channel layout, with
 * known or unknown disposition.
 *)
function ff_all_channel_counts: PAVFilterChannelLayouts; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_all_channel_counts';

function ff_make_channel_layout_list(const fmts: PAVChannelLayout): PAVFilterChannelLayouts; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_make_channel_layout_list';

(**
 * Construct an AVFilterFormats representing all possible color spaces.
 *
 * Note: This list does not include AVCOL_SPC_RESERVED.
 *)
function ff_all_color_spaces(): PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_all_color_spaces';

(**
 * Construct an AVFilterFormats representing all possible color ranges.
 *)
function ff_all_color_ranges(): PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_all_color_ranges';

(**
 * Helpers for query_formats() which set all free audio links to the same list
 * of channel layouts/sample rates. If there are no links hooked to this list,
 * the list is freed.
 *)
function ff_set_common_channel_layouts(ctx: PAVFilterContext;
                                   layouts: PAVFilterChannelLayouts): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_channel_layouts';
(**
 * Equivalent to ff_set_common_channel_layouts(ctx, ff_make_channel_layout_list(fmts))
 *)
function ff_set_common_channel_layouts_from_list(ctx: PAVFilterContext;
                                            const fmts: PAVChannelLayout): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_channel_layouts_from_list';
(**
 * Equivalent to ff_set_common_channel_layouts(ctx, ff_all_channel_counts())
 *)
function ff_set_common_all_channel_counts(ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_channel_counts';

function ff_set_common_samplerates(ctx: PAVFilterContext;
                               samplerates: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_samplerates';
(**
 * Equivalent to ff_set_common_samplerates(ctx, ff_make_format_list(samplerates))
 *)
function ff_set_common_samplerates_from_list(ctx: PAVFilterContext;
                                        const samplerates: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_samplerates_from_list';
(**
 * Equivalent to ff_set_common_samplerates(ctx, ff_all_samplerates())
 *)
function ff_set_common_all_samplerates(ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_samplerates';

function ff_set_common_color_spaces(ctx: PAVFilterContext;
                               color_spaces: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_spaces';
(**
 * Equivalent to ff_set_common_color_spaces(ctx, ff_make_format_list(color_spaces))
 *)
function ff_set_common_color_spaces_from_list(ctx: PAVFilterContext;
                                         const color_spaces: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_spaces_from_list';

(**
 * Equivalent to ff_set_common_color_spaces(ctx, ff_all_color_spaces())
 *)
function ff_set_common_all_color_spaces(ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_color_spaces';

function ff_set_common_color_ranges(ctx: PAVFilterContext;
                               color_ranges: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_ranges';
(**
 * Equivalent to ff_set_common_color_ranges(ctx, ff_make_format_list(color_ranges))
 *)
function ff_set_common_color_ranges_from_list(ctx: PAVFilterContext;
                                         const color_ranges: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_ranges_from_list';

(**
 * Equivalent to ff_set_common_color_ranges(ctx, ff_all_color_ranges())
 *)
function ff_set_common_all_color_ranges(ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_color_ranges';

(**
 * A helper for query_formats() which sets all links to the same list of
 * formats. If there are no links hooked to this filter, the list of formats is
 * freed.
 *)
function ff_set_common_formats(ctx: PAVFilterContext; formats: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_formats';

(**
 * Equivalent to ff_set_common_formats(ctx, ff_make_format_list(fmts))
 *)
function ff_set_common_formats_from_list(ctx: PAVFilterContext; const fmts: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_formats_from_list';

(**
 * Helpers for query_formats2() which set all free audio links to the same list
 * of channel layouts/sample rates. If there are no links hooked to this list,
 * the list is freed.
 *)
function ff_set_common_channel_layouts2(const ctx: PAVFilterContext;
                                   cfg_in: PPAVFilterFormatsConfig;
                                   cfg_out: PPAVFilterFormatsConfig;
                                   channel_layouts: PAVFilterChannelLayouts): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_channel_layouts2';

function ff_set_common_channel_layouts_from_list2(const ctx: PAVFilterContext;
                                             cfg_in: PPAVFilterFormatsConfig;
                                             cfg_out: PPAVFilterFormatsConfig;
                                             const fmts: PAVChannelLayout): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_channel_layouts_from_list2';

function ff_set_common_all_channel_counts2(const ctx: PAVFilterContext;
                                      cfg_in: PPAVFilterFormatsConfig;
                                      cfg_out: PPAVFilterFormatsConfig): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_channel_counts2';

function ff_set_common_samplerates2(const ctx: PAVFilterContext;
                               cfg_in: PPAVFilterFormatsConfig;
                               cfg_out: PPAVFilterFormatsConfig;
                               samplerates: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_samplerates2';

function ff_set_common_samplerates_from_list2(const ctx: PAVFilterContext;
                                         cfg_in: PPAVFilterFormatsConfig;
                                         cfg_out: PPAVFilterFormatsConfig;
                                         const samplerates: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_samplerates_from_list2';

function ff_set_common_all_samplerates2(const ctx: PAVFilterContext;
                                   cfg_in: PPAVFilterFormatsConfig;
                                   cfg_out: PPAVFilterFormatsConfig): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_samplerates2';

function ff_set_common_color_spaces2(const ctx: PAVFilterContext;
                                cfg_in: PPAVFilterFormatsConfig;
                                cfg_out: PPAVFilterFormatsConfig;
                                color_spaces: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_spaces2';

function ff_set_common_color_spaces_from_list2(const ctx: PAVFilterContext;
                                          cfg_in: PPAVFilterFormatsConfig;
                                          cfg_out: PPAVFilterFormatsConfig;
                                          const color_ranges: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_spaces_from_list2';

function ff_set_common_all_color_spaces2(const ctx: PAVFilterContext;
                                    cfg_in: PPAVFilterFormatsConfig;
                                    cfg_out: PPAVFilterFormatsConfig): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_color_spaces2';

function ff_set_common_color_ranges2(const ctx: PAVFilterContext;
                                cfg_in: PPAVFilterFormatsConfig;
                                cfg_out: PPAVFilterFormatsConfig;
                                color_ranges: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_ranges2';

function ff_set_common_color_ranges_from_list2(const ctx: PAVFilterContext;
                                          cfg_in: PPAVFilterFormatsConfig;
                                          cfg_out: PPAVFilterFormatsConfig;
                                          const color_ranges: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_color_ranges_from_list2';

function ff_set_common_all_color_ranges2(const ctx: PAVFilterContext;
                                    cfg_in: PPAVFilterFormatsConfig;
                                    cfg_out: PPAVFilterFormatsConfig): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_all_color_ranges2';

function ff_set_common_formats2(const ctx: PAVFilterContext;
                           cfg_in: PPAVFilterFormatsConfig;
                           cfg_out: PPAVFilterFormatsConfig;
                           formats: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_formats2';

function ff_set_common_formats_from_list2(const ctx: PAVFilterContext;
                                     cfg_in: PPAVFilterFormatsConfig;
                                     cfg_out: PPAVFilterFormatsConfig;
                                     const fmts: PInteger): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_set_common_formats_from_list2';

function ff_add_channel_layout(l: PPAVFilterChannelLayouts; channel_layout: PAVChannelLayout): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_add_channel_layout';

(**
 * Add *ref as a new reference to f.
 *)
function ff_channel_layouts_ref(f: PAVFilterChannelLayouts;
                            ref: PPAVFilterChannelLayouts): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_channel_layouts_ref';

(**
 * Remove a reference to a channel layouts list.
 *)
procedure ff_channel_layouts_unref(ref: PPAVFilterChannelLayouts); cdecl; external AVFILTER_LIBNAME name _PU + 'ff_channel_layouts_unref';

procedure ff_channel_layouts_changeref(oldref, newref: PPAVFilterChannelLayouts); cdecl; external AVFILTER_LIBNAME name _PU + 'ff_channel_layouts_changeref';

(**
 * Sets all remaining unset filter lists for all inputs/outputs to their
 * corresponding `ff_all_*()` lists.
 *)
function ff_default_query_formats(ctx: PAVFilterContext): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_default_query_formats';

(**
 * Create a list of supported formats. This is intended for use in
 * AVFilter->query_formats().
 *
 * @param fmts list of media formats, terminated by -1
 * @return the format list, with no existing references
 *)
function ff_make_format_list(const fmts: PInteger): PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_make_format_list';

(**
 * Equivalent to ff_make_format_list({const int[]}{ fmt, -1 })
 *)
function ff_make_formats_list_singleton(fmt: Integer): PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_make_formats_list_singleton';

(**
 * Add fmt to the list of media formats contained in *avff.
 * If *avff is NULL the function allocates the filter formats struct
 * and puts its pointer in *avff.
 *
 * @return a non negative value in case of success, or a negative
 * value corresponding to an AVERROR code in case of error
 *)
function ff_add_format(avff: PPAVFilterFormats; fmt: Int64): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_add_format';

(**
 * Return a list of all formats supported by FFmpeg for the given media type.
 *)
function ff_all_formats(type_: TAVMediaType): PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_all_formats';

(**
 * Construct a formats list containing all pixel formats with certain
 * properties
 *)
function ff_formats_pixdesc_filter(want, rej: Cardinal): PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_pixdesc_filter';

//* format is software, non-planar with sub-sampling
//#define FF_PIX_FMT_FLAG_SW_FLAT_SUB (1 << 24)

(**
 * Construct a formats list containing all planar sample formats.
 *)
function ff_planar_sample_fmts: PAVFilterFormats; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_planar_sample_fmts';

(**
 * Add *ref as a new reference to formats.
 * That is the pointers will point like in the ascii art below:
 *   ________
 *  |formats |<--------.
 *  |  ____  |     ____|___________________
 *  | |refs| |    |  __|_
 *  | |* * | |    | |  | |  AVFilterLink
 *  | |* *--------->|*ref|
 *  | |____| |    | |____|
 *  |________|    |________________________
 *)
function ff_formats_ref(formats: PAVFilterFormats; ref: PPAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_ref';

(**
 * If *ref is non-NULL, remove *ref as a reference to the format list
 * it currently points to, deallocates that list if this was the last
 * reference, and sets *ref to NULL.
 *
 *         Before                                 After
 *   ________                               ________         NULL
 *  |formats |<--------.                   |formats |         ^
 *  |  ____  |     ____|________________   |  ____  |     ____|________________
 *  | |refs| |    |  __|_                  | |refs| |    |  __|_
 *  | |* * | |    | |  | |  AVFilterLink   | |* * | |    | |  | |  AVFilterLink
 *  | |* *--------->|*ref|                 | |*   | |    | |*ref|
 *  | |____| |    | |____|                 | |____| |    | |____|
 *  |________|    |_____________________   |________|    |_____________________
 *)
procedure ff_formats_unref(ref: PPAVFilterFormats); cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_unref';

(**
 *         Before                                 After
 *   ________                         ________
 *  |formats |<---------.            |formats |<---------.
 *  |  ____  |       ___|___         |  ____  |       ___|___
 *  | |refs| |      |   |   |        | |refs| |      |   |   |   NULL
 *  | |* *--------->|*oldref|        | |* *--------->|*newref|     ^
 *  | |* * | |      |_______|        | |* * | |      |_______|  ___|___
 *  | |____| |                       | |____| |                |   |   |
 *  |________|                       |________|                |*oldref|
 *                                                             |_______|
 *)
procedure ff_formats_changeref(oldref, newref: PPAVFilterFormats); cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_changeref';

(**
 * Check that fmts is a valid pixel formats list.
 *
 * In particular, check for duplicates.
 *)
function ff_formats_check_pixel_formats(log: Pointer; const fmts: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_check_pixel_formats';

(**
 * Check that fmts is a valid sample formats list.
 *
 * In particular, check for duplicates.
 *)
function ff_formats_check_sample_formats(log: Pointer; const fmts: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_check_sample_formats';

(**
 * Check that fmts is a valid sample rates list.
 *
 * In particular, check for duplicates.
 *)
function ff_formats_check_sample_rates(log: Pointer; const fmts: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_check_sample_rates';

(**
 * Check that fmts is a valid channel layouts list.
 *
 * In particular, check for duplicates.
 *)
function ff_formats_check_channel_layouts(log: Pointer; const fmts: PAVFilterChannelLayouts): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_check_channel_layouts';

(**
 * Check that fmts is a valid formats list for YUV colorspace metadata.
 *
 * In particular, check for duplicates.
 *)
function ff_formats_check_color_spaces(log: Pointer; const fmts: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_check_color_spaces';
function ff_formats_check_color_ranges(log: Pointer; const fmts: PAVFilterFormats): Integer; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_formats_check_color_ranges';

type
  PAVFilterFormatsMerger = ^TAVFilterFormatsMerger;
  TAVFilterFormatsMerger = record
    offset: Cardinal;
    merge: function(a, b: Pointer): Integer; cdecl;
    can_merge: function(a, b: Pointer): Integer; cdecl;
  end;

(**
 * Callbacks and properties to describe the steps of a format negotiation.
 *
 * The steps are:
 *
 * 1. query_formats(): call the callbacks on all filter to set lists of
 *                     supported formats.
 *                     When links on a filter must eventually have the same
 *                     format, the lists of supported formats are the same
 *                     object in memory.
 *                     See:
 *                     http://www.normalesup.org/~george/articles/format_negotiation_in_libavfilter/#12
 *
 *
 * 2. query_formats(): merge lists of supported formats or insert automatic
 *                     conversion filters.
 *                     Compute the intersection of the lists of supported
 *                     formats on the ends of links. If it succeeds, replace
 *                     both objects with the intersection everywhere they
 *                     are referenced.
 *                     If the intersection is empty, insert an automatic
 *                     conversion filter.
 *                     If several formats are negotiated at once (format,
 *                     rate, layout), only merge if all three can be, since
 *                     the conversion filter can convert all three at once.
 *                     This process goes on as long as progress is made.
 *                     See:
 *                     http://www.normalesup.org/~george/articles/format_negotiation_in_libavfilter/#14
 *                     http://www.normalesup.org/~george/articles/format_negotiation_in_libavfilter/#29
 *
 * 3. reduce_formats(): try to reduce format conversion within filters.
 *                      For each link where there is only one supported
 *                      formats on output, for each output of the connected
 *                      filter, if the media type is the same and said
 *                      format is supported, keep only this one.
 *                      This process goes on as long as progress is made.
 *                      Rationale: conversion filters will set a large list
 *                      of supported formats on outputs but users will
 *                      expect the output to be as close as possible as the
 *                      input (examples: scale without changing the pixel
 *                      format, resample without changint the layout).
 *                      FIXME: this can probably be done by merging the
 *                      input and output lists instead of re-implementing
 *                      the logic.
 *
 * 4. swap_sample_fmts():
 *    swap_samplerates():
 *    swap_channel_layouts(): For each filter with an input with only one
 *                            supported format, when outputs have several
 *                            supported formats, put the best one with
 *                            reference to the input at the beginning of the
 *                            list, to prepare it for being picked up by
 *                            pick_formats().
 *                            The best format is the one that is most
 *                            similar to the input while not losing too much
 *                            information.
 *                            This process need to run only once.
 *                            FIXME: reduce_formats() operates on all inputs
 *                            with a single format, swap_*() operates on the
 *                            first one only: check if the difference makes
 *                            sense.
 *                            TODO: the swapping done for one filter can
 *                            override the swapping done for another filter
 *                            connected to the same list of formats, maybe
 *                            it would be better to compute a total score
 *                            for all connected filters and use the score to
 *                            pick the format instead of just swapping.
 *                            TODO: make the similarity logic available as
 *                            public functions in libavutil.
 *
 * 5. pick_formats(): Choose one format from the lists of supported formats,
 *                    use it for the link and reduce the list to a single
 *                    element to force other filters connected to the same
 *                    list to use it.
 *                    First process all links where there is a single format
 *                    and the output links of all filters with an input,
 *                    trying to preserve similarity between input and
 *                    outputs.
 *                    Repeat as long as process is made.
 *                    Then do a final run for the remaining filters.
 *                    FIXME: the similarity logic (the ref argument to
 *                    pick_format()) added in FFmpeg duplicates and
 *                    overrides the swapping logic added in libav. Better
 *                    merge them into a score system.
 *)
  PAVFilterNegotiation = ^TAVFilterNegotiation;
  TAVFilterNegotiation = record
    nb_mergers: Cardinal;
    mergers: PAVFilterFormatsMerger;
    conversion_filter: PAnsiChar;
    conversion_opts_offset: Cardinal;
  end;

function ff_filter_get_negotiation(link: PAVFilterLink): PAVFilterNegotiation; cdecl; external AVFILTER_LIBNAME name _PU + 'ff_filter_get_negotiation';

implementation

end.
