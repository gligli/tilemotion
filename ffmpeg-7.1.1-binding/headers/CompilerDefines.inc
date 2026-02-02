{$IFDEF CONDITIONALEXPRESSIONS}
  // Must be at the top...
  {$IF CompilerVersion >= 24.0}
    {$LEGACYIFEND ON}
  {$IFEND}
{$ENDIF}

{$IFNDEF DEBUG}
  // Enabling range checking slows down your program and makes it somewhat larger.
  {$RANGECHECKS OFF} // {$R-}
  // Enabling overflow checking slows down your program and makes it somewhat larger, so use {$Q+} only for debugging.
  {$OVERFLOWCHECKS OFF} // {$Q-}
{$ENDIF}

// compatible with C libraries
{$ALIGN 8}
{$MINENUMSIZE 4}

// When generating C++Builder output files, certain workarounds to compiler
// problems need to be enabled! When invoking DCC on the command-line, use
// the -DBCB parameter. When invoking MSBUILD, include the DCC_Define="BCB"
// attribute in the /p parameter.
{$IFDEF BCB}
  {$DEFINE CBUILDER}
{$ELSE}
  {$DEFINE DELPHI}
{$ENDIF}

// Define for Delphi to auto-generate platform-appropriate '#pragma link' statements in HPP files
{$UNDEF HAS_DIRECTIVE_HPPEMIT_LINKUNIT}

// detect compiler versions

{$IFNDEF FPC}

{$IFNDEF CONDITIONALEXPRESSIONS}
  {$I 'ERROR: FFVCL needs Delphi 6 & C++Builder 2007 or above'}
{$ENDIF}

{$IFNDEF CPUX64}
  {$IFNDEF CPUX86}
    {$DEFINE CPUX86}
  {$ENDIF}
{$ENDIF}

//Delphi & C++Builder 6
{$IFDEF VER140}
  {$DEFINE DCC}
  {$DEFINE VCL_60}
  {$IFDEF CBUILDER}
    {$I 'ERROR: FFVCL needs C++Builder 2007 or above'}
  {$ELSE}
    {$DEFINE DELPHI_6}
  {$ENDIF}
{$ENDIF}

//Delphi 7
{$IFDEF VER150}
  {$DEFINE DCC}
  {$DEFINE VCL_70}
  {$DEFINE DELPHI_7} // there was no C++ Builder 7
{$ENDIF}

//Delphi 8
{$IFDEF VER160}
  {$DEFINE DCC}
  {$DEFINE VCL_80}
  {$DEFINE DELPHI_8} // there was no C++ Builder 8
{$ENDIF}

//Delphi 2005
{$IFDEF VER170}
  {$DEFINE DCC}
  {$DEFINE VCL_2005}
  {$DEFINE DELPHI_2005} // there was no C++Builder 2005
{$ENDIF}

// NOTE: CodeGear decided to make Highlander be a non-breaking release
// (no interface changes, thus fully backwards compatible without any
// end user code changes), so VER180 applies to both BDS 2006 and
// Highlander prior to the release of RAD Studio 2007.  Use VER185 to
// identify Highlanger specifically.

//Delphi & C++Builder 2006
//Delphi & C++Builder 2007 (initial release)
{$IFDEF VER180}
  {$DEFINE DCC}
  {$DEFINE VCL_2006}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_2006}
  {$ELSE}
    {$DEFINE DELPHI_2006}
  {$ENDIF}
{$ENDIF}

//Delphi & C++Builder 2007 (final release)
{$IFDEF VER185}
  {$DEFINE DCC}
  {$UNDEF VCL_2006}
  {$DEFINE VCL_2007}
  {$IFDEF CBUILDER}
    {$UNDEF CBUILDER_2006}
    {$DEFINE CBUILDER_2007}
  {$ELSE}
    {$UNDEF DELPHI_2006}
    {$DEFINE DELPHI_2007}
  {$ENDIF}
{$ENDIF}

