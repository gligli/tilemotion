// TODO: check from ffmpeg.h
// deprecated features
{$DEFINE FFMPEG_OPT_QPHIST}
{$DEFINE FFMPEG_OPT_ADRIFT_THRESHOLD}
{$DEFINE FFMPEG_OPT_ENC_TIME_BASE_NUM}
{$DEFINE FFMPEG_OPT_TOP}
{$DEFINE FFMPEG_OPT_FORCE_KF_SOURCE_NO_DROP}
{$DEFINE FFMPEG_OPT_VSYNC_DROP}
{$DEFINE FFMPEG_OPT_VSYNC}
{$DEFINE FFMPEG_OPT_FILTER_SCRIPT}

const
  {%H-}FFMPEG_VERSION     = '7.1.1';
  {%H-}program_birth_year = 2000;
  {%H-}CONFIG_THIS_YEAR   = 2025;

  // libavcodec
  LIBAVCODEC_VERSION_MAJOR = 61;
  LIBAVCODEC_VERSION_MINOR = 19;
  LIBAVCODEC_VERSION_MICRO = 101;
  LIBAVCODEC_VERSION       = '61.19.101';
  LIBAVCODEC_VERSION_INT   = (LIBAVCODEC_VERSION_MAJOR shl 16) or
                             (LIBAVCODEC_VERSION_MINOR shl 8) or
                              LIBAVCODEC_VERSION_MICRO;
  {%H-}LIBAVCODEC_BUILD    = LIBAVCODEC_VERSION_INT;
  {%H-}LIBAVCODEC_IDENT    = 'Lavc' + LIBAVCODEC_VERSION;

(**
 * FF_API_* defines may be placed below to indicate public API that will be
 * dropped at a future version bump. The defines themselves are not part of
 * the public API and may change, break or disappear at any time.
 *
 * @note, when bumping the major version it is recommended to manually
 * disable each FF_API_* in its own commit instead of disabling them all
 * at once through the bump. This improves the git bisect-ability of the change.
 *)

{$IF LIBAVCODEC_VERSION_MAJOR < 62}
  {$DEFINE FF_API_INIT_PACKET}
  {$DEFINE FF_API_SUBFRAMES}
  {$DEFINE FF_API_TICKS_PER_FRAME}
  {$DEFINE FF_API_DROPCHANGED}

  {$DEFINE FF_API_AVFFT}
  {$DEFINE FF_API_FF_PROFILE_LEVEL}

  {$DEFINE FF_API_AVCODEC_CLOSE}
  {$DEFINE FF_API_BUFFER_MIN_SIZE}
  {$DEFINE FF_API_VDPAU_ALLOC_GET_SET}
  {$DEFINE FF_API_QUALITY_FACTOR}
{$IFEND}

  // libavdevice
  LIBAVDEVICE_VERSION_MAJOR = 61;
  LIBAVDEVICE_VERSION_MINOR = 3;
  LIBAVDEVICE_VERSION_MICRO = 100;
  LIBAVDEVICE_VERSION       = '61.3.100';
  LIBAVDEVICE_VERSION_INT   = (LIBAVDEVICE_VERSION_MAJOR shl 16) or
                              (LIBAVDEVICE_VERSION_MINOR shl 8) or
                               LIBAVDEVICE_VERSION_MICRO;
  {%H-}LIBAVDEVICE_BUILD    = LIBAVDEVICE_VERSION_INT;
  {%H-}LIBAVDEVICE_IDENT    = 'Lavc' + LIBAVDEVICE_VERSION;

(**
 * FF_API_* defines may be placed below to indicate public API that will be
 * dropped at a future version bump. The defines themselves are not part of
 * the public API and may change, break or disappear at any time.
 *)

{$IF LIBAVDEVICE_VERSION_MAJOR < 62}
  // reminder to remove the bktr device on next major bump
  {$DEFINE FF_API_BKTR_DEVICE}
  // reminder to remove the opengl device on next major bump
  {$DEFINE FF_API_OPENGL_DEVICE}
  // reminder to remove the sdl2 device on next major bump
  {$DEFINE FF_API_SDL2_DEVICE}
{$IFEND}

  // libavfilter
  LIBAVFILTER_VERSION_MAJOR  = 10;
  LIBAVFILTER_VERSION_MINOR  = 4;
  LIBAVFILTER_VERSION_MICRO  = 100;
  LIBAVFILTER_VERSION        = '10.4.100';
  LIBAVFILTER_VERSION_INT    = (LIBAVFILTER_VERSION_MAJOR shl 16) or
                               (LIBAVFILTER_VERSION_MINOR shl 8) or
                                LIBAVFILTER_VERSION_MICRO;
  {%H-}LIBAVFILTER_BUILD     = LIBAVFILTER_VERSION_INT;
  {%H-}LIBAVFILTER_IDENT     = 'Lavfi' + LIBAVFILTER_VERSION;

