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
  {%H-}FFMPEG_VERSION     = '8.0';
  {%H-}program_birth_year = 2000;
  {%H-}CONFIG_THIS_YEAR   = 2025;

  // libavcodec
  LIBAVCODEC_VERSION_MAJOR = 62;
  LIBAVCODEC_VERSION_MINOR = 11;
  LIBAVCODEC_VERSION_MICRO = 100;
  LIBAVCODEC_VERSION       = '62.11.100';
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

{$IF LIBAVCODEC_VERSION_MAJOR < 63}
  {$DEFINE FF_API_INIT_PACKET}

  {$DEFINE FF_API_V408_CODECID}
  {$DEFINE FF_API_CODEC_PROPS}
  {$DEFINE FF_API_EXR_GAMMA}

  {$DEFINE FF_API_NVDEC_OLD_PIX_FMTS}

  // reminder to remove the OMX encoder on next major bump
  {$DEFINE FF_CODEC_OMX}
  // reminder to remove Sonic Lossy/Lossless encoders on next major bump
  {$DEFINE FF_CODEC_SONIC_ENC}
  // reminder to remove Sonic decoder on next-next major bump
  {$DEFINE FF_CODEC_SONIC_DEC}
{$IFEND}

  // libavdevice
  LIBAVDEVICE_VERSION_MAJOR = 62;
  LIBAVDEVICE_VERSION_MINOR = 1;
  LIBAVDEVICE_VERSION_MICRO = 100;
  LIBAVDEVICE_VERSION       = '62.1.100';
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

{$IF LIBAVDEVICE_VERSION_MAJOR < 63}
  {$DEFINE FF_API_ALSA_CHANNELS}
{$IFEND}

  // libavfilter
  LIBAVFILTER_VERSION_MAJOR  = 11;
  LIBAVFILTER_VERSION_MINOR  = 4;
  LIBAVFILTER_VERSION_MICRO  = 100;
  LIBAVFILTER_VERSION        = '11.4.100';
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

{$IF LIBAVFILTER_VERSION_MAJOR < 12}
  {$DEFINE FF_API_BUFFERSINK_OPTS}
  {$DEFINE FF_API_CONTEXT_PUBLIC}
{$IFEND}

  // libavformat
  LIBAVFORMAT_VERSION_MAJOR = 62;
  LIBAVFORMAT_VERSION_MINOR = 3;
  LIBAVFORMAT_VERSION_MICRO = 100;
  LIBAVFORMAT_VERSION       = '62.3.100';
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

{$IF LIBAVFORMAT_VERSION_MAJOR < 63}
  {$DEFINE FF_API_COMPUTE_PKT_FIELDS2}

  {$DEFINE FF_API_INTERNAL_TIMING}

  {$DEFINE FF_API_NO_DEFAULT_TLS_VERIFY}
{$IFEND}

{$DEFINE FF_API_R_FRAME_RATE}

  // libavutil
  LIBAVUTIL_VERSION_MAJOR = 60;
  LIBAVUTIL_VERSION_MINOR = 8;
  LIBAVUTIL_VERSION_MICRO = 100;
  LIBAVUTIL_VERSION       = '60.8.100';
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

{$IF LIBAVUTIL_VERSION_MAJOR < 61}
  {$DEFINE FF_API_MOD_UINTP2}
  {$DEFINE FF_API_RISCV_FD_ZBA}
  {$DEFINE FF_API_VULKAN_FIXED_QUEUES}
  {$DEFINE FF_API_OPT_INT_LIST}
  {$DEFINE FF_API_OPT_PTR}
{$IFEND}

(**
 * @}
 *)

  // libswresample
  LIBSWRESAMPLE_VERSION_MAJOR = 6;
  LIBSWRESAMPLE_VERSION_MINOR = 1;
  LIBSWRESAMPLE_VERSION_MICRO = 100;
  LIBSWRESAMPLE_VERSION       = '6.1.100';
  LIBSWRESAMPLE_VERSION_INT   = (LIBSWRESAMPLE_VERSION_MAJOR shl 16) or
                                (LIBSWRESAMPLE_VERSION_MINOR shl 8) or
                                 LIBSWRESAMPLE_VERSION_MICRO;
  {%H-}LIBSWRESAMPLE_BUILD    = LIBSWRESAMPLE_VERSION_INT;
  {%H-}LIBSWRESAMPLE_IDENT    = 'SwS' + LIBSWRESAMPLE_VERSION;

  // libswscale
  LIBSWSCALE_VERSION_MAJOR = 9;
  LIBSWSCALE_VERSION_MINOR = 1;
  LIBSWSCALE_VERSION_MICRO = 100;
  LIBSWSCALE_VERSION       = '9.1.100';
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

  SLIBAVCODEC_VERSION_MAJOR    = '62';
  SLIBAVDEVICE_VERSION_MAJOR   = '62';
  SLIBAVFILTER_VERSION_MAJOR   = '11';
  SLIBAVFORMAT_VERSION_MAJOR   = '62';
  SLIBAVUTIL_VERSION_MAJOR     = '60';
  SLIBSWRESAMPLE_VERSION_MAJOR = '6';
  SLIBSWSCALE_VERSION_MAJOR    = '9';

  AVCODEC_LIBNAME    = CLibPrefix + 'avcodec'    + CLibConnector + SLIBAVCODEC_VERSION_MAJOR    + CLibExtension;
  AVDEVICE_LIBNAME   = CLibPrefix + 'avdevice'   + CLibConnector + SLIBAVDEVICE_VERSION_MAJOR   + CLibExtension;
  AVFILTER_LIBNAME   = CLibPrefix + 'avfilter'   + CLibConnector + SLIBAVFILTER_VERSION_MAJOR   + CLibExtension;
  AVFORMAT_LIBNAME   = CLibPrefix + 'avformat'   + CLibConnector + SLIBAVFORMAT_VERSION_MAJOR   + CLibExtension;
  AVUTIL_LIBNAME     = CLibPrefix + 'avutil'     + CLibConnector + SLIBAVUTIL_VERSION_MAJOR     + CLibExtension;
  SWRESAMPLE_LIBNAME = CLibPrefix + 'swresample' + CLibConnector + SLIBSWRESAMPLE_VERSION_MAJOR + CLibExtension;
  SWSCALE_LIBNAME    = CLibPrefix + 'swscale'    + CLibConnector + SLIBSWSCALE_VERSION_MAJOR    + CLibExtension;