// BDS 2007 NET personality uses VER190 instead of 185.
//Delphi .NET 2007
{$IFDEF VER190}
  {$DEFINE DCC}
  {$IFDEF CIL}
    //Delphi 2007
    {$DEFINE VCL_2007}
    {$DEFINE DELPHI_2007}
  {$ENDIF}
{$ENDIF}

//Delphi & C++Builder 2009
{$IFDEF VER200}
  {$DEFINE DCC}
  {$DEFINE VCL_2009}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_2009}
  {$ELSE}
    {$DEFINE DELPHI_2009}
  {$ENDIF}
{$ENDIF}

//Delphi & C++Builder 2010
{$IFDEF VER210}
  {$DEFINE DCC}
  {$DEFINE VCL_2010}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_2010}
  {$ELSE}
    {$DEFINE DELPHI_2010}
  {$ENDIF}
{$ENDIF}

//Delphi & C++Builder XE
{$IFDEF VER220}
  {$IFNDEF DCC}
    {$DEFINE DCC}
  {$ENDIF}
  {$DEFINE VCL_XE}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE}
  {$ELSE}
    {$DEFINE DELPHI_XE}
  {$ENDIF}
{$ENDIF}

// DCC is now defined by the Delphi compiler starting in XE2

//Delphi & CBuilder XE2
{$IFDEF VER230}
  {$DEFINE VCL_XE2}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE2}
  {$ELSE}
    {$DEFINE DELPHI_XE2}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder XE3
//Delphi & CBuilder XE3.5 (early betas only)
{$IFDEF VER240}
  {$DEFINE VCL_XE3}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE3}
  {$ELSE}
    {$DEFINE DELPHI_XE3}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder XE4
{$IFDEF VER250}
  {$UNDEF VCL_XE3}
  {$DEFINE VCL_XE4}
  {$IFDEF CBUILDER}
    {$UNDEF CBUILDER_XE3}
    {$DEFINE CBUILDER_XE4}
  {$ELSE}
    {$UNDEF DELPHI_XE3}
    {$DEFINE DELPHI_XE4}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder XE5
{$IFDEF VER260}
  {$DEFINE VCL_XE5}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE5}
  {$ELSE}
    {$DEFINE DELPHI_XE5}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder AppMethod
//AppMethod is just XE5 for mobile only, VCL is removed
{$IFDEF VER265}
  {$DEFINE VCL_XE5}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE5}
  {$ELSE}
    {$DEFINE DELPHI_XE5}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder XE6
{$IFDEF VER270}
  {$DEFINE VCL_XE6}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE6}
  {$ELSE}
    {$DEFINE DELPHI_XE6}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder XE7
{$IFDEF VER280}
  {$DEFINE VCL_XE7}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE7}
  {$ELSE}
    {$DEFINE DELPHI_XE7}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder XE8
{$IFDEF VER290}
  {$DEFINE VCL_XE8}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_XE8}
  {$ELSE}
    {$DEFINE DELPHI_XE8}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 10.0 Seattle
{$IFDEF VER300}
  {$DEFINE VCL_10_0}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_VCL_10_0}
  {$ELSE}
    {$DEFINE DELPHI_VCL_10_0}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 10.1 Berlin
{$IFDEF VER310}
  {$DEFINE VCL_10_1}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_10_1}
  {$ELSE}
    {$DEFINE DELPHI_10_1}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 10.2 Tokyo
{$IFDEF VER320}
  {$DEFINE VCL_10_2}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_10_2}
  {$ELSE}
    {$DEFINE DELPHI_10_2}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 10.3 Rio
{$IFDEF VER330}
  {$DEFINE VCL_10_3}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_10_3}
  {$ELSE}
    {$DEFINE DELPHI_10_3}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 10.4 Sydney
{$IFDEF VER340}
  {$DEFINE VCL_10_4}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_10_4}
  {$ELSE}
    {$DEFINE DELPHI_10_4}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 11.0 Alexandria
{$IFDEF VER350}
  {$DEFINE VCL_11}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_11}
  {$ELSE}
    {$DEFINE DELPHI_11}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 12.0 Athens
{$IFDEF VER360}
  {$DEFINE VCL_12}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_12}
  {$ELSE}
    {$DEFINE DELPHI_12}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 13.0 Florence
{$IFDEF VER370}
  {$DEFINE VCL_13}
  {$IFDEF CBUILDER}
    {$DEFINE CBUILDER_13}
  {$ELSE}
    {$DEFINE DELPHI_13}
  {$ENDIF}
{$ENDIF}