(**
 * FF_API_* defines may be placed below to indicate public API that will be
 * dropped at a future version bump. The defines themselves are not part of
 * the public API and may change, break or disappear at any time.
 *)

{$IF LIBAVFILTER_VERSION_MAJOR < 11}
  {$DEFINE FF_API_LINK_PUBLIC}
{$IFEND}

  // libavformat
  LIBAVFORMAT_VERSION_MAJOR = 61;
  LIBAVFORMAT_VERSION_MINOR = 7;
  LIBAVFORMAT_VERSION_MICRO = 100;
  LIBAVFORMAT_VERSION       = '61.7.100';
  LIBAVFORMAT_VERSION_INT   = (LIBAVFORMAT_VERSION_MAJOR shl 16) or
                              (LIBAVFORMAT_VERSION_MINOR shl 8) or
                               LIBAVFORMAT_VERSION_MICRO;
  {%H-}LIBAVFORMAT_BUILD    = LIBAVFORMAT_VERSION_INT;
  {%H-}LIBAVFORMAT_IDENT    = 'Lavf' + LIBAVFORMAT_VERSION;

(**
 * FF_API_* defines may be placed below to indicate public API that will be
 * dropped at a future version bump. The defines themselves are not part of
 * the public API and may change, break or disappear at any time.
 *
 * @note, when bumping the major version it is recommended to manually
 * disable each FF_API_* in its own commit instead of disabling them all
 * at once through the bump. This improves the git bisect-ability of the change.
 *
 *)

{$IF LIBAVFORMAT_VERSION_MAJOR < 62}
  {$DEFINE FF_API_COMPUTE_PKT_FIELDS2}
  {$DEFINE FF_API_LAVF_SHORTEST}
  {$DEFINE FF_API_ALLOW_FLUSH}
  {$DEFINE FF_API_AVSTREAM_SIDE_DATA}

  {$DEFINE FF_API_GET_DUR_ESTIMATE_METHOD}
  {$DEFINE FF_API_INTERNAL_TIMING}
{$IFEND}

{$DEFINE FF_API_R_FRAME_RATE}

  // libavutil
  LIBAVUTIL_VERSION_MAJOR = 59;
  LIBAVUTIL_VERSION_MINOR = 39;
  LIBAVUTIL_VERSION_MICRO = 100;
  LIBAVUTIL_VERSION       = '59.39.100';
  LIBAVUTIL_VERSION_INT   = (LIBAVUTIL_VERSION_MAJOR shl 16) or
                            (LIBAVUTIL_VERSION_MINOR shl 8) or
                             LIBAVUTIL_VERSION_MICRO;
  {%H-}LIBAVUTIL_BUILD    = LIBAVUTIL_VERSION_INT;
  {%H-}LIBAVUTIL_IDENT    = 'Lavu' + LIBAVUTIL_VERSION;

