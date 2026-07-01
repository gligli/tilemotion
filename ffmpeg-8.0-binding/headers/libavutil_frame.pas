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
 * @ingroup lavu_frame
 * reference-counted frame API
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/frame.h
 * Ported by CodeCoolie@CNSW 2013/10/22 -> $Date:: 2025-11-04 #$
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

unit libavutil_frame;

interface

{$I CompilerDefines.inc}

uses
  libavutil,
  libavutil_buffer,
  libavutil_channel_layout,
  libavutil_dict,
  libavutil_pixfmt,
  libavutil_rational,
  FFTypes;

{$I libversion.inc}

const
  AV_NUM_DATA_POINTERS = 8;
  AV_FRAME_FLAG_CORRUPT     =  (1 shl 0);
  AV_FRAME_FLAG_KEY         =  (1 shl 1);
  AV_FRAME_FLAG_DISCARD     =  (1 shl 2);
  AV_FRAME_FLAG_INTERLACED  =  (1 shl 3);
  AV_FRAME_FLAG_TOP_FIELD_FIRST = (1 shl 4);
  AV_FRAME_FLAG_LOSSLESS        = (1 shl 5);
  FF_DECODE_ERROR_INVALID_BITSTREAM = 1;
  FF_DECODE_ERROR_MISSING_REFERENCE = 2;
  FF_DECODE_ERROR_CONCEALMENT_ACTIVE = 4;
  FF_DECODE_ERROR_DECODE_SLICES      = 8;