//Delphi & CBuilder 14.0+ (future releases)
{$IFDEF CONDITIONALEXPRESSIONS}
  {$IF CompilerVersion >= 38}
    {$MESSAGE WARN 'Unknown compiler version detected! Assuming >= 14.x '}
    {$DEFINE VCL_UNKNOWN_VERSION}
    {$DEFINE VCL_14}
    {$IFDEF CBUILDER}
      {$DEFINE CBUILDER_14}
    {$ELSE}
      {$DEFINE DELPHI_14}
    {$ENDIF}
  {$IFEND}
{$ENDIF}

{$ENDIF}

// FPC (2.6.0+)

{$IFDEF FPC}
  // FPC_FULLVERSION was added in FPC 2.2.4
  // Have to use Defined() or else Delphi compiler chokes, since it
  // evaluates $IF statements before $IFDEF statements...
  {$MACRO ON} // must be on in order to use versioning macros
  {$IFNDEF FPC_FULLVERSION}
    {$ERROR FFVCL needs version 2.6.0 or above}
  {$ENDIF}
  {$IF DEFINED(FPC_FULLVERSION) AND (FPC_FULLVERSION < 20600)}
    {$ERROR FFVCL needs version 2.6.0 or above}
  {$IFEND}
  {$MODE Delphi}
  {$ASMMODE Intel}
  {$GOTO ON}           // alow goto
  {$PACKRECORDS 8}     // same as ALIGN 8 for Delphi, it will be reset to default by $MODE
  {$PACKENUM 4}        // same as MINENUMSIZE 4 for Delphi, it will be reset to default by $MODE
  {$CALLING REGISTER}  // default calling convention is register
  {$DEFINE VCL_70}
  {$DEFINE DELPHI_7}
  {$IFDEF CPUX86_64}
    {$DEFINE CPUX64}
  {$ELSE}
    {$DEFINE CPUX86}
  {$ENDIF}
  {$WARN 4055 off : Conversion between ordinals and pointers is not portable}
{$ENDIF}

// end FPC

{$IFDEF VCL_14}
  {$DEFINE VCL_14_OR_ABOVE}
{$ENDIF}