(**
 * @defgroup lavu_depr_guards Deprecation Guards
 * FF_API_* defines may be placed below to indicate public API that will be
 * dropped at a future version bump. The defines themselves are not part of
 * the public API and may change, break or disappear at any time.
 *
 * @note, when bumping the major version it is recommended to manually
 * disable each FF_API_* in its own commit instead of disabling them all
 * at once through the bump. This improves the git bisect-ability of the change.
 *
 * @{
 *)

{$IF LIBAVUTIL_VERSION_MAJOR < 60}
  {$DEFINE FF_API_HDR_VIVID_THREE_SPLINE}
  {$DEFINE FF_API_FRAME_PKT}
  {$DEFINE FF_API_INTERLACED_FRAME}
  {$DEFINE FF_API_FRAME_KEY}
  {$DEFINE FF_API_PALETTE_HAS_CHANGED}
  {$DEFINE FF_API_VULKAN_CONTIGUOUS_MEMORY}
  {$DEFINE FF_API_H274_FILM_GRAIN_VCS}
  {$DEFINE FF_API_MOD_UINTP2}
  {$DEFINE FF_API_RISCV_FD_ZBA}
  {$DEFINE FF_API_VULKAN_FIXED_QUEUES}
{$IFEND}

(**
 * @}
 *)

  // libswresample
  LIBSWRESAMPLE_VERSION_MAJOR = 5;
  LIBSWRESAMPLE_VERSION_MINOR = 3;
  LIBSWRESAMPLE_VERSION_MICRO = 100;
  LIBSWRESAMPLE_VERSION       = '5.3.100';
  LIBSWRESAMPLE_VERSION_INT   = (LIBSWRESAMPLE_VERSION_MAJOR shl 16) or
                                (LIBSWRESAMPLE_VERSION_MINOR shl 8) or
                                 LIBSWRESAMPLE_VERSION_MICRO;
  {%H-}LIBSWRESAMPLE_BUILD    = LIBSWRESAMPLE_VERSION_INT;
  {%H-}LIBSWRESAMPLE_IDENT    = 'SwS' + LIBSWRESAMPLE_VERSION;

  // libswscale
  LIBSWSCALE_VERSION_MAJOR = 8;
  LIBSWSCALE_VERSION_MINOR = 3;
  LIBSWSCALE_VERSION_MICRO = 100;
  LIBSWSCALE_VERSION       = '8.3.100';
  LIBSWSCALE_VERSION_INT   = (LIBSWSCALE_VERSION_MAJOR shl 16) or
                             (LIBSWSCALE_VERSION_MINOR shl 8) or
                              LIBSWSCALE_VERSION_MICRO;
  {%H-}LIBSWSCALE_BUILD    = LIBSWSCALE_VERSION_INT;
  {%H-}LIBSWSCALE_IDENT    = 'SwS' + LIBSWSCALE_VERSION;

(**
 * FF_API_* defines may be placed below to indicate public API that will be
 * dropped at a future version bump. The defines themselves are not part of
 * the public API and may change, break or disappear at any time.
 *)
{$IFDEF MSWINDOWS}
  CLibPrefix = '';
  CLibConnector = '-';
  CLibExtension = '.dll';
  _PU = '';
{$ENDIF}
{$IFDEF POSIX}
  CLibPrefix = 'lib';
  CLibConnector = '.';
  CLibExtension = '.dylib';
  // On Mac OSX, cdecl names have a preceeding underscore
  // if x86 native backend.
  {$IF Defined(UNDERSCOREIMPORTNAME)}
    _PU = '_';
  {$ELSE}
    _PU = '';
  {$IFEND}
{$ENDIF}

  SLIBAVCODEC_VERSION_MAJOR    = '61';
  SLIBAVDEVICE_VERSION_MAJOR   = '61';
  SLIBAVFILTER_VERSION_MAJOR   = '10';
  SLIBAVFORMAT_VERSION_MAJOR   = '61';
  SLIBAVUTIL_VERSION_MAJOR     = '59';
  SLIBSWRESAMPLE_VERSION_MAJOR = '5';
  SLIBSWSCALE_VERSION_MAJOR    = '8';

  AVCODEC_LIBNAME    = CLibPrefix + 'avcodec'    + CLibConnector + SLIBAVCODEC_VERSION_MAJOR    + CLibExtension;
  AVDEVICE_LIBNAME   = CLibPrefix + 'avdevice'   + CLibConnector + SLIBAVDEVICE_VERSION_MAJOR   + CLibExtension;
  AVFILTER_LIBNAME   = CLibPrefix + 'avfilter'   + CLibConnector + SLIBAVFILTER_VERSION_MAJOR   + CLibExtension;
  AVFORMAT_LIBNAME   = CLibPrefix + 'avformat'   + CLibConnector + SLIBAVFORMAT_VERSION_MAJOR   + CLibExtension;
  AVUTIL_LIBNAME     = CLibPrefix + 'avutil'     + CLibConnector + SLIBAVUTIL_VERSION_MAJOR     + CLibExtension;
  SWRESAMPLE_LIBNAME = CLibPrefix + 'swresample' + CLibConnector + SLIBSWRESAMPLE_VERSION_MAJOR + CLibExtension;
  SWSCALE_LIBNAME    = CLibPrefix + 'swscale'    + CLibConnector + SLIBSWSCALE_VERSION_MAJOR    + CLibExtension;