type
(**
 * @defgroup lavu_frame AVFrame
 * @ingroup lavu_data
 *
 * @{
 * AVFrame is an abstraction for reference-counted raw multimedia data.
 *)

  TAVFrameSideDataType = (
    (**
     * The data is the AVPanScan struct defined in libavcodec.
     *)
    AV_FRAME_DATA_PANSCAN,
    (**
     * ATSC A53 Part 4 Closed Captions.
     * A53 CC bitstream is stored as uint8_t in AVFrameSideData.data.
     * The number of bytes of CC data is AVFrameSideData.size.
     *)
    AV_FRAME_DATA_A53_CC,
    (**
     * Stereoscopic 3d metadata.
     * The data is the AVStereo3D struct defined in libavutil/stereo3d.h.
     *)
    AV_FRAME_DATA_STEREO3D,
    (**
     * The data is the AVMatrixEncoding enum defined in libavutil/channel_layout.h.
     *)
    AV_FRAME_DATA_MATRIXENCODING,
    (**
     * Metadata relevant to a downmix procedure.
     * The data is the AVDownmixInfo struct defined in libavutil/downmix_info.h.
     *)
    AV_FRAME_DATA_DOWNMIX_INFO,
    (**
     * ReplayGain information in the form of the AVReplayGain struct.
     *)
    AV_FRAME_DATA_REPLAYGAIN,
    (**
     * This side data contains a 3x3 transformation matrix describing an affine
     * transformation that needs to be applied to the frame for correct
     * presentation.
     *
     * See libavutil/display.h for a detailed description of the data.
     *)
    AV_FRAME_DATA_DISPLAYMATRIX,
    (**
     * Active Format Description data consisting of a single byte as specified
     * in ETSI TS 101 154 using AVActiveFormatDescription enum.
     *)
    AV_FRAME_DATA_AFD,
    (**
     * Motion vectors exported by some codecs (on demand through the export_mvs
     * flag set in the libavcodec AVCodecContext flags2 option).
     * The data is the AVMotionVector struct defined in
     * libavutil/motion_vector.h.
     *)
    AV_FRAME_DATA_MOTION_VECTORS,
    (**
     * Recommends skipping the specified number of samples. This is exported
     * only if the "skip_manual" AVOption is set in libavcodec.
     * This has the same format as AV_PKT_DATA_SKIP_SAMPLES.
     * @code
     * u32le number of samples to skip from start of this packet
     * u32le number of samples to skip from end of this packet
     * u8    reason for start skip
     * u8    reason for end   skip (0=padding silence, 1=convergence)
     * @endcode
     *)
    AV_FRAME_DATA_SKIP_SAMPLES,
    (**
     * This side data must be associated with an audio frame and corresponds to
     * enum AVAudioServiceType defined in avcodec.h.
     *)
    AV_FRAME_DATA_AUDIO_SERVICE_TYPE,
    (**
     * Mastering display metadata associated with a video frame. The payload is
     * an AVMasteringDisplayMetadata type and contains information about the
     * mastering display color volume.
     *)
    AV_FRAME_DATA_MASTERING_DISPLAY_METADATA,
    (**
     * The GOP timecode in 25 bit timecode format. Data format is 64-bit integer.
     * This is set on the first frame of a GOP that has a temporal reference of 0.
     *)
    AV_FRAME_DATA_GOP_TIMECODE,

    (**
     * The data represents the AVSphericalMapping structure defined in
     * libavutil/spherical.h.
     *)
    AV_FRAME_DATA_SPHERICAL,

    (**
     * Content light level (based on CTA-861.3). This payload contains data in
     * the form of the AVContentLightMetadata struct.
     *)
    AV_FRAME_DATA_CONTENT_LIGHT_LEVEL,

    (**
     * The data contains an ICC profile as an opaque octet buffer following the
     * format described by ISO 15076-1 with an optional name defined in the
     * metadata key entry "name".
     *)
    AV_FRAME_DATA_ICC_PROFILE,

    (**
     * Timecode which conforms to SMPTE ST 12-1. The data is an array of 4 uint32_t
     * where the first uint32_t describes how many (1-3) of the other timecodes are used.
     * The timecode format is described in the documentation of av_timecode_get_smpte_from_framenum()
     * function in libavutil/timecode.h.
     *)
    AV_FRAME_DATA_S12M_TIMECODE,

    (**
     * HDR dynamic metadata associated with a video frame. The payload is
     * an AVDynamicHDRPlus type and contains information for color
     * volume transform - application 4 of SMPTE 2094-40:2016 standard.
     *)
    AV_FRAME_DATA_DYNAMIC_HDR_PLUS,

    (**
     * Regions Of Interest, the data is an array of AVRegionOfInterest type, the number of
     * array element is implied by AVFrameSideData.size / AVRegionOfInterest.self_size.
     *)
    AV_FRAME_DATA_REGIONS_OF_INTEREST,

    (**
     * Encoding parameters for a video frame, as described by AVVideoEncParams.
     *)
    AV_FRAME_DATA_VIDEO_ENC_PARAMS,

    (**
     * User data unregistered metadata associated with a video frame.
     * This is the H.26[45] UDU SEI message, and shouldn't be used for any other purpose
     * The data is stored as uint8_t in AVFrameSideData.data which is 16 bytes of
     * uuid_iso_iec_11578 followed by AVFrameSideData.size - 16 bytes of user_data_payload_byte.
     *)
    AV_FRAME_DATA_SEI_UNREGISTERED,

    (**
     * Film grain parameters for a frame, described by AVFilmGrainParams.
     * Must be present for every frame which should have film grain applied.
     *
     * May be present multiple times, for example when there are multiple
     * alternative parameter sets for different video signal characteristics.
     * The user should select the most appropriate set for the application.
     *)
    AV_FRAME_DATA_FILM_GRAIN_PARAMS,

    (**
     * Bounding boxes for object detection and classification,
     * as described by AVDetectionBBoxHeader.
     *)
    AV_FRAME_DATA_DETECTION_BBOXES,

    (**
     * Dolby Vision RPU raw data, suitable for passing to x265
     * or other libraries. Array of uint8_t, with NAL emulation
     * bytes intact.
     *)
    AV_FRAME_DATA_DOVI_RPU_BUFFER,

    (**
     * Parsed Dolby Vision metadata, suitable for passing to a software
     * implementation. The payload is the AVDOVIMetadata struct defined in
     * libavutil/dovi_meta.h.
     *)
    AV_FRAME_DATA_DOVI_METADATA,

    (**
     * HDR Vivid dynamic metadata associated with a video frame. The payload is
     * an AVDynamicHDRVivid type and contains information for color
     * volume transform - CUVA 005.1-2021.
     *)
    AV_FRAME_DATA_DYNAMIC_HDR_VIVID,

    (**
     * Ambient viewing environment metadata, as defined by H.274.
     *)
    AV_FRAME_DATA_AMBIENT_VIEWING_ENVIRONMENT,

    (**
     * Provide encoder-specific hinting information about changed/unchanged
     * portions of a frame.  It can be used to pass information about which
     * macroblocks can be skipped because they didn't change from the
     * corresponding ones in the previous frame. This could be useful for
     * applications which know this information in advance to speed up
     * encoding.
     *)
    AV_FRAME_DATA_VIDEO_HINT,

    (**
     * Raw LCEVC payload data, as a uint8_t array, with NAL emulation
     * bytes intact.
     *)
    AV_FRAME_DATA_LCEVC,

    (**
     * This side data must be associated with a video frame.
     * The presence of this side data indicates that the video stream is
     * composed of multiple views (e.g. stereoscopic 3D content,
     * cf. H.264 Annex H or H.265 Annex G).
     * The data is an int storing the view ID.
     *)
    AV_FRAME_DATA_VIEW_ID,

    (**
     * This side data contains information about the reference display width(s)
     * and reference viewing distance(s) as well as information about the
     * corresponding reference stereo pair(s), i.e., the pair(s) of views to be
     * displayed for the viewer's left and right eyes on the reference display
     * at the reference viewing distance.
     * The payload is the AV3DReferenceDisplaysInfo struct defined in
     * libavutil/tdrdi.h.
     *)
    AV_FRAME_DATA_3D_REFERENCE_DISPLAYS
  );

  TAVActiveFormatDescription = (
    AV_AFD_SAME         = 8,
    AV_AFD_4_3          = 9,
    AV_AFD_16_9         = 10,
    AV_AFD_14_9         = 11,
    AV_AFD_4_3_SP_14_9  = 13,
    AV_AFD_16_9_SP_14_9 = 14,
    AV_AFD_SP_4_3       = 15
  );

(**
 * Structure to hold side data for an AVFrame.
 *
 * sizeof(AVFrameSideData) is not a part of the public ABI, so new fields may be added
 * to the end with a minor bump.
 *)
  PPPAVFrameSideData = ^PPAVFrameSideData;
  PPAVFrameSideData = ^PAVFrameSideData;
  PAVFrameSideData = ^TAVFrameSideData;
  TAVFrameSideData = record
    type_: TAVFrameSideDataType;
    data: PByte;
    size: Size_t;
    metadata: PAVDictionary;
    buf: PAVBufferRef;
  end;

  TAVSideDataProps = (
    (**
     * The side data type can be used in stream-global structures.
     * Side data types without this property are only meaningful on per-frame
     * basis.
     *)
    AV_SIDE_DATA_PROP_GLOBAL = (1 shl 0),

    (**
     * Multiple instances of this side data type can be meaningfully present in
     * a single side data array.
     *)
    AV_SIDE_DATA_PROP_MULTI  = (1 shl 1),

    (**
     * Side data depends on the video dimensions. Side data with this property
     * loses its meaning when rescaling or cropping the image, unless
     * either recomputed or adjusted to the new resolution.
     *)
    AV_SIDE_DATA_PROP_SIZE_DEPENDENT = (1 shl 2),

    (**
     * Side data depends on the video color space. Side data with this property
     * loses its meaning when changing the video color encoding, e.g. by
     * adapting to a different set of primaries or transfer characteristics.
     *)
    AV_SIDE_DATA_PROP_COLOR_DEPENDENT = (1 shl 3),

    (**
     * Side data depends on the channel layout. Side data with this property
     * loses its meaning when downmixing or upmixing, unless either recomputed
     * or adjusted to the new layout.
     *)
    AV_SIDE_DATA_PROP_CHANNEL_DEPENDENT = (1 shl 4)
  );

(**
 * This struct describes the properties of a side data type. Its instance
 * corresponding to a given type can be obtained from av_frame_side_data_desc().
 *)
  PAVSideDataDescriptor = ^TAVSideDataDescriptor;
  TAVSideDataDescriptor = record
    (**
     * Human-readable side data description.
     *)
    name: PAnsiChar;

    (**
     * Side data property flags, a combination of AVSideDataProps values.
     *)
    props: Cardinal;
  end;

(**
 * Structure describing a single Region Of Interest.
 *
 * When multiple regions are defined in a single side-data block, they
 * should be ordered from most to least important - some encoders are only
 * capable of supporting a limited number of distinct regions, so will have
 * to truncate the list.
 *
 * When overlapping regions are defined, the first region containing a given
 * area of the frame applies.
 *)
  TAVRegionOfInterest = record
    (**
     * Must be set to the size of this data structure (that is,
     * sizeof(AVRegionOfInterest)).
     *)
    Self_size: Cardinal;
    (**
     * Distance in pixels from the top edge of the frame to the top and
     * bottom edges and from the left edge of the frame to the left and
     * right edges of the rectangle defining this region of interest.
     *
     * The constraints on a region are encoder dependent, so the region
     * actually affected may be slightly larger for alignment or other
     * reasons.
     *)
    top: Integer;
    bottom: Integer;
    left: Integer;
    right: Integer;
    (**
     * Quantisation offset.
     *
     * Must be in the range -1 to +1.  A value of zero indicates no quality
     * change.  A negative value asks for better quality (less quantisation),
     * while a positive value asks for worse quality (greater quantisation).
     *
     * The range is calibrated so that the extreme values indicate the
     * largest possible offset - if the rest of the frame is encoded with the
     * worst possible quality, an offset of -1 indicates that this region
     * should be encoded with the best possible quality anyway.  Intermediate
     * values are then interpolated in some codec-dependent way.
     *
     * For example, in 10-bit H.264 the quantisation parameter varies between
     * -12 and 51.  A typical qoffset value of -1/10 therefore indicates that
     * this region should be encoded with a QP around one-tenth of the full
     * range better than the rest of the frame.  So, if most of the frame
     * were to be encoded with a QP of around 30, this region would get a QP
     * of around 24 (an offset of approximately -1/10 * (51 - -12) = -6.3).
     * An extreme value of -1 would indicate that this region should be
     * encoded with the best possible quality regardless of the treatment of
     * the rest of the frame - that is, should be encoded at a QP of -12.
     *)
    qoffset: TAVRational;
  end;

(**
 * This structure describes decoded (raw) audio or video data.
 *
 * AVFrame must be allocated using av_frame_alloc(). Note that this only
 * allocates the AVFrame itself, the buffers for the data must be managed
 * through other means (see below).
 * AVFrame must be freed with av_frame_free().
 *
 * AVFrame is typically allocated once and then reused multiple times to hold
 * different data (e.g. a single AVFrame to hold frames received from a
 * decoder). In such a case, av_frame_unref() will free any references held by
 * the frame and reset it to its original clean state before it
 * is reused again.
 *
 * The data described by an AVFrame is usually reference counted through the
 * AVBuffer API. The underlying buffer references are stored in AVFrame.buf /
 * AVFrame.extended_buf. An AVFrame is considered to be reference counted if at
 * least one reference is set, i.e. if AVFrame.buf[0] != NULL. In such a case,
 * every single data plane must be contained in one of the buffers in
 * AVFrame.buf or AVFrame.extended_buf.
 * There may be a single buffer for all the data, or one separate buffer for
 * each plane, or anything in between.
 *
 * sizeof(AVFrame) is not a part of the public ABI, so new fields may be added
 * to the end with a minor bump.
 *
 * Fields can be accessed through AVOptions, the name string used, matches the
 * C structure field name for fields accessible through AVOptions.
 *)
  PPAVFrame = ^PAVFrame;
  PAVFrame = ^TAVFrame;
  TAVFrame = record
//#define AV_NUM_DATA_POINTERS 8
    (**
     * pointer to the picture/channel planes.
     * This might be different from the first allocated byte. For video,
     * it could even point to the end of the image data.
     *
     * All pointers in data and extended_data must point into one of the
     * AVBufferRef in buf or extended_buf.
     *
     * Some decoders access areas outside 0,0 - width,height, please
     * see avcodec_align_dimensions2(). Some filters and swscale can read
     * up to 16 bytes beyond the planes, if these filters are to be used,
     * then 16 extra bytes must be allocated.
     *
     * NOTE: Pointers not needed by the format MUST be set to NULL.
     *
     * @attention In case of video, the data[] pointers can point to the
     * end of image data in order to reverse line order, when used in
     * combination with negative values in the linesize[] array.
     *)
    data: array[0..AV_NUM_DATA_POINTERS-1] of PByte;

    (**
     * For video, a positive or negative value, which is typically indicating
     * the size in bytes of each picture line, but it can also be:
     * - the negative byte size of lines for vertical flipping
     *   (with data[n] pointing to the end of the data
     * - a positive or negative multiple of the byte size as for accessing
     *   even and odd fields of a frame (possibly flipped)
     *
     * For audio, only linesize[0] may be set. For planar audio, each channel
     * plane must be the same size.
     *
     * For video the linesizes should be multiples of the CPUs alignment
     * preference, this is 16 or 32 for modern desktop CPUs.
     * Some code requires such alignment other code can be slower without
     * correct alignment, for yet other it makes no difference.
     *
     * @note The linesize may be larger than the size of usable data -- there
     * may be extra padding present for performance reasons.
     *
     * @attention In case of video, line size values can be negative to achieve
     * a vertically inverted iteration over image lines.
     *)
    linesize: array[0..AV_NUM_DATA_POINTERS-1] of Integer;

    (**
     * pointers to the data planes/channels.
     *
     * For video, this should simply point to data[].
     *
     * For planar audio, each channel has a separate data pointer, and
     * linesize[0] contains the size of each channel buffer.
     * For packed audio, there is just one data pointer, and linesize[0]
     * contains the total size of the buffer for all channels.
     *
     * Note: Both data and extended_data should always be set in a valid frame,
     * but for planar audio with more channels that can fit in data,
     * extended_data must be used in order to access all channels.
     *)
    extended_data: PPByte;

    (**
     * @name Video dimensions
     * Video frames only. The coded dimensions (in pixels) of the video frame,
     * i.e. the size of the rectangle that contains some well-defined values.
     *
     * @note The part of the frame intended for display/presentation is further
     * restricted by the @ref cropping "Cropping rectangle".
     * @{
     *)
    width, height: Integer;
    (**
     * @}
     *)

    (**
     * number of audio samples (per channel) described by this frame
     *)
    nb_samples: Integer;

    (**
     * format of the frame, -1 if unknown or unset
     * Values correspond to enum AVPixelFormat for video frames,
     * enum AVSampleFormat for audio)
     *)
    format: Integer;

    (**
     * Picture type of the frame.
     *)
    pict_type: TAVPictureType;

    (**
     * Sample aspect ratio for the video frame, 0/1 if unknown/unspecified.
     *)
    sample_aspect_ratio: TAVRational;

    (**
     * Presentation timestamp in time_base units (time when frame should be shown to user).
     *)
    pts: Int64;

    (**
     * DTS copied from the AVPacket that triggered returning this frame. (if frame threading isn't used)
     * This is also the Presentation time of this AVFrame calculated from
     * only AVPacket.dts values without pts values.
     *)
    pkt_dts: Int64;

    (**
     * Time base for the timestamps in this frame.
     * In the future, this field may be set on frames output by decoders or
     * filters, but its value will be by default ignored on input to encoders
     * or filters.
     *)
    time_base: TAVRational;

    (**
     * quality (between 1 (good) and FF_LAMBDA_MAX (bad))
     *)
    quality: Integer;

    (**
     * Frame owner's private data.
     *
     * This field may be set by the code that allocates/owns the frame data.
     * It is then not touched by any library functions, except:
     * - it is copied to other references by av_frame_copy_props() (and hence by
     *   av_frame_ref());
     * - it is set to NULL when the frame is cleared by av_frame_unref()
     * - on the caller's explicit request. E.g. libavcodec encoders/decoders
     *   will copy this field to/from @ref AVPacket "AVPackets" if the caller sets
     *   @ref AV_CODEC_FLAG_COPY_OPAQUE.
     *
     * @see opaque_ref the reference-counted analogue
     *)
    opaque: Pointer;

    (**
     * Number of fields in this frame which should be repeated, i.e. the total
     * duration of this frame should be repeat_pict + 2 normal field durations.
     *
     * For interlaced frames this field may be set to 1, which signals that this
     * frame should be presented as 3 fields: beginning with the first field (as
     * determined by AV_FRAME_FLAG_TOP_FIELD_FIRST being set or not), followed
     * by the second field, and then the first field again.
     *
     * For progressive frames this field may be set to a multiple of 2, which
     * signals that this frame's duration should be (repeat_pict + 2) / 2
     * normal frame durations.
     *
     * @note This field is computed from MPEG2 repeat_first_field flag and its
     * associated flags, H.264 pic_struct from picture timing SEI, and
     * their analogues in other codecs. Typically it should only be used when
     * higher-layer timing information is not available.
     *)
    repeat_pict: Integer;

    (**
     * Sample rate of the audio data.
     *)
    sample_rate: Integer;

    (**
     * AVBuffer references backing the data for this frame. All the pointers in
     * data and extended_data must point inside one of the buffers in buf or
     * extended_buf. This array must be filled contiguously -- if buf[i] is
     * non-NULL then buf[j] must also be non-NULL for all j < i.
     *
     * There may be at most one AVBuffer per data plane, so for video this array
     * always contains all the references. For planar audio with more than
     * AV_NUM_DATA_POINTERS channels, there may be more buffers than can fit in
     * this array. Then the extra AVBufferRef pointers are stored in the
     * extended_buf array.
     *)
    buf: array[0..AV_NUM_DATA_POINTERS - 1] of PAVBufferRef;

    (**
     * For planar audio which requires more than AV_NUM_DATA_POINTERS
     * AVBufferRef pointers, this array will hold all the references which
     * cannot fit into AVFrame.buf.
     *
     * Note that this is different from AVFrame.extended_data, which always
     * contains all the pointers. This array only contains the extra pointers,
     * which cannot fit into AVFrame.buf.
     *
     * This array is always allocated using av_malloc() by whoever constructs
     * the frame. It is freed in av_frame_unref().
     *)
    extended_buf: PPAVBufferRef;
    (**
     * Number of elements in extended_buf.
     *)
    nb_extended_buf: Integer;

    side_data: PPAVFrameSideData;
    nb_side_data: Integer;

(**
 * @defgroup lavu_frame_flags AV_FRAME_FLAGS
 * @ingroup lavu_frame
 * Flags describing additional frame properties.
 *
 * @{
 *)

(**
 * The frame data may be corrupted, e.g. due to decoding errors.
 *)
//#define AV_FRAME_FLAG_CORRUPT       (1 << 0)
(**
 * A flag to mark frames that are keyframes.
 *)
//#define AV_FRAME_FLAG_KEY (1 << 1)
(**
 * A flag to mark the frames which need to be decoded, but shouldn't be output.
 *)
//#define AV_FRAME_FLAG_DISCARD   (1 << 2)
(**
 * A flag to mark frames whose content is interlaced.
 *)
//#define AV_FRAME_FLAG_INTERLACED (1 << 3)
(**
 * A flag to mark frames where the top field is displayed first if the content
 * is interlaced.
 *)
//#define AV_FRAME_FLAG_TOP_FIELD_FIRST (1 << 4)
(**
 * A decoder can use this flag to mark frames which were originally encoded losslessly.
 *
 * For coding bitstream formats which support both lossless and lossy
 * encoding, it is sometimes possible for a decoder to determine which method
 * was used when the bitsream was encoded.
 *)
//#define AV_FRAME_FLAG_LOSSLESS        (1 << 5)
(**
 * @}
 *)

    (**
     * Frame flags, a combination of @ref lavu_frame_flags
     *)
    flags: Integer;

    (**
     * MPEG vs JPEG YUV range.
     * - encoding: Set by user
     * - decoding: Set by libavcodec
     *)
    color_range: TAVColorRange;

    color_primaries: TAVColorPrimaries;

    color_trc: TAVColorTransferCharacteristic;

    (**
     * YUV colorspace type.
     * - encoding: Set by user
     * - decoding: Set by libavcodec
     *)
    colorspace: TAVColorSpace;

    chroma_location: TAVChromaLocation;

    (**
     * frame timestamp estimated using various heuristics, in stream time base
     * - encoding: unused
     * - decoding: set by libavcodec, read by user.
     *)
    best_effort_timestamp: Int64;

    (**
     * metadata.
     * - encoding: Set by user.
     * - decoding: Set by libavcodec.
     *)
    metadata: PAVDictionary;

    (**
     * decode error flags of the frame, set to a combination of
     * FF_DECODE_ERROR_xxx flags if the decoder produced a frame, but there
     * were errors during the decoding.
     * - encoding: unused
     * - decoding: set by libavcodec, read by user.
     *)
    decode_error_flags: Integer;
//#define FF_DECODE_ERROR_INVALID_BITSTREAM   1
//#define FF_DECODE_ERROR_MISSING_REFERENCE   2
//#define FF_DECODE_ERROR_CONCEALMENT_ACTIVE  4
//#define FF_DECODE_ERROR_DECODE_SLICES       8

    (**
     * For hwaccel-format frames, this should be a reference to the
     * AVHWFramesContext describing the frame.
     *)
    hw_frames_ctx: PAVBufferRef;

    (**
     * Frame owner's private data.
     *
     * This field may be set by the code that allocates/owns the frame data.
     * It is then not touched by any library functions, except:
     * - a new reference to the underlying buffer is propagated by
     *   av_frame_copy_props() (and hence by av_frame_ref());
     * - it is unreferenced in av_frame_unref();
     * - on the caller's explicit request. E.g. libavcodec encoders/decoders
     *   will propagate a new reference to/from @ref AVPacket "AVPackets" if the
     *   caller sets @ref AV_CODEC_FLAG_COPY_OPAQUE.
     *
     * @see opaque the plain pointer analogue
     *)
    opaque_ref: PAVBufferRef;

    (**
     * @anchor cropping
     * @name Cropping
     * Video frames only. The number of pixels to discard from the the
     * top/bottom/left/right border of the frame to obtain the sub-rectangle of
     * the frame intended for presentation.
     * @{
     *)
    crop_top: Size_t;
    crop_bottom: Size_t;
    crop_left: Size_t;
    crop_right: Size_t;
    (**
     * @}
     *)

    (**
     * RefStruct reference for internal use by a single libav* library.
     * Must not be used to transfer data between libraries.
     * Has to be NULL when ownership of the frame leaves the respective library.
     *
     * Code outside the FFmpeg libs must never check or change private_ref.
     *)
    private_ref: Pointer;

    (**
     * Channel layout of the audio data.
     *)
    ch_layout: TAVChannelLayout;

    (**
     * Duration of the frame, in the same units as pts. 0 if unknown.
     *)
    duration: Int64;
  end;


(**
 * Allocate an AVFrame and set its fields to default values.  The resulting
 * struct must be freed using av_frame_free().
 *
 * @return An AVFrame filled with default values or NULL on failure.
 *
 * @note this only allocates the AVFrame itself, not the data buffers. Those
 * must be allocated through other means, e.g. with av_frame_get_buffer() or
 * manually.
 *)
function av_frame_alloc(): PAVFrame; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_alloc';

(**
 * Free the frame and any dynamically allocated objects in it,
 * e.g. extended_data. If the frame is reference counted, it will be
 * unreferenced first.
 *
 * @param frame frame to be freed. The pointer will be set to NULL.
 *)
procedure av_frame_free(frame: PPAVFrame); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_free';

(**
 * Set up a new reference to the data described by the source frame.
 *
 * Copy frame properties from src to dst and create a new reference for each
 * AVBufferRef from src.
 *
 * If src is not reference counted, new buffers are allocated and the data is
 * copied.
 *
 * @warning: dst MUST have been either unreferenced with av_frame_unref(dst),
 *           or newly allocated with av_frame_alloc() before calling this
 *           function, or undefined behavior will occur.
 *
 * @return 0 on success, a negative AVERROR on error
 *)
function av_frame_ref(dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_ref';

(**
 * Ensure the destination frame refers to the same data described by the source
 * frame, either by creating a new reference for each AVBufferRef from src if
 * they differ from those in dst, by allocating new buffers and copying data if
 * src is not reference counted, or by unrefencing it if src is empty.
 *
 * Frame properties on dst will be replaced by those from src.
 *
 * @return 0 on success, a negative AVERROR on error. On error, dst is
 *         unreferenced.
 *)
function av_frame_replace(dst: PAVFrame; const src: PAVFrame): integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_replace';

(**
 * Create a new frame that references the same data as src.
 *
 * This is a shortcut for av_frame_alloc()+av_frame_ref().
 *
 * @return newly created AVFrame on success, NULL on error.
 *)
function av_frame_clone(const src: PAVFrame): PAVFrame; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_clone';

(**
 * Unreference all the buffers referenced by frame and reset the frame fields.
 *)
procedure av_frame_unref(frame: PAVFrame); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_unref';

(**
 * Move everything contained in src to dst and reset src.
 *
 * @warning: dst is not unreferenced, but directly overwritten without reading
 *           or deallocating its contents. Call av_frame_unref(dst) manually
 *           before calling this function to ensure that no memory is leaked.
 *)
procedure av_frame_move_ref(dst, src: PAVFrame); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_move_ref';

(**
 * Allocate new buffer(s) for audio or video data.
 *
 * The following fields must be set on frame before calling this function:
 * - format (pixel format for video, sample format for audio)
 * - width and height for video
 * - nb_samples and ch_layout for audio
 *
 * This function will fill AVFrame.data and AVFrame.buf arrays and, if
 * necessary, allocate and fill AVFrame.extended_data and AVFrame.extended_buf.
 * For planar formats, one buffer will be allocated for each plane.
 *
 * @warning: if frame already has been allocated, calling this function will
 *           leak memory. In addition, undefined behavior can occur in certain
 *           cases.
 *
 * @param frame frame in which to store the new buffers.
 * @param align Required buffer size and data pointer alignment. If equal to 0,
 *              alignment will be chosen automatically for the current CPU.
 *              It is highly recommended to pass 0 here unless you know what
 *              you are doing.
 *
 * @return 0 on success, a negative AVERROR on error.
 *)
function av_frame_get_buffer(frame: PAVFrame; align: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_get_buffer';

(**
 * Check if the frame data is writable.
 *
 * @return A positive value if the frame data is writable (which is true if and
 * only if each of the underlying buffers has only one reference, namely the one
 * stored in this frame). Return 0 otherwise.
 *
 * If 1 is returned the answer is valid until av_buffer_ref() is called on any
 * of the underlying AVBufferRefs (e.g. through av_frame_ref() or directly).
 *
 * @see av_frame_make_writable(), av_buffer_is_writable()
 *)
function av_frame_is_writable(frame: PAVFrame): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_is_writable';

(**
 * Ensure that the frame data is writable, avoiding data copy if possible.
 *
 * Do nothing if the frame is writable, allocate new buffers and copy the data
 * if it is not. Non-refcounted frames behave as non-writable, i.e. a copy
 * is always made.
 *
 * @return 0 on success, a negative AVERROR on error.
 *
 * @see av_frame_is_writable(), av_buffer_is_writable(),
 * av_buffer_make_writable()
 *)
function av_frame_make_writable(frame: PAVFrame): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_make_writable';

(**
 * Copy the frame data from src to dst.
 *
 * This function does not allocate anything, dst must be already initialized and
 * allocated with the same parameters as src.
 *
 * This function only copies the frame data (i.e. the contents of the data /
 * extended data arrays), not any other properties.
 *
 * @return >= 0 on success, a negative AVERROR on error.
 *)
function av_frame_copy(dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_copy';

(**
 * Copy only "metadata" fields from src to dst.
 *
 * Metadata for the purpose of this function are those fields that do not affect
 * the data layout in the buffers.  E.g. pts, sample rate (for audio) or sample
 * aspect ratio (for video), but not width/height or channel layout.
 * Side data is also copied.
 *)
function av_frame_copy_props(dst: PAVFrame; const src: PAVFrame): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_copy_props';

(**
 * Get the buffer reference a given data plane is stored in.
 *
 * @param frame the frame to get the plane's buffer from
 * @param plane index of the data plane of interest in frame->extended_data.
 *
 * @return the buffer reference that contains the plane or NULL if the input
 * frame is not valid.
 *)
function av_frame_get_plane_buffer(const frame: PAVFrame; plane: Integer): PAVBufferRef; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_get_plane_buffer';

(**
 * Add a new side data to a frame.
 *
 * @param frame a frame to which the side data should be added
 * @param type type of the added side data
 * @param size size of the side data
 *
 * @return newly added side data on success, NULL on error
 *)
function av_frame_new_side_data(frame: PAVFrame;
                                         type_: TAVFrameSideDataType;
                                         size: Size_t): PAVFrameSideData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_new_side_data';

(**
 * Add a new side data to a frame from an existing AVBufferRef
 *
 * @param frame a frame to which the side data should be added
 * @param type  the type of the added side data
 * @param buf   an AVBufferRef to add as side data. The ownership of
 *              the reference is transferred to the frame.
 *
 * @return newly added side data on success, NULL on error. On failure
 *         the frame is unchanged and the AVBufferRef remains owned by
 *         the caller.
 *)
function av_frame_new_side_data_from_buf(frame: PAVFrame;
                                                 type_: TAVFrameSideDataType;
                                                 buf: PAVBufferRef): PAVFrameSideData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_new_side_data_from_buf';

(**
 * @return a pointer to the side data of a given type on success, NULL if there
 * is no side data with such type in this frame.
 *)
function av_frame_get_side_data(const frame: PAVFrame;
                                         type_: TAVFrameSideDataType): PAVFrameSideData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_get_side_data';

(**
 * Remove and free all side data instances of the given type.
 *)
procedure av_frame_remove_side_data(frame: PAVFrame; type_: TAVFrameSideDataType); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_remove_side_data';


(**
 * Flags for frame cropping.
 *)
//enum {
    (**
     * Apply the maximum possible cropping, even if it requires setting the
     * AVFrame.data[] entries to unaligned pointers. Passing unaligned data
     * to FFmpeg API is generally not allowed, and causes undefined behavior
     * (such as crashes). You can pass unaligned data only to FFmpeg APIs that
     * are explicitly documented to accept it. Use this flag only if you
     * absolutely know what you are doing.
     *)
const
    AV_FRAME_CROP_UNALIGNED     = (1 shl 0);
//};

(**
 * Remove existing entries before adding new ones.
 *)
  AV_FRAME_SIDE_DATA_FLAG_UNIQUE = (1 shl 0);
(**
 * Don't add a new entry if another of the same type exists.
 * Applies only for side data types without the AV_SIDE_DATA_PROP_MULTI prop.
 *)
  AV_FRAME_SIDE_DATA_FLAG_REPLACE = (1 shl 1);
(**
 * Create a new reference to the passed in buffer instead of taking ownership
 * of it.
 *)
  AV_FRAME_SIDE_DATA_FLAG_NEW_REF = (1 shl 2);

(**
 * Crop the given video AVFrame according to its crop_left/crop_top/crop_right/
 * crop_bottom fields. If cropping is successful, the function will adjust the
 * data pointers and the width/height fields, and set the crop fields to 0.
 *
 * In all cases, the cropping boundaries will be rounded to the inherent
 * alignment of the pixel format. In some cases, such as for opaque hwaccel
 * formats, the left/top cropping is ignored. The crop fields are set to 0 even
 * if the cropping was rounded or ignored.
 *
 * @param frame the frame which should be cropped
 * @param flags Some combination of AV_FRAME_CROP_* flags, or 0.
 *
 * @return >= 0 on success, a negative AVERROR on error. If the cropping fields
 * were invalid, AVERROR(ERANGE) is returned, and nothing is changed.
 *)
function av_frame_apply_cropping(frame: PAVFrame; flags: Integer): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_apply_cropping';

(**
 * @return a string identifying the side data type
 *)
function av_frame_side_data_name(type_: TAVFrameSideDataType): PAnsiChar; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_name';

(**
 * @return side data descriptor corresponding to a given side data type, NULL
 *         when not available.
 *)
function av_frame_side_data_desc(type_: TAVFrameSideDataType): PAVSideDataDescriptor; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_desc';

(**
 * Free all side data entries and their contents, then zeroes out the
 * values which the pointers are pointing to.
 *
 * @param sd    pointer to array of side data to free. Will be set to NULL
 *              upon return.
 * @param nb_sd pointer to an integer containing the number of entries in
 *              the array. Will be set to 0 upon return.
 *)
procedure av_frame_side_data_free(sd: PPPAVFrameSideData; nb_sd: PInteger); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_free';

(**
 * Add new side data entry to an array.
 *
 * @param sd    pointer to array of side data to which to add another entry,
 *              or to NULL in order to start a new array.
 * @param nb_sd pointer to an integer containing the number of entries in
 *              the array.
 * @param type  type of the added side data
 * @param size  size of the side data
 * @param flags Some combination of AV_FRAME_SIDE_DATA_FLAG_* flags, or 0.
 *
 * @return newly added side data on success, NULL on error.
 * @note In case of AV_FRAME_SIDE_DATA_FLAG_UNIQUE being set, entries of
 *       matching AVFrameSideDataType will be removed before the addition
 *       is attempted.
 * @note In case of AV_FRAME_SIDE_DATA_FLAG_REPLACE being set, if an
 *       entry of the same type already exists, it will be replaced instead.
 *)
function av_frame_side_data_new(sd: PPPAVFrameSideData; nb_sd: PInteger;
                                        type_: TAVFrameSideDataType;
                                        size: Size_t; flags: Cardinal): PAVFrameSideData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_new';

(**
 * Add a new side data entry to an array from an existing AVBufferRef.
 *
 * @param sd    pointer to array of side data to which to add another entry,
 *              or to NULL in order to start a new array.
 * @param nb_sd pointer to an integer containing the number of entries in
 *              the array.
 * @param type  type of the added side data
 * @param buf   Pointer to AVBufferRef to add to the array. On success,
 *              the function takes ownership of the AVBufferRef and *buf is
 *              set to NULL, unless AV_FRAME_SIDE_DATA_FLAG_NEW_REF is set
 *              in which case the ownership will remain with the caller.
 * @param flags Some combination of AV_FRAME_SIDE_DATA_FLAG_* flags, or 0.
 *
 * @return newly added side data on success, NULL on error.
 * @note In case of AV_FRAME_SIDE_DATA_FLAG_UNIQUE being set, entries of
 *       matching AVFrameSideDataType will be removed before the addition
 *       is attempted.
 * @note In case of AV_FRAME_SIDE_DATA_FLAG_REPLACE being set, if an
 *       entry of the same type already exists, it will be replaced instead.
 *
 *)
function av_frame_side_data_add(sd: PPPAVFrameSideData; nb_sd: PInteger;
                                        type_: TAVFrameSideDataType;
                                        buf: PPAVBufferRef; flags: Cardinal): PAVFrameSideData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_add';

(**
 * Add a new side data entry to an array based on existing side data, taking
 * a reference towards the contained AVBufferRef.
 *
 * @param sd    pointer to array of side data to which to add another entry,
 *              or to NULL in order to start a new array.
 * @param nb_sd pointer to an integer containing the number of entries in
 *              the array.
 * @param src   side data to be cloned, with a new reference utilized
 *              for the buffer.
 * @param flags Some combination of AV_FRAME_SIDE_DATA_FLAG_* flags, or 0.
 *
 * @return negative error code on failure, >=0 on success.
 * @note In case of AV_FRAME_SIDE_DATA_FLAG_UNIQUE being set, entries of
 *       matching AVFrameSideDataType will be removed before the addition
 *       is attempted.
 * @note In case of AV_FRAME_SIDE_DATA_FLAG_REPLACE being set, if an
 *       entry of the same type already exists, it will be replaced instead.
 *)
function av_frame_side_data_clone(sd: PPPAVFrameSideData; nb_sd: PInteger;
                             const src: PAVFrameSideData; flags: Cardinal): Integer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_clone';

(**
 * Get a side data entry of a specific type from an array.
 *
 * @param sd    array of side data.
 * @param nb_sd integer containing the number of entries in the array.
 * @param type  type of side data to be queried
 *
 * @return a pointer to the side data of a given type on success, NULL if there
 *         is no side data with such type in this set.
 *)
function av_frame_side_data_get_c(const sd: PPAVFrameSideData;
                                           const nb_sd: Integer;
                                           type_: TAVFrameSideDataType): PAVFrameSideData; cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_get_c';

(**
 * Remove and free all side data instances of the given type from an array.
 *)
procedure av_frame_side_data_remove(sd: PPPAVFrameSideData; nb_sd: PInteger;
                               type_: TAVFrameSideDataType); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_remove';

(**
 * Remove and free all side data instances that match any of the given
 * side data properties. (See enum AVSideDataProps)
 *)
procedure av_frame_side_data_remove_by_props(sd: PPPAVFrameSideData; nb_sd: PInteger;
                                        props: Integer); cdecl; external AVUTIL_LIBNAME name _PU + 'av_frame_side_data_remove_by_props';

(**
 * Wrapper around av_frame_side_data_get_c() to workaround the limitation
 * that for any type T the conversion from T * const * to const T * const *
 * is not performed automatically in C.
 * @see av_frame_side_data_get_c()
 *)
function av_frame_side_data_get(sd: PPAVFrameSideData;
                                const nb_sd: Integer;
                                type_: TAVFrameSideDataType): PAVFrameSideData; {$IFDEF USE_INLINE}inline;{$ENDIF}

(**
 * @}
 *)

implementation


function av_frame_side_data_get(sd: PPAVFrameSideData;
                                const nb_sd: Integer;
                                type_: TAVFrameSideDataType): PAVFrameSideData;
begin
  Result := av_frame_side_data_get_c(sd, nb_sd, type_);
end;

end.