{$IFDEF VCL_14_OR_ABOVE}
  {$DEFINE VCL_13_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_13}
    {$DEFINE VCL_13_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_13_OR_ABOVE}
  {$DEFINE VCL_12_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_12}
    {$DEFINE VCL_12_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_12_OR_ABOVE}
  {$DEFINE VCL_11_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_11}
    {$DEFINE VCL_11_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_11_OR_ABOVE}
  {$DEFINE VCL_10_4_OR_ABOVE}
  {$DEFINE VCL_10_4_UPDATE2_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_10_4}
    {$DEFINE VCL_10_4_OR_ABOVE}
    // TODO: figure out how to detect this version
    {.$DEFINE VCL_10_4_UPDATE2_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_4_OR_ABOVE}
  {$DEFINE VCL_10_3_OR_ABOVE}
  {$DEFINE VCL_10_3_UPDATE2_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_10_3}
    {$DEFINE VCL_10_3_OR_ABOVE}
    // TODO: figure out how to detect this version
    {.$DEFINE VCL_10_3_UPDATE2_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_3_OR_ABOVE}
  {$DEFINE VCL_10_2_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_10_2}
    {$DEFINE VCL_10_2_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_2_OR_ABOVE}
  {$DEFINE VCL_10_1_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_10_1}
    {$DEFINE VCL_10_1_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_1_OR_ABOVE}
  {$DEFINE VCL_10_0_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_10_0}
    {$DEFINE VCL_10_0_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_0_OR_ABOVE}
  {$DEFINE VCL_XE8_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE8}
    {$DEFINE VCL_XE8_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE8_OR_ABOVE}
  {$DEFINE VCL_XE7_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE7}
    {$DEFINE VCL_XE7_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE7_OR_ABOVE}
  {$DEFINE VCL_XE6_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE6}
    {$DEFINE VCL_XE6_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE6_OR_ABOVE}
  {$DEFINE VCL_XE5_OR_ABOVE}
  {$DEFINE VCL_XE5_UPDATE2_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE5}
    {$DEFINE VCL_XE5_OR_ABOVE}
    // TODO: figure out how to detect this version
    {.$DEFINE VCL_XE5_UPDATE2_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE5_OR_ABOVE}
  {$DEFINE VCL_XE4_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE4}
    {$DEFINE VCL_XE4_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE4_OR_ABOVE}
  {$DEFINE VCL_XE3_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE3}
    {$DEFINE VCL_XE3_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE3_OR_ABOVE}
  {$DEFINE VCL_XE2_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE2}
    {$DEFINE VCL_XE2_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE2_OR_ABOVE}
  {$DEFINE VCL_XE_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_XE}
    {$DEFINE VCL_XE_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE_OR_ABOVE}
  {$DEFINE VCL_2010_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_2010}
    {$DEFINE VCL_2010_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2010_OR_ABOVE}
  {$DEFINE VCL_2009_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_2009}
    {$DEFINE VCL_2009_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2009_OR_ABOVE}
  {$DEFINE VCL_2007_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_2007}
    {$DEFINE VCL_2007_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2007_OR_ABOVE}
  {$DEFINE VCL_2006_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_2006}
    {$DEFINE VCL_2006_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2006_OR_ABOVE}
  {$DEFINE VCL_2005_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_2005}
    {$DEFINE VCL_2005_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2005_OR_ABOVE}
  {$DEFINE VCL_8_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_80}
    {$DEFINE VCL_8_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_8_OR_ABOVE}
  {$DEFINE VCL_7_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_70}
    {$DEFINE VCL_7_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_7_OR_ABOVE}
  {$DEFINE VCL_6_OR_ABOVE}
{$ELSE}
  {$IFDEF VCL_60}
    {$DEFINE VCL_6_OR_ABOVE}
  {$ENDIF}
{$ENDIF}

// just in case
{$IFNDEF VCL_6_OR_ABOVE}
  {$I 'ERROR: FFVCL needs Delphi 6 & C++Builder 2007 or above'}
{$ENDIF}

// Check for available features

{$IFDEF CBUILDER}
  // When generating a C++ HPP file, if a class has no explicit constructor
  // defined and contains compiler-managed members (xxxString, TDateTime,
  // Variant, DelphiInterface, etc), the HPP will contain a forwarding
  // inline constructor that implicitly initializes those managed members,
  // which will overwrite any non-default initializations performed inside
  // of InitComponent() overrides! In this situation, the workaround is to
  // define an explicit constructor that calls the base class constructor
  // manually, allowing those managed members to be initialized by the
  // compiler before InitComponent() overrides then re-assign them.
  {$DEFINE WORKAROUND_INLINE_CONSTRUCTORS}
{$ENDIF}

