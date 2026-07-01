(*
 * Copyright (C) 2024 Niklas Haas
 * Copyright (C) 2001-2011 Michael Niedermayer <michaelni@gmx.at>
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
 * @ingroup libsws
 * external API header
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libswscale/swscale.h
 * Ported by CodeCoolie@CNSW 2008/03/20 -> $Date:: 2026-04-05 #$
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

unit libswscale;

interface

{$I CompilerDefines.inc}

uses
  libavutil_frame,
  libavutil_log,
  libavutil_pixfmt,
  FFTypes;

{$I libversion.inc}

(**
 * @defgroup libsws libswscale
 * Color conversion and scaling library.
 *
 * @{
 *)

(**
 * Return the LIBSWSCALE_VERSION_INT constant.
 *)
function swscale_version: Cardinal; cdecl; external SWSCALE_LIBNAME name _PU + 'swscale_version';

(**
 * Return the libswscale build-time configuration.
 *)
function swscale_configuration: PAnsiChar; cdecl; external SWSCALE_LIBNAME name _PU + 'swscale_configuration';

(**
 * Return the libswscale license.
 *)
function swscale_license: PAnsiChar; cdecl; external SWSCALE_LIBNAME name _PU + 'swscale_license';

(**
 * Get the AVClass for SwsContext. It can be used in combination with
 * AV_OPT_SEARCH_FAKE_OBJ for examining options.
 *
 * @see av_opt_find().
 *)
function sws_get_class: PAVClass; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_get_class';

(******************************
 * Flags and quality settings *
 ******************************)
type
  TSwsDither = (
    SWS_DITHER_NONE = 0, (* disable dithering *)
    SWS_DITHER_AUTO,     (* auto-select from preset *)
    SWS_DITHER_BAYER,    (* ordered dither matrix *)
    SWS_DITHER_ED,       (* error diffusion *)
    SWS_DITHER_A_DITHER, (* arithmetic addition *)
    SWS_DITHER_X_DITHER, (* arithmetic xor *)
    SWS_DITHER_NB        (* not part of the ABI *)
  );

  TSwsAlphaBlend = (
    SWS_ALPHA_BLEND_NONE = 0,
    SWS_ALPHA_BLEND_UNIFORM,
    SWS_ALPHA_BLEND_CHECKERBOARD,
    SWS_ALPHA_BLEND_NB   (* not part of the ABI *)
  );

  TSwsFlags = (
    (**
     * Scaler selection options. Only one may be active at a time.
     *)
    SWS_FAST_BILINEAR = (1 shl  0), ///< fast bilinear filtering
    SWS_BILINEAR      = (1 shl  1), ///< bilinear filtering
    SWS_BICUBIC       = (1 shl  2), ///< 2-tap cubic B-spline
    SWS_X             = (1 shl  3), ///< experimental
    SWS_POINT         = (1 shl  4), ///< nearest neighbor
    SWS_AREA          = (1 shl  5), ///< area averaging
    SWS_BICUBLIN      = (1 shl  6), ///< bicubic luma, bilinear chroma
    SWS_GAUSS         = (1 shl  7), ///< gaussian approximation
    SWS_SINC          = (1 shl  8), ///< unwindowed sinc
    SWS_LANCZOS       = (1 shl  9), ///< 3-tap sinc/sinc
    SWS_SPLINE        = (1 shl 10), ///< cubic Keys spline

    (**
     * Return an error on underspecified conversions. Without this flag,
     * unspecified fields are defaulted to sensible values.
     *)
    SWS_STRICT        = (1 shl 11),

    (**
     * Emit verbose log of scaling parameters.
     *)
    SWS_PRINT_INFO    = (1 shl 12),

    (**
     * Perform full chroma upsampling when upscaling to RGB.
     *
     * For example, when converting 50x50 yuv420p to 100x100 rgba, setting this flag
     * will scale the chroma plane from 25x25 to 100x100 (4:4:4), and then convert
     * the 100x100 yuv444p image to rgba in the final output step.
     *
     * Without this flag, the chroma plane is instead scaled to 50x100 (4:2:2),
     * with a single chroma sample being reused for both of the horizontally
     * adjacent RGBA output pixels.
     *)
    SWS_FULL_CHR_H_INT = (1 shl 13),

    (**
     * Perform full chroma interpolation when downscaling RGB sources.
     *
     * For example, when converting a 100x100 rgba source to 50x50 yuv444p, setting
     * this flag will generate a 100x100 (4:4:4) chroma plane, which is then
     * downscaled to the required 50x50.
     *
     * Without this flag, the chroma plane is instead generated at 50x100 (dropping
     * every other pixel), before then being downscaled to the required 50x50
     * resolution.
     *)
    SWS_FULL_CHR_H_INP = (1 shl 14),

    (**
     * Force bit-exact output. This will prevent the use of platform-specific
     * optimizations that may lead to slight difference in rounding, in favor
     * of always maintaining exact bit output compatibility with the reference
     * C code.
     *
     * Note: It is recommended to set both of these flags simultaneously.
     *)
    SWS_ACCURATE_RND   = (1 shl 18),
    SWS_BITEXACT       = (1 shl 19),

    (**
     * Deprecated flags.
     *)
    SWS_DIRECT_BGR      = (1 shl 15), ///< This flag has no effect
    SWS_ERROR_DIFFUSION = (1 shl 23)  ///< Set `SwsContext.dither` instead
  );

  TSwsIntent = (
    SWS_INTENT_PERCEPTUAL = 0,            ///< Perceptual tone mapping
    SWS_INTENT_RELATIVE_COLORIMETRIC = 1, ///< Relative colorimetric clipping
    SWS_INTENT_SATURATION = 2,            ///< Saturation mapping
    SWS_INTENT_ABSOLUTE_COLORIMETRIC = 3, ///< Absolute colorimetric clipping
    SWS_INTENT_NB  ///< not part of the ABI
  );

(***********************************
 * Context creation and management *
 ***********************************)

(**
 * Main external API structure. New fields can be added to the end with
 * minor version bumps. Removal, reordering and changes to existing fields
 * require a major version bump. sizeof(SwsContext) is not part of the ABI.
 *)
  PPSwsContext = ^PSwsContext;
  PSwsContext = ^TSwsContext;
  TSwsContext = record
    av_class: PAVClass;

    (**
     * Private data of the user, can be used to carry app specific stuff.
     *)
    opaque: Pointer;

    (**
     * Bitmask of SWS_*. See `SwsFlags` for details.
     *)
    flags: Cardinal;

    (**
     * Extra parameters for fine-tuning certain scalers.
     *)
    scaler_params: array[0..2 - 1] of Double;

    (**
     * How many threads to use for processing, or 0 for automatic selection.
     *)
    threads: Integer;

    (**
     * Dither mode.
     *)
    dither: TSwsDither;

    (**
     * Alpha blending mode. See `SwsAlphaBlend` for details.
     *)
    alpha_blend: TSwsAlphaBlend;

    (**
     * Use gamma correct scaling.
     *)
    gamma_flag: Integer;

    (**
     * Deprecated frame property overrides, for the legacy API only.
     *
     * Ignored by sws_scale_frame() when used in dynamic mode, in which
     * case all properties are instead taken from the frame directly.
     *)
    src_w, src_h: Integer;  ///< Width and height of the source frame
    dst_w, dst_h: Integer;  ///< Width and height of the destination frame
    src_format: Integer;    ///< Source pixel format
    dst_format: Integer;    ///< Destination pixel format
    src_range: Integer;     ///< Source is full range
    dst_range: Integer;     ///< Destination is full range
    src_v_chr_pos: Integer; ///< Source vertical chroma position in luma grid / 256
    src_h_chr_pos: Integer; ///< Source horizontal chroma position
    dst_v_chr_pos: Integer; ///< Destination vertical chroma position
    dst_h_chr_pos: Integer; ///< Destination horizontal chroma position

    (**
     * Desired ICC intent for color space conversions.
     *)
    intent: Integer;

    (* Remember to add new fields to graph.c:opts_equal() *)
  end;

(**
 * Allocate an empty SwsContext and set its fields to default values.
 *)
function sws_alloc_context(): PSwsContext; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_alloc_context';

(**
 * Free the context and everything associated with it, and write NULL
 * to the provided pointer.
 *)
procedure sws_free_context(ctx: PPSwsContext); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_free_context';

(***************************
 * Supported frame formats *
 ***************************)

(**
 * Test if a given pixel format is supported.
 *
 * @param output  If 0, test if compatible with the source/input frame;
 *                otherwise, with the destination/output frame.
 * @param format  The format to check.
 *
 * @return A positive integer if supported, 0 otherwise.
 *)
function sws_test_format(format: TAVPixelFormat; output: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_test_format';

(**
 * Test if a given color space is supported.
 *
 * @param output  If 0, test if compatible with the source/input frame;
 *                otherwise, with the destination/output frame.
 * @param colorspace The colorspace to check.
 *
 * @return A positive integer if supported, 0 otherwise.
 *)
function sws_test_colorspace(colorspace: TAVColorSpace; output: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_test_colorspace';

(**
 * Test if a given set of color primaries is supported.
 *
 * @param output  If 0, test if compatible with the source/input frame;
 *                otherwise, with the destination/output frame.
 * @param primaries The color primaries to check.
 *
 * @return A positive integer if supported, 0 otherwise.
 *)
function sws_test_primaries(primaries: TAVColorPrimaries; output: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_test_primaries';

(**
 * Test if a given color transfer function is supported.
 *
 * @param output  If 0, test if compatible with the source/input frame;
 *                otherwise, with the destination/output frame.
 * @param trc     The color transfer function to check.
 *
 * @return A positive integer if supported, 0 otherwise.
 *)
function sws_test_transfer(trc: TAVColorTransferCharacteristic; output: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_test_transfer';

(**
 * Helper function to run all sws_test_* against a frame, as well as testing
 * the basic frame properties for sanity. Ignores irrelevant properties - for
 * example, AVColorSpace is not checked for RGB frames.
 *)
function sws_test_frame(const frame: PAVFrame; output: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_test_frame';

(**
 * Like `sws_scale_frame`, but without actually scaling. It will instead
 * merely initialize internal state that *would* be required to perform the
 * operation, as well as returning the correct error code for unsupported
 * frame combinations.
 *
 * @param ctx   The scaling context.
 * @param dst   The destination frame to consider.
 * @param src   The source frame to consider.
 * @return 0 on success, a negative AVERROR code on failure.
 *)
function sws_frame_setup(ctx: PSwsContext; const dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_frame_setup';

(********************
 * Main scaling API *
 ********************)

(**
 * Check if a given conversion is a noop. Returns a positive integer if
 * no operation needs to be performed, 0 otherwise.
 *)
function sws_is_noop(const dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_is_noop';

(**
 * Scale source data from `src` and write the output to `dst`.
 *
 * This function can be used directly on an allocated context, without setting
 * up any frame properties or calling `sws_init_context()`. Such usage is fully
 * dynamic and does not require reallocation if the frame properties change.
 *
 * Alternatively, this function can be called on a context that has been
 * explicitly initialized. However, this is provided only for backwards
 * compatibility. In this usage mode, all frame properties must be correctly
 * set at init time, and may no longer change after initialization.
 *
 * @param ctx   The scaling context.
 * @param dst   The destination frame. The data buffers may either be already
 *              allocated by the caller or left clear, in which case they will
 *              be allocated by the scaler. The latter may have performance
 *              advantages - e.g. in certain cases some (or all) output planes
 *              may be references to input planes, rather than copies.
 * @param src   The source frame. If the data buffers are set to NULL, then
 *              this function behaves identically to `sws_frame_setup`.
 * @return >= 0 on success, a negative AVERROR code on failure.
 *)
function sws_scale_frame(c: PSwsContext; dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_scale_frame';

const
(*************************
 * Legacy (stateful) API *
 *************************)

  SWS_SRC_V_CHR_DROP_MASK     = $30000;
  SWS_SRC_V_CHR_DROP_SHIFT    = 16;

  SWS_PARAM_DEFAULT           = 123456;

  SWS_MAX_REDUCE_CUTOFF = 0.002;

  SWS_CS_ITU709         = 1;
  SWS_CS_FCC            = 4;
  SWS_CS_ITU601         = 5;
  SWS_CS_ITU624         = 5;
  SWS_CS_SMPTE170M      = 5;
  SWS_CS_SMPTE240M      = 7;
  SWS_CS_DEFAULT        = 5;
  SWS_CS_BT2020         = 9;

(**
 * Return a pointer to yuv<->rgb coefficients for the given colorspace
 * suitable for sws_setColorspaceDetails().
 *
 * @param colorspace One of the SWS_CS_* macros. If invalid,
 * SWS_CS_DEFAULT is used.
 *)
function sws_getCoefficients(colorspace: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_getCoefficients';

type
  PPInteger = ^PInteger;

// when used for filters they must have an odd number of elements
// coeffs cannot be shared between vectors
  PSwsVector = ^TSwsVector;
  TSwsVector = record
    coeff: PDouble;             ///< pointer to the list of coefficients
    length: Integer;            ///< number of coefficients in the vector
  end;

// vectors can be shared
  PSwsFilter = ^TSwsFilter;
  TSwsFilter = record
    lumH: PSwsVector;
    lumV: PSwsVector;
    chrH: PSwsVector;
    chrV: PSwsVector;
  end;

(**
 * Return a positive value if pix_fmt is a supported input format, 0
 * otherwise.
 *)
function sws_isSupportedInput(pix_fmt: TAVPixelFormat): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_isSupportedInput';

(**
 * Return a positive value if pix_fmt is a supported output format, 0
 * otherwise.
 *)
function sws_isSupportedOutput(pix_fmt: TAVPixelFormat): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_isSupportedOutput';

(**
 * @param[in]  pix_fmt the pixel format
 * @return a positive value if an endianness conversion for pix_fmt is
 * supported, 0 otherwise.
 *)
function sws_isSupportedEndiannessConversion(pix_fmt: TAVPixelFormat): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_isSupportedEndiannessConversion';

(**
 * Initialize the swscaler context sws_context.
 *
 * This function is considered deprecated, and provided only for backwards
 * compatibility with sws_scale() and sws_start_frame(). The preferred way to
 * use libswscale is to set all frame properties correctly and call
 * sws_scale_frame() directly, without explicitly initializing the context.
 *
 * @return zero or positive value on success, a negative value on
 * error
 *)
function sws_init_context(sws_context: PSwsContext; srcFilter, dstFilter: PSwsFilter): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_init_context';

(**
 * Free the swscaler context swsContext.
 * If swsContext is NULL, then does nothing.
 *)
procedure sws_freeContext(swsContext: PSwsContext); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_freeContext';

(**
 * Allocate and return an SwsContext. You need it to perform
 * scaling/conversion operations using sws_scale().
 *
 * @param srcW the width of the source image
 * @param srcH the height of the source image
 * @param srcFormat the source image format
 * @param dstW the width of the destination image
 * @param dstH the height of the destination image
 * @param dstFormat the destination image format
 * @param flags specify which algorithm and options to use for rescaling
 * @param param extra parameters to tune the used scaler
 *              For SWS_BICUBIC param[0] and [1] tune the shape of the basis
 *              function, param[0] tunes f(1) and param[1] f'(1)
 *              For SWS_GAUSS param[0] tunes the exponent and thus cutoff
 *              frequency
 *              For SWS_LANCZOS param[0] tunes the width of the window function
 * @return a pointer to an allocated context, or NULL in case of error
 * @note this function is to be removed after a saner alternative is
 *       written
 *)
function sws_getContext(srcW, srcH: Integer; srcFormat: TAVPixelFormat;
                                  dstW, dstH: Integer; dstFormat: TAVPixelFormat;
                                  flags: Integer; srcFilter, dstFilter: PSwsFilter;
                                  param: PDouble): PSwsContext; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_getContext';

(**
 * Scale the image slice in srcSlice and put the resulting scaled
 * slice in the image in dst. A slice is a sequence of consecutive
 * rows in an image. Requires a context that has been previously
 * been initialized with sws_init_context().
 *
 * Slices have to be provided in sequential order, either in
 * top-bottom or bottom-top order. If slices are provided in
 * non-sequential order the behavior of the function is undefined.
 *
 * @param c         the scaling context previously created with
 *                  sws_getContext()
 * @param srcSlice  the array containing the pointers to the planes of
 *                  the source slice
 * @param srcStride the array containing the strides for each plane of
 *                  the source image
 * @param srcSliceY the position in the source image of the slice to
 *                  process, that is the number (counted starting from
 *                  zero) in the image of the first row of the slice
 * @param srcSliceH the height of the source slice, that is the number
 *                  of rows in the slice
 * @param dst       the array containing the pointers to the planes of
 *                  the destination image
 * @param dstStride the array containing the strides for each plane of
 *                  the destination image
 * @return          the height of the output slice
 *)
function sws_scale(c: PSwsContext; const srcSlice: PPByte;
                    const srcStride: PInteger; srcSliceY, srcSliceH: Integer;
                    const dst: PPByte; const dstStride: PInteger): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_scale';

(**
 * Initialize the scaling process for a given pair of source/destination frames.
 * Must be called before any calls to sws_send_slice() and sws_receive_slice().
 * Requires a context that has been previously been initialized with
 * sws_init_context().
 *
 * This function will retain references to src and dst, so they must both use
 * refcounted buffers (if allocated by the caller, in case of dst).
 *
 * @param c   The scaling context
 * @param dst The destination frame.
 *
 *            The data buffers may either be already allocated by the caller or
 *            left clear, in which case they will be allocated by the scaler.
 *            The latter may have performance advantages - e.g. in certain cases
 *            some output planes may be references to input planes, rather than
 *            copies.
 *
 *            Output data will be written into this frame in successful
 *            sws_receive_slice() calls.
 * @param src The source frame. The data buffers must be allocated, but the
 *            frame data does not have to be ready at this point. Data
 *            availability is then signalled by sws_send_slice().
 * @return 0 on success, a negative AVERROR code on failure
 *
 * @see sws_frame_end()
 *)
function sws_frame_start(c: PSwsContext; dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_frame_start';

(**
 * Finish the scaling process for a pair of source/destination frames previously
 * submitted with sws_frame_start(). Must be called after all sws_send_slice()
 * and sws_receive_slice() calls are done, before any new sws_frame_start()
 * calls.
 *
 * @param c   The scaling context
 *)
procedure sws_frame_end(c: PSwsContext); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_frame_end';

(**
 * Indicate that a horizontal slice of input data is available in the source
 * frame previously provided to sws_frame_start(). The slices may be provided in
 * any order, but may not overlap. For vertically subsampled pixel formats, the
 * slices must be aligned according to subsampling.
 *
 * @param c   The scaling context
 * @param slice_start first row of the slice
 * @param slice_height number of rows in the slice
 *
 * @return a non-negative number on success, a negative AVERROR code on failure.
 *)
function sws_send_slice(c: PSwsContext; slice_start, slice_height: Cardinal): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_send_slice';

(**
 * Request a horizontal slice of the output data to be written into the frame
 * previously provided to sws_frame_start().
 *
 * @param c   The scaling context
 * @param slice_start first row of the slice; must be a multiple of
 *                    sws_receive_slice_alignment()
 * @param slice_height number of rows in the slice; must be a multiple of
 *                     sws_receive_slice_alignment(), except for the last slice
 *                     (i.e. when slice_start+slice_height is equal to output
 *                     frame height)
 *
 * @return a non-negative number if the data was successfully written into the output
 *         AVERROR(EAGAIN) if more input data needs to be provided before the
 *                         output can be produced
 *         another negative AVERROR code on other kinds of scaling failure
 *)
function sws_receive_slice(c: PSwsContext; slice_start, slice_height: Cardinal): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_receive_slice';

(**
 * Get the alignment required for slices. Requires a context that has been
 * previously been initialized with sws_init_context().
 *
 * @param c   The scaling context
 * @return alignment required for output slices requested with sws_receive_slice().
 *         Slice offsets and sizes passed to sws_receive_slice() must be
 *         multiples of the value returned from this function.
 *)
function sws_receive_slice_alignment(const c: PSwsContext): Cardinal; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_receive_slice_alignment';

(**
 * @param c the scaling context
 * @param dstRange flag indicating the while-black range of the output (1=jpeg / 0=mpeg)
 * @param srcRange flag indicating the while-black range of the input (1=jpeg / 0=mpeg)
 * @param table the yuv2rgb coefficients describing the output yuv space, normally ff_yuv2rgb_coeffs[x]
 * @param inv_table the yuv2rgb coefficients describing the input yuv space, normally ff_yuv2rgb_coeffs[x]
 * @param brightness 16.16 fixed point brightness correction
 * @param contrast 16.16 fixed point contrast correction
 * @param saturation 16.16 fixed point saturation correction
 *
 * @return A negative error code on error, non negative otherwise.
 *         If `LIBSWSCALE_VERSION_MAJOR < 7`, returns -1 if not supported.
 *)
function sws_setColorspaceDetails(c: PSwsContext; inv_table: PInteger(*array{[0..3]} of Integer*);
                             srcRange: Integer; table: PInteger(*array{[0..3]} of Integer*); dstRange: Integer;
                             brightness, contrast, saturation: Integer): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_setColorspaceDetails';

(**
 * @return A negative error code on error, non negative otherwise.
 *         If `LIBSWSCALE_VERSION_MAJOR < 7`, returns -1 if not supported.
 *)
function sws_getColorspaceDetails(c: PSwsContext; inv_table: PPInteger; srcRange: PInteger; table: PPInteger; dstRange, brightness, contrast, saturation: PInteger): Integer; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_getColorspaceDetails';

(**
 * Allocate and return an uninitialized vector with length coefficients.
 *)
function sws_allocVec(length: Integer): PSwsVector; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_allocVec';

(**
 * Return a normalized Gaussian curve used to filter stuff
 * quality = 3 is high quality, lower is lower quality.
 *)
function sws_getGaussianVec(variance, quality: Double): PSwsVector; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_getGaussianVec';

(**
 * Scale all the coefficients of a by the scalar value.
 *)
procedure sws_scaleVec(a: PSwsVector; scalar: Double); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_scaleVec';

(**
 * Scale all the coefficients of a so that their sum equals height.
 *)
procedure sws_normalizeVec(a: PSwsVector; height: Double); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_normalizeVec';

procedure sws_freeVec(a: PSwsVector); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_freeVec';

function sws_getDefaultFilter(lumaGBlur, chromaGBlur,
                                lumaSharpen, chromaSharpen,
                                chromaHShift, chromaVShift: Single;
                                verbose: Integer): PSwsFilter; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_getDefaultFilter';
procedure sws_freeFilter(filter: PSwsFilter); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_freeFilter';

(**
 * Check if context can be reused, otherwise reallocate a new one.
 *
 * If context is NULL, just calls sws_getContext() to get a new
 * context. Otherwise, checks if the parameters are the ones already
 * saved in context. If that is the case, returns the current
 * context. Otherwise, frees context and gets a new context with
 * the new parameters.
 *
 * Be warned that srcFilter and dstFilter are not checked, they
 * are assumed to remain the same.
 *)
function sws_getCachedContext(context: PSwsContext; srcW: Integer; srcH: Integer;
                                 srcFormat: TAVPixelFormat; dstW: Integer; dstH: Integer;
                                 dstFormat: TAVPixelFormat; flags: Integer;
                                 srcFilter: PSwsFilter; dstFilter: PSwsFilter;
                                 const param: PDouble): PSwsContext; cdecl; external SWSCALE_LIBNAME name _PU + 'sws_getCachedContext';

(**
 * Convert an 8-bit paletted frame into a frame with a color depth of 32 bits.
 *
 * The output frame will have the same packed format as the palette.
 *
 * @param src        source frame buffer
 * @param dst        destination frame buffer
 * @param num_pixels number of pixels to convert
 * @param palette    array with [256] entries, which must match color arrangement (RGB or BGR) of src
 *)
procedure sws_convertPalette8ToPacked32(src, dst: PByte; num_pixels: Integer; palette: PByte); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_convertPalette8ToPacked32';

(**
 * Convert an 8-bit paletted frame into a frame with a color depth of 24 bits.
 *
 * With the palette format "ABCD", the destination frame ends up with the format "ABC".
 *
 * @param src        source frame buffer
 * @param dst        destination frame buffer
 * @param num_pixels number of pixels to convert
 * @param palette    array with [256] entries, which must match color arrangement (RGB or BGR) of src
 *)
procedure sws_convertPalette8ToPacked24(src, dst: PByte; num_pixels: Integer; palette: PByte); cdecl; external SWSCALE_LIBNAME name _PU + 'sws_convertPalette8ToPacked24';

(**
 * @}
 *)

implementation

end.
