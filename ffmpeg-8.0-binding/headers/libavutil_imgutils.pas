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
 * misc image utilities
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavcore/imgutils.h
 * Ported by CodeCoolie@CNSW 2010/09/17 -> 2011-01-21
 * Original file: libavutil/imgutils.h
 * Ported by CodeCoolie@CNSW 2011/07/02 -> $Date:: 2024-07-28 #$
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

unit libavutil_imgutils;

interface

{$I CompilerDefines.inc}

uses
  libavutil_pixdesc,
  libavutil_pixfmt,
  libavutil_rational,
  FFTypes;

{$I libversion.inc}

(**
 * @addtogroup lavu_picture
 * @{
 *)

(**
 * Compute the max pixel step for each plane of an image with a
 * format described by pixdesc.
 *
 * The pixel step is the distance in bytes between the first byte of
 * the group of bytes which describe a pixel component and the first
 * byte of the successive group in the same plane for the same
 * component.
 *
 * @param max_pixsteps an array which is filled with the max pixel step
 * for each plane. Since a plane may contain different pixel
 * components, the computed max_pixsteps[plane] is relative to the
 * component in the plane with the max pixel step.
 * @param max_pixstep_comps an array which is filled with the component
 * for each plane which has the max pixel step. May be NULL.
 * @param pixdesc the AVPixFmtDescriptor for the image, describing its format
 *)
procedure av_image_fill_max_pixsteps(max_pixsteps, max_pixstep_comps: PInteger{array[0..3] of Integer};
                                              const pixdesc: PAVPixFmtDescriptor); cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_max_pixsteps';

(**
 * Compute the size of an image line with format pix_fmt and width
 * width for the plane plane.
 *
 * @return the computed size in bytes
 *)
function av_image_get_linesize(pix_fmt: TAVPixelFormat; width, plane: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_get_linesize';

(**
 * Fill plane linesizes for an image with pixel format pix_fmt and
 * width width.
 *
 * @param linesizes array to be filled with the linesize for each plane
 * @param pix_fmt the AVPixelFormat of the image
 * @param width width of the image in pixels
 * @return >= 0 in case of success, a negative error code otherwise
 *)
function av_image_fill_linesizes(linesizes: PInteger{array[0..3] of Integer}; pix_fmt: TAVPixelFormat; width: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_linesizes';

(**
 * Fill plane sizes for an image with pixel format pix_fmt and height height.
 *
 * @param size the array to be filled with the size of each image plane
 * @param pix_fmt the AVPixelFormat of the image
 * @param height height of the image in pixels
 * @param linesizes the array containing the linesize for each
 *        plane, should be filled by av_image_fill_linesizes()
 * @return >= 0 in case of success, a negative error code otherwise
 *
 * @note The linesize parameters have the type ptrdiff_t here, while they are
 *       int for av_image_fill_linesizes().
 *)
function av_image_fill_plane_sizes(size: PSize_t{array[0..3] of Size_t}; pix_fmt: TAVPixelFormat;
                             height: Integer; const linesizes: PNativeInt{array[0..3] of ptrdiff_t}): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_plane_sizes';

(**
 * Fill plane data pointers for an image with pixel format pix_fmt and
 * height height.
 *
 * @param data pointers array to be filled with the pointer for each image plane
 * @param pix_fmt the AVPixelFormat of the image
 * @param height height of the image in pixels
 * @param ptr the pointer to a buffer which will contain the image
 * @param linesizes the array containing the linesize for each
 * plane, should be filled by av_image_fill_linesizes()
 * @return the size in bytes required for the image buffer, a negative
 * error code in case of failure
 *)
function av_image_fill_pointers(data: PPByte{array[0..3] of PByte}; pix_fmt: TAVPixelFormat; height: Integer;
                                         ptr: PByte; linesizes: PInteger{array[0..3] of Integer}): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_pointers';

(**
 * Allocate an image with size w and h and pixel format pix_fmt, and
 * fill pointers and linesizes accordingly.
 * The allocated image buffer has to be freed by using
 * av_freep(&pointers[0]).
 *
 * @param pointers array to be filled with the pointer for each image plane
 * @param linesizes the array filled with the linesize for each plane
 * @param w width of the image in pixels
 * @param h height of the image in pixels
 * @param pix_fmt the AVPixelFormat of the image
 * @param align the value to use for buffer size alignment
 * @return the size in bytes required for the image buffer, a negative
 * error code in case of failure
 *)
function av_image_alloc(pointers: PPByte{array[0..3] of PByte}; linesizes: PInteger{array[0..3] of Integer};
                   w, h: Integer; pix_fmt: TAVPixelFormat; align: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_alloc';

(**
 * Copy image plane from src to dst.
 * That is, copy "height" number of lines of "bytewidth" bytes each.
 * The first byte of each successive line is separated by *_linesize
 * bytes.
 *
 * bytewidth must be contained by both absolute values of dst_linesize
 * and src_linesize, otherwise the function behavior is undefined.
 *
 * @param dst          destination plane to copy to
 * @param dst_linesize linesize for the image plane in dst
 * @param src          source plane to copy from
 * @param src_linesize linesize for the image plane in src
 * @param height       height (number of lines) of the plane
 *)
procedure av_image_copy_plane(dst: PByte; dst_linesize: Integer;
                                       const src: PByte; src_linesize: Integer;
                                       bytewidth, height: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_copy_plane';

(**
 * Copy image data located in uncacheable (e.g. GPU mapped) memory. Where
 * available, this function will use special functionality for reading from such
 * memory, which may result in greatly improved performance compared to plain
 * av_image_copy_plane().
 *
 * bytewidth must be contained by both absolute values of dst_linesize
 * and src_linesize, otherwise the function behavior is undefined.
 *
 * @note The linesize parameters have the type ptrdiff_t here, while they are
 *       int for av_image_copy_plane().
 * @note On x86, the linesizes currently need to be aligned to the cacheline
 *       size (i.e. 64) to get improved performance.
 *)
procedure av_image_copy_plane_uc_from(dst: PByte; dst_linesize: NativeInt{ptrdiff_t};
                                 const src: PByte; src_linesize: NativeInt{ptrdiff_t};
                                 bytewidth: NativeInt{ptrdiff_t}; height: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_copy_plane_uc_from';

(**
 * Copy image in src_data to dst_data.
 *
 * @param dst_data      destination image data buffer to copy to
 * @param dst_linesizes linesizes for the image in dst_data
 * @param src_data      source image data buffer to copy from
 * @param src_linesizes linesizes for the image in src_data
 * @param pix_fmt       the AVPixelFormat of the image
 * @param width         width of the image in pixels
 * @param height        height of the image in pixels
 *)
procedure av_image_copy(dst_data: PPByte{array[0..3] of PByte}; dst_linesizes: PInteger{array[0..3] of Integer};
                                 const src_data: PPByte{array[0..3] of PByte}; const src_linesizes: PInteger{array[0..3] of Integer};
                                 pix_fmt: TAVPixelFormat; width, height: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_copy';

(**
 * Wrapper around av_image_copy() to workaround the limitation
 * that the conversion from uint8_t * const * to const uint8_t * const *
 * is not performed automatically in C.
 * @see av_image_copy()
 *)
//static inline
//void av_image_copy2(uint8_t * const dst_data[4], const int dst_linesizes[4],
//                    uint8_t * const src_data[4], const int src_linesizes[4],
//                    enum AVPixelFormat pix_fmt, int width, int height)
{
    av_image_copy(dst_data, dst_linesizes,
                  (const uint8_t * const *)src_data, src_linesizes,
                  pix_fmt, width, height);
}

(**
 * Copy image data located in uncacheable (e.g. GPU mapped) memory. Where
 * available, this function will use special functionality for reading from such
 * memory, which may result in greatly improved performance compared to plain
 * av_image_copy().
 *
 * The data pointers and the linesizes must be aligned to the maximum required
 * by the CPU architecture.
 *
 * @note The linesize parameters have the type ptrdiff_t here, while they are
 *       int for av_image_copy().
 * @note On x86, the linesizes currently need to be aligned to the cacheline
 *       size (i.e. 64) to get improved performance.
 *)
procedure av_image_copy_uc_from(dst_data: PPByte{array[0..3] of PByte}; const dst_linesizes: PNativeInt{array[0..3] of NativeInt}{ptrdiff_t};
                           const src_data: PPByte{array[0..3] of PByte}; const src_linesizes: PNativeInt{array[0..3] of NativeInt}{ptrdiff_t};
                           pix_fmt: TAVPixelFormat; width, height: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_copy_uc_from';

(**
 * Setup the data pointers and linesizes based on the specified image
 * parameters and the provided array.
 *
 * The fields of the given image are filled in by using the src
 * address which points to the image data buffer. Depending on the
 * specified pixel format, one or multiple image data pointers and
 * line sizes will be set.  If a planar format is specified, several
 * pointers will be set pointing to the different picture planes and
 * the line sizes of the different planes will be stored in the
 * lines_sizes array. Call with src == NULL to get the required
 * size for the src buffer.
 *
 * To allocate the buffer and fill in the dst_data and dst_linesize in
 * one call, use av_image_alloc().
 *
 * @param dst_data      data pointers to be filled in
 * @param dst_linesize  linesizes for the image in dst_data to be filled in
 * @param src           buffer which will contain or contains the actual image data, can be NULL
 * @param pix_fmt       the pixel format of the image
 * @param width         the width of the image in pixels
 * @param height        the height of the image in pixels
 * @param align         the value used in src for linesize alignment
 * @return the size in bytes required for src, a negative error code
 * in case of failure
 *)
function av_image_fill_arrays(dst_data: PPByte{array[0..3] of PByte}; dst_linesize: PInteger{array[0..3] of Integer};
                                        const src: PByte; pix_fmt: TAVPixelFormat;
                                        width, height, align: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_arrays';

(**
 * Return the size in bytes of the amount of data required to store an
 * image with the given parameters.
 *
 * @param pix_fmt  the pixel format of the image
 * @param width    the width of the image in pixels
 * @param height   the height of the image in pixels
 * @param align    the assumed linesize alignment
 * @return the buffer size in bytes, a negative error code in case of failure
 *)
function av_image_get_buffer_size(pix_fmt: TAVPixelFormat; width, height, align: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_get_buffer_size';

(**
 * Copy image data from an image into a buffer.
 *
 * av_image_get_buffer_size() can be used to compute the required size
 * for the buffer to fill.
 *
 * @param dst           a buffer into which picture data will be copied
 * @param dst_size      the size in bytes of dst
 * @param src_data      pointers containing the source image data
 * @param src_linesize  linesizes for the image in src_data
 * @param pix_fmt       the pixel format of the source image
 * @param width         the width of the source image in pixels
 * @param height        the height of the source image in pixels
 * @param align         the assumed linesize alignment for dst
 * @return the number of bytes written to dst, or a negative value
 * (error code) on error
 *)
function av_image_copy_to_buffer(dst: PByte; dst_size: Integer;
                            const src_data: PPByte{array[0..3] of PByte}; const src_linesize: PInteger{array[0..3] of Integer};
                            pix_fmt: TAVPixelFormat; width, height, align: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_copy_to_buffer';

(**
 * Check if the given dimension of an image is valid, meaning that all
 * bytes of the image can be addressed with a signed int.
 *
 * @param w the width of the picture
 * @param h the height of the picture
 * @param log_offset the offset to sum to the log level for logging with log_ctx
 * @param log_ctx the parent logging context, it may be NULL
 * @return >= 0 if valid, a negative error code otherwise
 *)
function av_image_check_size(w, h: Cardinal; log_offset: Integer; log_ctx: Pointer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_check_size';

(**
 * Check if the given dimension of an image is valid, meaning that all
 * bytes of a plane of an image with the specified pix_fmt can be addressed
 * with a signed int.
 *
 * @param w the width of the picture
 * @param h the height of the picture
 * @param max_pixels the maximum number of pixels the user wants to accept
 * @param pix_fmt the pixel format, can be AV_PIX_FMT_NONE if unknown.
 * @param log_offset the offset to sum to the log level for logging with log_ctx
 * @param log_ctx the parent logging context, it may be NULL
 * @return >= 0 if valid, a negative error code otherwise
 *)
function av_image_check_size2(w, h: Cardinal; max_pixels: Int64; pix_fmt: TAVPixelFormat; log_offset: Integer; log_ctx: Pointer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_check_size2';

(**
 * Check if the given sample aspect ratio of an image is valid.
 *
 * It is considered invalid if the denominator is 0 or if applying the ratio
 * to the image size would make the smaller dimension less than 1. If the
 * sar numerator is 0, it is considered unknown and will return as valid.
 *
 * @param w width of the image
 * @param h height of the image
 * @param sar sample aspect ratio of the image
 * @return 0 if valid, a negative AVERROR code otherwise
 *)
function av_image_check_sar(w, h: Cardinal; sar: TAVRational): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_check_sar';

(**
 * Overwrite the image data with black. This is suitable for filling a
 * sub-rectangle of an image, meaning the padding between the right most pixel
 * and the left most pixel on the next line will not be overwritten. For some
 * formats, the image size might be rounded up due to inherent alignment.
 *
 * If the pixel format has alpha, the alpha is cleared to opaque.
 *
 * This can return an error if the pixel format is not supported. Normally, all
 * non-hwaccel pixel formats should be supported.
 *
 * Passing NULL for dst_data is allowed. Then the function returns whether the
 * operation would have succeeded. (It can return an error if the pix_fmt is
 * not supported.)
 *
 * @param dst_data      data pointers to destination image
 * @param dst_linesize  linesizes for the destination image
 * @param pix_fmt       the pixel format of the image
 * @param range         the color range of the image (important for colorspaces such as YUV)
 * @param width         the width of the image in pixels
 * @param height        the height of the image in pixels
 * @return 0 if the image data was cleared, a negative AVERROR code otherwise
 *)
function av_image_fill_black(dst_data: PPByte{array[0..3] of PByte}; const dst_linesize: PNativeInt{array[0..3] of NativeInt}{ptrdiff_t};
                        pix_fmt: TAVPixelFormat; range: TAVColorRange;
                        width, height: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_black';

(**
 * Overwrite the image data with a color. This is suitable for filling a
 * sub-rectangle of an image, meaning the padding between the right most pixel
 * and the left most pixel on the next line will not be overwritten. For some
 * formats, the image size might be rounded up due to inherent alignment.
 *
 * If the pixel format has alpha, it is also replaced. Color component values
 * are interpreted as native integers (or intfloats) regardless of actual pixel
 * format endianness.
 *
 * This can return an error if the pixel format is not supported. Normally, all
 * non-hwaccel pixel formats should be supported.
 *
 * Passing NULL for dst_data is allowed. Then the function returns whether the
 * operation would have succeeded. (It can return an error if the pix_fmt is
 * not supported.)
 *
 * @param dst_data      data pointers to destination image
 * @param dst_linesize  linesizes for the destination image
 * @param pix_fmt       the pixel format of the image
 * @param color         the color components to be used for the fill
 * @param width         the width of the image in pixels
 * @param height        the height of the image in pixels
 * @param flags         currently unused
 * @return 0 if the image data was filled, a negative AVERROR code otherwise
 *)
function av_image_fill_color(dst_data: PPByte{array[0..3] of PByte}; const dst_linesize: PNativeInt{array[0..3] of NativeInt}{ptrdiff_t};
                        pix_fmt: TAVPixelFormat; const color: PCardinal{array[0..3] of Cardinal}{uint32_t};
                        width: Integer; height: Integer; flags: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_image_fill_color';

(**
 * @}
 *)

procedure av_image_copy2(dst_data: PPByte; const dst_linesizes: PInteger;
  const src_data: PPByte; const src_linesizes: PInteger;
  pix_fmt: TAVPixelFormat; width, height: Integer); {$IFDEF USE_INLINE}inline;{$ENDIF}

implementation


procedure av_image_copy2(dst_data: PPByte; const dst_linesizes: PInteger;
  const src_data: PPByte; const src_linesizes: PInteger;
  pix_fmt: TAVPixelFormat; width, height: Integer);
begin
  av_image_copy(dst_data, dst_linesizes,
                src_data, src_linesizes,
                pix_fmt, width, height);
end;

end.