{$IFDEF VCL_6_OR_ABOVE}
  {$IFNDEF FPC}
    {$IFNDEF KYLIX}
      {$DEFINE HAS_RemoveFreeNotification}
    {$ENDIF}
  {$ENDIF}
  {$DEFINE HAS_GetObjectProp}
  {$DEFINE HAS_TObjectList}
  {$DEFINE HAS_StrToInt64Def}
  {$DEFINE HAS_PCardinal}
  {$DEFINE HAS_PByte}
  {$DEFINE HAS_PWord}
  {$DEFINE HAS_PPointer}
  {$DEFINE HAS_TList_Assign}
  {$DEFINE HAS_sLineBreak}
  {$DEFINE HAS_RaiseLastOSError}
  {$DEFINE HAS_SysUtils_IncludeExcludeTrailingPathDelimiter}
  {$DEFINE HAS_SysUtils_DirectoryExists}
  {$DEFINE HAS_UNIT_DateUtils}
  {$DEFINE HAS_UNIT_StrUtils}
  {$DEFINE HAS_UNIT_Types}
  {$DEFINE HAS_TryStrToInt}
  {$DEFINE HAS_TryStrToInt64}
  {$DEFINE HAS_TryEncodeDate}
  {$DEFINE HAS_TryEncodeTime}
  {$DEFINE HAS_ENUM_ELEMENT_VALUES}
  {$IFNDEF FPC}
    {$DEFINE HAS_IInterface}
    {$DEFINE HAS_TSelectionEditor}
    {$DEFINE HAS_TStringList_CaseSensitive}
    {$DEFINE HAS_AcquireExceptionObject}
    {$IFNDEF KYLIX}
      {$DEFINE HAS_DEPRECATED}
      {$DEFINE HAS_SYMBOL_PLATFORM}
      {$DEFINE HAS_UNIT_PLATFORM}
      {$IFNDEF VCL_8_OR_ABOVE}
        // Delphi 6 and 7 have an annoying bug that if a class method is declared as
        // deprecated, the compiler will emit a "symbol is deprecated" warning
        // on the method's implementation!  So we will have to wrap implementations
        // of deprecated methods with {$WARN SYMBOL_DEPRECATED OFF} directives
        // to disable that warning.
        {$DEFINE DEPRECATED_IMPL_BUG}
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}
  {$IFNDEF DOTNET}
    //Widget defines are omitted in .NET
    {$DEFINE VCL_60_PLUS}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_7_OR_ABOVE}
  {$IFNDEF FPC}
    {$DEFINE HAS_UInt64} // Note: it was just an alias for Int64 until D2006!
    {$DEFINE HAS_NAMED_THREADS}
    {$DEFINE HAS_TStrings_NameValueSeparator}
    {$DEFINE HAS_TStrings_ValueFromIndex}
  {$ENDIF}
  {$DEFINE HAS_TFormatSettings}
  {$DEFINE HAS_PosEx}
  {$IFNDEF VCL_70}
    // not implemented in D7
    {$DEFINE HAS_STATIC_TThread_Queue}
  {$ENDIF}
  {$IFNDEF CIL}
    {$IFNDEF VCL_80}
      // not implemented in D8 or .NET
      {$DEFINE HAS_STATIC_TThread_Synchronize}
    {$ENDIF}
  {$ENDIF}
{$ELSE}
  {$IFDEF CBUILDER_6}
    {$DEFINE HAS_NAMED_THREADS}
  {$ENDIF}
{$ENDIF}

