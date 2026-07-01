(*
 * Immersive Audio Model and Formats helper functions and defines
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
 * Immersive Audio Model and Formats API header
 * @see <a href="https://aomediacodec.github.io/iamf/">Immersive Audio Model and Formats</a>
 *)

(*
 * FFVCL - Delphi FFmpeg VCL Components
 * http://www.DelphiFFmpeg.com
 *
 * Original file: libavutil/iamf.h
 * Ported by CodeCoolie@CNSW 2024/07/08 -> $Date:: 2025-01-17 #$
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

unit libavutil_iamf;

interface

{$I CompilerDefines.inc}

uses
  libavutil_channel_layout,
  libavutil_dict,
  libavutil_log,
  libavutil_rational,
  FFTypes;

{$I libversion.inc}

(**
 * @defgroup lavu_iamf Immersive Audio Model and Formats
 * @ingroup lavu_audio
 *
 * Immersive Audio Model and Formats related functions and defines
 *
 * @defgroup lavu_iamf_params Parameter Definition
 * @ingroup lavu_iamf
 * @{
 * Parameters as defined in section 3.6.1 and 3.8 of IAMF.
 * @}
 *
 * @defgroup lavu_iamf_audio Audio Element
 * @ingroup lavu_iamf
 * @{
 * Audio Elements as defined in section 3.6 of IAMF.
 * @}
 *
 * @defgroup lavu_iamf_mix Mix Presentation
 * @ingroup lavu_iamf
 * @{
 * Mix Presentations as defined in section 3.7 of IAMF.
 * @}
 *
 * @addtogroup lavu_iamf_params
 * @{
 *)
type
  TAVIAMFAnimationType = (
    AV_IAMF_ANIMATION_TYPE_STEP,
    AV_IAMF_ANIMATION_TYPE_LINEAR,
    AV_IAMF_ANIMATION_TYPE_BEZIER
  );

(**
 * Mix Gain Parameter Data as defined in section 3.8.1 of IAMF.
 *
 * @note This struct's size is not a part of the public ABI.
 *)
  TAVIAMFMixGain = record
    av_class: PAVClass;

    (**
     * Duration for the given subblock, in units of
     * 1 / @ref AVIAMFParamDefinition.parameter_rate "parameter_rate".
     * It must not be 0.
     *)
    subblock_duration: Cardinal;
    (**
     * The type of animation applied to the parameter values.
     *)
    animation_type: TAVIAMFAnimationType;
    (**
     * Parameter value that is applied at the start of the subblock.
     * Applies to all defined Animation Types.
     *
     * Valid range of values is -128.0 to 128.0
     *)
    start_point_value: TAVRational;
    (**
     * Parameter value that is applied at the end of the subblock.
     * Applies only to AV_IAMF_ANIMATION_TYPE_LINEAR and
     * AV_IAMF_ANIMATION_TYPE_BEZIER Animation Types.
     *
     * Valid range of values is -128.0 to 128.0
     *)
    end_point_value: TAVRational;
    (**
     * Parameter value of the middle control point of a quadratic Bezier
     * curve, i.e., its y-axis value.
     * Applies only to AV_IAMF_ANIMATION_TYPE_BEZIER Animation Type.
     *
     * Valid range of values is -128.0 to 128.0
     *)
    control_point_value: TAVRational;
    (**
     * Parameter value of the time of the middle control point of a
     * quadratic Bezier curve, i.e., its x-axis value.
     * Applies only to AV_IAMF_ANIMATION_TYPE_BEZIER Animation Type.
     *
     * Valid range of values is 0.0 to 1.0
     *)
    control_point_relative_time: TAVRational;
  end;

(**
 * Demixing Info Parameter Data as defined in section 3.8.2 of IAMF.
 *
 * @note This struct's size is not a part of the public ABI.
 *)
  TAVIAMFDemixingInfo = record
    av_class: PAVClass;

    (**
     * Duration for the given subblock, in units of
     * 1 / @ref AVIAMFParamDefinition.parameter_rate "parameter_rate".
     * It must not be 0.
     *)
    subblock_duration: Cardinal;
    (**
     * Pre-defined combination of demixing parameters.
     *)
    dmixp_mode: Cardinal;
  end;

(**
 * Recon Gain Info Parameter Data as defined in section 3.8.3 of IAMF.
 *
 * @note This struct's size is not a part of the public ABI.
 *)
  TAVIAMFReconGain = record
    av_class: PAVClass;

    (**
     * Duration for the given subblock, in units of
     * 1 / @ref AVIAMFParamDefinition.parameter_rate "parameter_rate".
     * It must not be 0.
     *)
    subblock_duration: Cardinal;

    (**
     * Array of gain values to be applied to each channel for each layer
     * defined in the Audio Element referencing the parent Parameter Definition.
     * Values for layers where the AV_IAMF_LAYER_FLAG_RECON_GAIN flag is not set
     * are undefined.
     *
     * Channel order is: FL, C, FR, SL, SR, TFL, TFR, BL, BR, TBL, TBR, LFE
     *)
    recon_gain: array[0..5] of array[0..11] of Byte;
  end;

  TAVIAMFParamDefinitionType = (
   (**
    * Subblocks are of struct type AVIAMFMixGain
    *)
    AV_IAMF_PARAMETER_DEFINITION_MIX_GAIN,
   (**
    * Subblocks are of struct type AVIAMFDemixingInfo
    *)
    AV_IAMF_PARAMETER_DEFINITION_DEMIXING,
   (**
    * Subblocks are of struct type AVIAMFReconGain
    *)
    AV_IAMF_PARAMETER_DEFINITION_RECON_GAIN
  );

(**
 * Parameters as defined in section 3.6.1 of IAMF.
 *
 * The struct is allocated by av_iamf_param_definition_alloc() along with an
 * array of subblocks, its type depending on the value of type.
 * This array is placed subblocks_offset bytes after the start of this struct.
 *
 * @note This struct's size is not a part of the public ABI.
 *)
  PAVIAMFParamDefinition = ^TAVIAMFParamDefinition;
  TAVIAMFParamDefinition = record
    av_class: PAVClass;

    (**
     * Offset in bytes from the start of this struct, at which the subblocks
     * array is located.
     *)
    subblocks_offset: Size_t;
    (**
     * Size in bytes of each element in the subblocks array.
     *)
    subblock_size: Size_t;
    (**
     * Number of subblocks in the array.
     *)
    nb_subblocks: Cardinal;

    (**
     * Parameters type. Determines the type of the subblock elements.
     *)
    type_: TAVIAMFParamDefinitionType;

    (**
     * Identifier for the paremeter substream.
     *)
    parameter_id: Cardinal;
    (**
     * Sample rate for the paremeter substream. It must not be 0.
     *)
    parameter_rate: Cardinal;

    (**
     * The accumulated duration of all blocks in this parameter definition,
     * in units of 1 / @ref parameter_rate.
     *
     * May be 0, in which case all duration values should be specified in
     * another parameter definition referencing the same parameter_id.
     *)
    duration: Cardinal;
    (**
     * The duration of every subblock in the case where all subblocks, with
     * the optional exception of the last subblock, have equal durations.
     *
     * Must be 0 if subblocks have different durations.
     *)
    constant_subblock_duration: Cardinal;
  end;

function av_iamf_param_definition_get_class(): PAVClass; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_param_definition_get_class';

(**
 * Allocates memory for AVIAMFParamDefinition, plus an array of {@code nb_subblocks}
 * amount of subblocks of the given type and initializes the variables. Can be
 * freed with a normal av_free() call.
 *
 * @param size if non-NULL, the size in bytes of the resulting data array is written here.
 *)
function av_iamf_param_definition_alloc(type_: TAVIAMFParamDefinitionType;
                           nb_subblocks: Cardinal; size: PSize_t): PAVIAMFParamDefinition; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_param_definition_alloc';

(**
 * Get the subblock at the specified {@code idx}. Must be between 0 and nb_subblocks - 1.
 *
 * The @ref AVIAMFParamDefinition.type "param definition type" defines
 * the struct type of the returned pointer.
 *)
//function av_iamf_param_definition_get_subblock(const par: PAVIAMFParamDefinition; idx: Cardinal): Pointer;
{
    av_assert0(idx < par->nb_subblocks);
    return (void *)((uint8_t *)par + par->subblocks_offset + idx * par->subblock_size);
}

(**
 * @}
 * @addtogroup lavu_iamf_audio
 * @{
 *)
type
  TAVIAMFAmbisonicsMode = (
    AV_IAMF_AMBISONICS_MODE_MONO,
    AV_IAMF_AMBISONICS_MODE_PROJECTION
  );

(**
 * Recon gain information for the layer is present in AVIAMFReconGain
 *)
//  AV_IAMF_LAYER_FLAG_RECON_GAIN = (1 shl 0);

(**
 * A layer defining a Channel Layout in the Audio Element.
 *
 * When @ref AVIAMFAudioElement.audio_element_type "the parent's Audio Element type"
 * is AV_IAMF_AUDIO_ELEMENT_TYPE_CHANNEL, this corresponds to an Scalable Channel
 * Layout layer as defined in section 3.6.2 of IAMF.
 * For AV_IAMF_AUDIO_ELEMENT_TYPE_SCENE, it is an Ambisonics channel
 * layout as defined in section 3.6.3 of IAMF.
 *
 * @note The struct should be allocated with av_iamf_audio_element_add_layer()
 *       and its size is not a part of the public ABI.
 *)
  PPAVIAMFLayer = ^PAVIAMFLayer;
  PAVIAMFLayer = ^TAVIAMFLayer;
  TAVIAMFLayer = record
    av_class: PAVClass;

    ch_layout: TAVChannelLayout;

    (**
     * A bitmask which may contain a combination of AV_IAMF_LAYER_FLAG_* flags.
     *)
    flags: Cardinal;
    (**
     * Output gain channel flags as defined in section 3.6.2 of IAMF.
     *
     * This field is defined only if @ref AVIAMFAudioElement.audio_element_type
     * "the parent's Audio Element type" is AV_IAMF_AUDIO_ELEMENT_TYPE_CHANNEL,
     * must be 0 otherwise.
     *)
    output_gain_flags: Cardinal;
    (**
     * Output gain as defined in section 3.6.2 of IAMF.
     *
     * Must be 0 if @ref output_gain_flags is 0.
     *)
    output_gain: TAVRational;
    (**
     * Ambisonics mode as defined in section 3.6.3 of IAMF.
     *
     * This field is defined only if @ref AVIAMFAudioElement.audio_element_type
     * "the parent's Audio Element type" is AV_IAMF_AUDIO_ELEMENT_TYPE_SCENE.
     *
     * If AV_IAMF_AMBISONICS_MODE_MONO, channel_mapping is defined implicitly
     * (Ambisonic Order) or explicitly (Custom Order with ambi channels) in
     * @ref ch_layout.
     * If AV_IAMF_AMBISONICS_MODE_PROJECTION, @ref demixing_matrix must be set.
     *)
    ambisonics_mode: TAVIAMFAmbisonicsMode;

    (**
     * Demixing matrix as defined in section 3.6.3 of IAMF.
     *
     * The length of the array is ch_layout.nb_channels multiplied by the sum of
     * the amount of streams in the group plus the amount of streams in the group
     * that are stereo.
     *
     * May be set only if @ref ambisonics_mode == AV_IAMF_AMBISONICS_MODE_PROJECTION,
     * must be NULL otherwise.
     *)
    demixing_matrix: PAVRational;
  end;

  TAVIAMFAudioElementType = (
    AV_IAMF_AUDIO_ELEMENT_TYPE_CHANNEL,
    AV_IAMF_AUDIO_ELEMENT_TYPE_SCENE
  );

(**
 * Information on how to combine one or more audio streams, as defined in
 * section 3.6 of IAMF.
 *
 * @note The struct should be allocated with av_iamf_audio_element_alloc()
 *       and its size is not a part of the public ABI.
 *)
  PPAVIAMFAudioElement = ^PAVIAMFAudioElement;
  PAVIAMFAudioElement = ^TAVIAMFAudioElement;
  TAVIAMFAudioElement = record
    av_class: PAVClass;

    layers: PPAVIAMFLayer;
    (**
     * Number of layers, or channel groups, in the Audio Element.
     * There may be 6 layers at most, and for @ref audio_element_type
     * AV_IAMF_AUDIO_ELEMENT_TYPE_SCENE, there may be exactly 1.
     *
     * Set by av_iamf_audio_element_add_layer(), must not be
     * modified by any other code.
     *)
    nb_layers: Cardinal;

    (**
     * Demixing information used to reconstruct a scalable channel audio
     * representation.
     * The @ref AVIAMFParamDefinition.type "type" must be
     * AV_IAMF_PARAMETER_DEFINITION_DEMIXING.
     *)
    demixing_info: PAVIAMFParamDefinition;
    (**
     * Recon gain information used to reconstruct a scalable channel audio
     * representation.
     * The @ref AVIAMFParamDefinition.type "type" must be
     * AV_IAMF_PARAMETER_DEFINITION_RECON_GAIN.
     *)
    recon_gain_info: PAVIAMFParamDefinition;

    (**
     * Audio element type as defined in section 3.6 of IAMF.
     *)
    audio_element_type: TAVIAMFAudioElementType;

    (**
     * Default weight value as defined in section 3.6 of IAMF.
     *)
    default_w: Cardinal;
  end;

function av_iamf_audio_element_get_class(): PAVClass; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_audio_element_get_class';

(**
 * Allocates a AVIAMFAudioElement, and initializes its fields with default values.
 * No layers are allocated. Must be freed with av_iamf_audio_element_free().
 *
 * @see av_iamf_audio_element_add_layer()
 *)
function av_iamf_audio_element_alloc(): PAVIAMFAudioElement; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_audio_element_alloc';

(**
 * Allocate a layer and add it to a given AVIAMFAudioElement.
 * It is freed by av_iamf_audio_element_free() alongside the rest of the parent
 * AVIAMFAudioElement.
 *
 * @return a pointer to the allocated layer.
 *)
function av_iamf_audio_element_add_layer(audio_element: PAVIAMFAudioElement): PAVIAMFLayer; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_audio_element_add_layer';

(**
 * Free an AVIAMFAudioElement and all its contents.
 *
 * @param audio_element pointer to pointer to an allocated AVIAMFAudioElement.
 *                      upon return, *audio_element will be set to NULL.
 *)
procedure av_iamf_audio_element_free(audio_element: PPAVIAMFAudioElement); cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_audio_element_free';

(**
 * @}
 * @addtogroup lavu_iamf_mix
 * @ begin
 *)
type
  TAVIAMFHeadphonesMode = (
    (**
     * The referenced Audio Element shall be rendered to stereo loudspeakers.
     *)
    AV_IAMF_HEADPHONES_MODE_STEREO,
    (**
     * The referenced Audio Element shall be rendered with a binaural renderer.
     *)
    AV_IAMF_HEADPHONES_MODE_BINAURAL
  );

(**
 * Submix element as defined in section 3.7 of IAMF.
 *
 * @note The struct should be allocated with av_iamf_submix_add_element()
 *       and its size is not a part of the public ABI.
 *)
  PPAVIAMFSubmixElement = ^PAVIAMFSubmixElement;
  PAVIAMFSubmixElement = ^TAVIAMFSubmixElement;
  TAVIAMFSubmixElement = record
    av_class: PAVClass;

    (**
     * The id of the Audio Element this submix element references.
     *)
    audio_element_id: Cardinal;

    (**
     * Information required required for applying any processing to the
     * referenced and rendered Audio Element before being summed with other
     * processed Audio Elements.
     * The @ref AVIAMFParamDefinition.type "type" must be
     * AV_IAMF_PARAMETER_DEFINITION_MIX_GAIN.
     *)
    element_mix_config: PAVIAMFParamDefinition;

    (**
     * Default mix gain value to apply when there are no AVIAMFParamDefinition
     * with @ref element_mix_config "element_mix_config's"
     * @ref AVIAMFParamDefinition.parameter_id "parameter_id" available for a
     * given audio frame.
     *)
    default_mix_gain: TAVRational;

    (**
     * A value that indicates whether the referenced channel-based Audio Element
     * shall be rendered to stereo loudspeakers or spatialized with a binaural
     * renderer when played back on headphones.
     * If the Audio Element is not of @ref AVIAMFAudioElement.audio_element_type
     * "type" AV_IAMF_AUDIO_ELEMENT_TYPE_CHANNEL, then this field is undefined.
     *)
    headphones_rendering_mode: TAVIAMFHeadphonesMode;

    (**
     * A dictionary of strings describing the submix in different languages.
     * Must have the same amount of entries as
     * @ref AVIAMFMixPresentation.annotations "the mix's annotations", stored
     * in the same order, and with the same key strings.
     *
     * @ref AVDictionaryEntry.key "key" is a string conforming to BCP-47 that
     * specifies the language for the string stored in
     * @ref AVDictionaryEntry.value "value".
     *)
    annotations: PAVDictionary;
  end;

  PPAVIAMFSubmixLayout = ^PAVIAMFSubmixLayout;
  PAVIAMFSubmixLayout = ^TAVIAMFSubmixLayout;
  TAVIAMFSubmixLayoutType = (
    (**
     * The layout follows the loudspeaker sound system convention of ITU-2051-3.
     *)
    AV_IAMF_SUBMIX_LAYOUT_TYPE_LOUDSPEAKERS = 2,
    (**
     * The layout is binaural.
     *)
    AV_IAMF_SUBMIX_LAYOUT_TYPE_BINAURAL = 3
  );

(**
 * Submix layout as defined in section 3.7.6 of IAMF.
 *
 * @note The struct should be allocated with av_iamf_submix_add_layout()
 *       and its size is not a part of the public ABI.
 *)
  TAVIAMFSubmixLayout = record
    av_class: PAVClass;

    layout_type: TAVIAMFSubmixLayoutType;

    (**
     * Channel layout matching one of Sound Systems A to J of ITU-2051-3, plus
     * 7.1.2ch and 3.1.2ch
     * If layout_type is not AV_IAMF_SUBMIX_LAYOUT_TYPE_LOUDSPEAKERS, this field
     * is undefined.
     *)
    sound_system: TAVChannelLayout;
    (**
     * The program integrated loudness information, as defined in
     * ITU-1770-4.
     *)
    integrated_loudness: TAVRational;
    (**
     * The digital (sampled) peak value of the audio signal, as defined
     * in ITU-1770-4.
     *)
    digital_peak: TAVRational;
    (**
     * The true peak of the audio signal, as defined in ITU-1770-4.
     *)
    true_peak: TAVRational;
    (**
     * The Dialogue loudness information, as defined in ITU-1770-4.
     *)
    dialogue_anchored_loudness: TAVRational;
    (**
     * The Album loudness information, as defined in ITU-1770-4.
     *)
    album_anchored_loudness: TAVRational;
  end;

(**
 * Submix layout as defined in section 3.7 of IAMF.
 *
 * @note The struct should be allocated with av_iamf_mix_presentation_add_submix()
 *       and its size is not a part of the public ABI.
 *)
  PPAVIAMFSubmix = ^PAVIAMFSubmix;
  PAVIAMFSubmix = ^TAVIAMFSubmix;
  TAVIAMFSubmix = record
    av_class: PAVClass;

    (**
     * Array of submix elements.
     *
     * Set by av_iamf_submix_add_element(), must not be modified by any
     * other code.
     *)
    elements: PPAVIAMFSubmixElement;
    (**
     * Number of elements in the submix.
     *
     * Set by av_iamf_submix_add_element(), must not be modified by any
     * other code.
     *)
    nb_elements: Cardinal;

    (**
     * Array of submix layouts.
     *
     * Set by av_iamf_submix_add_layout(), must not be modified by any
     * other code.
     *)
    layouts: PPAVIAMFSubmixLayout;
    (**
     * Number of layouts in the submix.
     *
     * Set by av_iamf_submix_add_layout(), must not be modified by any
     * other code.
     *)
    nb_layouts: Cardinal;

    (**
     * Information required for post-processing the mixed audio signal to
     * generate the audio signal for playback.
     * The @ref AVIAMFParamDefinition.type "type" must be
     * AV_IAMF_PARAMETER_DEFINITION_MIX_GAIN.
     *)
    output_mix_config: PAVIAMFParamDefinition;

    (**
     * Default mix gain value to apply when there are no AVIAMFParamDefinition
     * with @ref output_mix_config "output_mix_config's"
     * @ref AVIAMFParamDefinition.parameter_id "parameter_id" available for a
     * given audio frame.
     *)
    default_mix_gain: TAVRational;
  end;

(**
 * Information on how to render and mix one or more AVIAMFAudioElement to generate
 * the final audio output, as defined in section 3.7 of IAMF.
 *
 * @note The struct should be allocated with av_iamf_mix_presentation_alloc()
 *       and its size is not a part of the public ABI.
 *)
  PPAVIAMFMixPresentation = ^PAVIAMFMixPresentation;
  PAVIAMFMixPresentation = ^TAVIAMFMixPresentation;
  TAVIAMFMixPresentation = record
    av_class: PAVClass;

    (**
     * Array of submixes.
     *
     * Set by av_iamf_mix_presentation_add_submix(), must not be modified
     * by any other code.
     *)
    submixes: PPAVIAMFSubmix;
    (**
     * Number of submixes in the presentation.
     *
     * Set by av_iamf_mix_presentation_add_submix(), must not be modified
     * by any other code.
     *)
    nb_submixes: Cardinal;

    (**
     * A dictionary of strings describing the mix in different languages.
     * Must have the same amount of entries as every
     * @ref AVIAMFSubmixElement.annotations "Submix element annotations",
     * stored in the same order, and with the same key strings.
     *
     * @ref AVDictionaryEntry.key "key" is a string conforming to BCP-47
     * that specifies the language for the string stored in
     * @ref AVDictionaryEntry.value "value".
     *)
    annotations: PAVDictionary;
  end;

function av_iamf_mix_presentation_get_class(): PAVClass; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_mix_presentation_get_class';

(**
 * Allocates a AVIAMFMixPresentation, and initializes its fields with default
 * values. No submixes are allocated.
 * Must be freed with av_iamf_mix_presentation_free().
 *
 * @see av_iamf_mix_presentation_add_submix()
 *)
function av_iamf_mix_presentation_alloc(): PAVIAMFMixPresentation; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_mix_presentation_alloc';

(**
 * Allocate a submix and add it to a given AVIAMFMixPresentation.
 * It is freed by av_iamf_mix_presentation_free() alongside the rest of the
 * parent AVIAMFMixPresentation.
 *
 * @return a pointer to the allocated submix.
 *)
function av_iamf_mix_presentation_add_submix(mix_presentation: PAVIAMFMixPresentation): PAVIAMFSubmix; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_mix_presentation_add_submix';

(**
 * Allocate a submix element and add it to a given AVIAMFSubmix.
 * It is freed by av_iamf_mix_presentation_free() alongside the rest of the
 * parent AVIAMFSubmix.
 *
 * @return a pointer to the allocated submix.
 *)
function av_iamf_submix_add_element(submix: PAVIAMFSubmix): PAVIAMFSubmixElement; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_submix_add_element';

(**
 * Allocate a submix layout and add it to a given AVIAMFSubmix.
 * It is freed by av_iamf_mix_presentation_free() alongside the rest of the
 * parent AVIAMFSubmix.
 *
 * @return a pointer to the allocated submix.
 *)
function av_iamf_submix_add_layout(submix: PAVIAMFSubmix): PAVIAMFSubmixLayout; cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_submix_add_layout';

(**
 * Free an AVIAMFMixPresentation and all its contents.
 *
 * @param mix_presentation pointer to pointer to an allocated AVIAMFMixPresentation.
 *                         upon return, *mix_presentation will be set to NULL.
 *)
procedure av_iamf_mix_presentation_free(mix_presentation: PPAVIAMFMixPresentation); cdecl; external AVUTIL_LIBNAME name _PU + 'av_iamf_mix_presentation_free';
(**
 * @}
 *)

function av_iamf_param_definition_get_subblock(const par: PAVIAMFParamDefinition; idx: Cardinal): Pointer;

implementation

function av_iamf_param_definition_get_subblock(const par: PAVIAMFParamDefinition; idx: Cardinal): Pointer;
var
  P: PAnsiChar;
begin
  Assert(idx < par.nb_subblocks);
  P := PAnsiChar(par);
  Inc(P, par.subblocks_offset + idx * par.subblock_size);
  Result := P;
end;

end.