{$IFNDEF VCL_2005_OR_ABOVE}
  {$IFDEF DCC}
    // InterlockedCompareExchange() was declared in the Windows unit using Pointer
    // parameters until Delphi 2005, when it was switched to Longint parameters
    // instead to match the actual Win32 API declaration.
    {$DEFINE HAS_InterlockedCompareExchange_Pointers}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2006_OR_ABOVE}
  {$DEFINE USE_INLINE}
  {$DEFINE HAS_2PARAM_FileAge}
  {$DEFINE HAS_TStrings_LineBreak} // TODO: when was LineBreak introduced?
  {$IFDEF WINDOWS}
    // System.RegisterExpectedMemoryLeak() is only available on Windows at this time
    {$DEFINE HAS_System_RegisterExpectedMemoryLeak}
  {$ENDIF}
  // In C++Builder 2006 and 2007, UInt64 is emitted as signed __int64 in HPP
  // files instead of as unsigned __int64.  This causes conflicts in overloaded
  // routines that have (U)Int64 parameters.  This was fixed in C++Builder 2009...
  {$IFDEF CBUILDER}
    {$DEFINE BROKEN_UINT64_HPPEMIT}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2007_OR_ABOVE}
  {$IFNDEF CBUILDER_2007}
    // class properties are broken in C++Builder 2007, causing AVs at compile-time
    {$DEFINE HAS_CLASSPROPERTIES}
  {$ENDIF}
  // Native(U)Int exist but are buggy, so do not use them yet
  {.$DEFINE HAS_NativeInt}
  {.$DEFINE HAS_NativeUInt}
  {$DEFINE HAS_DWORD_PTR}
  {$DEFINE HAS_ULONG_PTR}
  {$DEFINE HAS_ULONGLONG}
  {$DEFINE HAS_PGUID}
  {$DEFINE HAS_PPAnsiChar}
  {$DEFINE HAS_CurrentYear}
  {$IFNDEF DOTNET}
    {$DEFINE HAS_TIMEUNITS}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_2009_OR_ABOVE}
  {$IFNDEF DOTNET}
    {$DEFINE STRING_IS_UNICODE}
    {$DEFINE HAS_UnicodeString}
    {$DEFINE HAS_TEncoding}
    {$DEFINE HAS_TCharacter}
    {$DEFINE HAS_InterlockedCompareExchangePointer}
    {$DEFINE HAS_WIDE_TCharArray}
    {$DEFINE HAS_PUInt64}
    {$IFDEF VCL_2009}
      // TODO: need to differentiate between RTM and Update 1
      // FmtStr() is broken in RTM but was fixed in Update 1
      {$DEFINE BROKEN_FmtStr}
    {$ENDIF}
  {$ENDIF}
  {$DEFINE HAS_CLASSVARS}
  {$DEFINE HAS_DEPRECATED_MSG}
  {$DEFINE HAS_TBytes}
  // Native(U)Int are still buggy, so do not use them yet
  {.$DEFINE HAS_NativeInt}
  {.$DEFINE HAS_NativeUInt}
  {$DEFINE HAS_Int8}
  {$DEFINE HAS_UInt8}
  {$DEFINE HAS_Int16}
  {$DEFINE HAS_UInt16}
  {$DEFINE HAS_Int32}
  {$DEFINE HAS_UInt32}
  {$DEFINE HAS_UIntToStr}
  // UInt64 is now emitted as unsigned __int64 in HPP files
  {$IFDEF CBUILDER}
    {$UNDEF BROKEN_UINT64_HPPEMIT}
  {$ENDIF}
  {$IFDEF DCC}
    {$IFDEF WINDOWS}
      // Exception.RaiseOuterException() is only available on Windows at this time
      {$DEFINE HAS_Exception_RaiseOuterException}
    {$ENDIF}
  {$ENDIF}
  {$DEFINE HAS_SetCodePage}
  {$DEFINE HAS_PRawByteString}
  {$DEFINE HAS_TThreadProcedure}
{$ENDIF}

{$IFDEF VCL_2010_OR_ABOVE}
  {$DEFINE HAS_CLASSCONSTRUCTOR}
  {$DEFINE HAS_CLASSDESTRUCTOR}
  {$DEFINE HAS_DELAYLOAD}
  {$DEFINE HAS_TThread_NameThreadForDebugging}
  {$DEFINE DEPRECATED_TThread_SuspendResume}
  // Native(U)Int are finally ok to use now
  {$DEFINE HAS_NativeInt}
  {$DEFINE HAS_NativeUInt}
  {$DEFINE HAS_USHORT}
  {$DEFINE HAS_IOUtils_TPath}
{$ENDIF}

{$IFDEF VCL_XE_OR_ABOVE}
  {$DEFINE HAS_TFormatSettings_Object}
  {$DEFINE HAS_LocaleCharsFromUnicode}
  {$DEFINE HAS_UnicodeFromLocaleChars}
  {$DEFINE HAS_PLongBool}
  {$DEFINE HAS_PVOID}
  {$DEFINE HAS_ULONG64}
  {$DEFINE HAS_TEncoding_GetEncoding_ByEncodingName}
  {$DEFINE HAS_DateUtils_TTimeZone}
  {$IFDEF DCC}
    // Exception.RaiseOuterException() is now available on all platforms
    {$DEFINE HAS_Exception_RaiseOuterException}
  {$ENDIF}
  {$IFNDEF DOTNET}
    {$DEFINE HAS_TInterlocked}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_XE2_OR_ABOVE}
  {$DEFINE HAS_SIZE_T}
  {$DEFINE HAS_PSIZE_T}
  {$DEFINE HAS_SSIZE_T}
  {$DEFINE HAS_PSSIZE_T}
  {$DEFINE HAS_LONG}
  {$DEFINE HAS_ComponentPlatformsAttribute}
  {$DEFINE HAS_ComponentPlatformsAttribute_Win32}
  {$DEFINE HAS_ComponentPlatformsAttribute_Win64}
  {$DEFINE HAS_ComponentPlatformsAttribute_OSX32}
  {$DEFINE HAS_System_ReturnAddress}
  {$DEFINE HAS_DIRECTIVE_WARN_DEFAULT}
{$ENDIF}

{$IFDEF VCL_XE3_OR_ABOVE}
  {$DEFINE HAS_DIRECTIVE_ZEROBASEDSTRINGS}
  {$DEFINE HAS_SysUtils_TStringHelper}
  {$IFDEF NEXTGEN}
    {$DEFINE DCC_NEXTGEN}
    {$DEFINE HAS_MarshaledAString}
    {$DEFINE USE_MARSHALLED_PTRS}
    {$IFDEF AUTOREFCOUNT}
      {$DEFINE USE_OBJECT_ARC}
    {$ENDIF}
  {$ENDIF}
  // technically, these are present in XE3, but they are not used yet
  {.$DEFINE HAS_ComponentPlatformsAttribute_iOS_Simulator}
  {.$DEFINE HAS_ComponentPlatformsAttribute_Android}
  {.$DEFINE HAS_ComponentPlatformsAttribute_Linux32}
  {.$DEFINE HAS_ComponentPlatformsAttribute_iOS_Device}
  {.$DEFINE HAS_ComponentPlatformsAttribute_WinNX32}
{$ENDIF}

{$IFDEF VCL_XE4_OR_ABOVE}
  {$DEFINE HAS_AnsiStrings_StrPLCopy}
  {$DEFINE HAS_AnsiStrings_StrLen}
  {$DEFINE HAS_Character_TCharHelper}
  {$DEFINE HAS_ComponentPlatformsAttribute_iOS_Simulator}
  {$DEFINE HAS_ComponentPlatformsAttribute_iOS_Device}
{$ENDIF}

{$IFDEF VCL_XE5_OR_ABOVE}
  {$DEFINE HAS_ComponentPlatformsAttribute_Android}
{$ENDIF}

{$IFDEF VCL_XE5_UPDATE2_OR_ABOVE}
  {$DEFINE HAS_DIRECTIVE_HPPEMIT_LINKUNIT}
  {$DEFINE HAS_DIRECTIVE_HPPEMIT_NAMESPACE}
{$ENDIF}

{$IFDEF VCL_XE7_OR_ABOVE}
  {$DEFINE HAS_TNetEncoding}
{$ENDIF}

{$IFDEF VCL_XE8_OR_ABOVE}
  {$DEFINE HAS_ComponentPlatformsAttribute_iOS_Device32}
  {$DEFINE HAS_ComponentPlatformsAttribute_iOS_Device64}
  // technically, these are present in XE8, but they are not used yet
  {.$DEFINE HAS_ComponentPlatformsAttribute_Linux64}
  {.$DEFINE HAS_ComponentPlatformsAttribute_WinIoT32}
{$ENDIF}

{$IFDEF VCL_10_0_OR_ABOVE}
  {$IFDEF ANDROID}
    {$DEFINE HAS_TAndroidHelper}
  {$ENDIF}
  // technically, these are present in 10.0 Seattle, but they are not used yet
  {.$DEFINE HAS_ComponentPlatformsAttribute_WinARM}
{$ENDIF}

{$IFDEF VCL_10_1_OR_ABOVE}
  {$DEFINE HAS_DIRECTIVE_HPPEMIT_LEGACYHPP}
  {$DEFINE HAS_TStrings_AddPair}
  // technically, these are present in 10.1 Berlin, but they are not used yet
  {.$DEFINE HAS_ComponentPlatformsAttribute_OSX64}
  {.$DEFINE HAS_ComponentPlatformsAttribute_OSXNX64}
  {.$DEFINE HAS_ComponentPlatformsAttribute_Linux32Arm}
  {.$DEFINE HAS_ComponentPlatformsAttribute_Linux64Arm}
  {.$DEFINE HAS_ComponentPlatformsAttribute_Android64}
{$ENDIF}

{$IFDEF VCL_10_2_OR_ABOVE}
  {.$WARN IMPLICIT_INTEGER_CAST_LOSS OFF}
  {.$WARN IMPLICIT_CONVERSION_LOSS OFF}
  {.$WARN COMBINING_SIGNED_UNSIGNED64 OFF}
  {$DEFINE HAS_STATIC_TThread_ForceQueue}
  // In Delphi 10.2 Tokyo, TThread.ForceQueue() is broken on Android, the
  // passed in procedure is called immediately instead of being delayed!
  {$IFDEF ANDROID}
    {$DEFINE BROKEN_TThread_ForceQueue}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_3_OR_ABOVE}
  {$DEFINE HAS_ComponentPlatformsAttribute_iOS_Simulator32}
  {$DEFINE HAS_ComponentPlatformsAttribute_Android32Arm}
  {$DEFINE HAS_ComponentPlatformsAttribute_WinARM32}
  {$UNDEF HAS_ComponentPlatformsAttribute_OSXNX64} // removed in 10.3 Rio
  // technically, these are present in 10.3 Rio, but they are not used yet
  {.$DEFINE HAS_ComponentPlatformsAttribute_iOS_Simulator64}
  {$IFDEF DCC}
    {$IFDEF LINUX}
      // RLebeau 9/25/2019: there is a bug in the IDE when debugging Linux projects
      // where the EThreadNameException exception raised by TThread.NameThreadForDebugging()
      // is not handled correctly.
      {$UNDEF HAS_NAMED_THREADS}
    {$ENDIF}
  {$ENDIF}
  {$IFDEF ANDROID}
    {$UNDEF BROKEN_TThread_ForceQueue}
  {$ENDIF}
{$ENDIF}

{$IFDEF VCL_10_3_UPDATE2_OR_ABOVE}
  {$DEFINE HAS_ComponentPlatformsAttribute_AllPlatforms}
  {$DEFINE HAS_ComponentPlatformsAttribute_OSX64}
{$ENDIF}

{$IFDEF VCL_10_4_OR_ABOVE}
  // 0-based string indexing via '[]' is turned off by default in Delphi 10.4.
  // TStringHelper is always 0-indexed, flat RTL functions are always 1-indexed,
  // and now '[]' is 1-indexed again on all platforms - {$ZEROBASEDSTRINGS OFF}
  // is the default.
  {.$UNDEF HAS_DIRECTIVE_ZEROBASEDSTRINGS}
{$ENDIF}

{$IFDEF VCL_11_OR_ABOVE}
  {$DEFINE HAS_ComponentPlatformsAttribute_AndroidArm32}
  {$DEFINE HAS_ComponentPlatformsAttribute_AndroidArm64}
  {$DEFINE HAS_ComponentPlatformsAttribute_OSXArm64}
{$ENDIF}

{$IFDEF FPC}
  {$DEFINE USE_INLINE}
{$ENDIF}

{$IFDEF WIN32}
  {$DEFINE USE_DESIGNIDE}
{$ENDIF}
{$IFDEF WIN64}
  {$IFDEF FPC}
    {$DEFINE USE_DESIGNIDE}
  {$ENDIF}
  {$IFDEF VER360}
    {$IF DECLARED(RTLVersion123)}
      {$DEFINE USE_DESIGNIDE}
    {$IFEND}
  {$ENDIF}
{$ENDIF}
