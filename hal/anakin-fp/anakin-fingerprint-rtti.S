/* Minimal Itanium RTTI objects for GSI HIDL fingerprint interfaces on ASUS ROG Phone 5 (ANAKIN). */
.section .rodata
.align 3
.Lname_v21: .asciz "N7android8hardware10biometrics11fingerprint4V2_122IBiometricsFingerprintE"
.Lname_c21: .asciz "N7android8hardware10biometrics11fingerprint4V2_136IBiometricsFingerprintClientCallbackE"
.Lname_v22: .asciz "N7android8hardware10biometrics11fingerprint4V2_222IBiometricsFingerprintE"
.Lname_c22: .asciz "N7android8hardware10biometrics11fingerprint4V2_236IBiometricsFingerprintClientCallbackE"
.Lname_v23: .asciz "N7android8hardware10biometrics11fingerprint4V2_322IBiometricsFingerprintE"
.Lname_c23: .asciz "N7android8hardware10biometrics11fingerprint4V2_336IBiometricsFingerprintClientCallbackE"
.Lname_refbase: .asciz "N7android7RefBaseE"
.Lname_ibase: .asciz "N7android4hidl4base4V1_05IBaseE"
.Lname_bnbase: .asciz "N7android4hidl4base4V1_08BnHwBaseE"
.Lname_iinterface: .asciz "N7android8hardware10IInterfaceE"
.Lname_bphwrefbase: .asciz "N7android8hardware11BpHwRefBaseE"
.Lname_ibinder: .asciz "N7android8hardware7IBinderE"
.Lname_hidl_instrumentor: .asciz "N7android8hardware7details16HidlInstrumentorE"
.Lname_bhwbinder: .asciz "N7android8hardware9BHwBinderE"

.macro RTTI symbol, name
.section .data.rel.ro
.align 3
.global \symbol
.type \symbol, %object
\symbol:
    .xword _ZTVN10__cxxabiv117__class_type_infoE + 16
    .xword \name
.size \symbol, .-\symbol
.endm

/* A HIDL interface has one non-virtual interface base. */
.macro SI_RTTI symbol, name, base
.section .data.rel.ro
.align 3
.global \symbol
.type \symbol, %object
\symbol:
    .xword _ZTVN10__cxxabiv120__si_class_type_infoE + 16
    .xword \name
    .xword \base
.size \symbol, .-\symbol
.endm

/* IBase is a weak RTTI definition in libhidlbase on this GSI. */
.macro WEAK_RTTI symbol, name
.section .data.rel.ro
.align 3
.weak \symbol
.type \symbol, %object
\symbol:
    .xword _ZTVN10__cxxabiv117__class_type_infoE + 16
    .xword \name
.size \symbol, .-\symbol
.endm

/* A HIDL helper with a virtual android::RefBase base. */
.macro VMI_RTTI symbol, name, base
.section .data.rel.ro
.align 3
.weak \symbol
.type \symbol, %object
\symbol:
    .xword _ZTVN10__cxxabiv121__vmi_class_type_infoE + 16
    .xword \name
    .word 0
    .word 1
    .xword \base
    .xword -8189
.size \symbol, .-\symbol
.endm

WEAK_RTTI _ZTIN7android7RefBaseE, .Lname_refbase

VMI_RTTI _ZTIN7android8hardware10IInterfaceE, .Lname_iinterface, \
    _ZTIN7android7RefBaseE

SI_RTTI _ZTIN7android4hidl4base4V1_05IBaseE, .Lname_ibase, \
    _ZTIN7android8hardware10IInterfaceE

/* The GSI's generated libraries do not export the RTTI for the legacy
 * fingerprint interfaces.  V2.3 is emitted by its interface library, but
 * that library has relocations against V2.2, while the V2.2 compatibility
 * library in this build exports no _ZTI objects at all.  Provide the missing
 * V2.1/V2.2 chain here and leave the native V2.3 objects untouched. */
SI_RTTI _ZTIN7android8hardware10biometrics11fingerprint4V2_122IBiometricsFingerprintE, .Lname_v21, \
    _ZTIN7android4hidl4base4V1_05IBaseE
SI_RTTI _ZTIN7android8hardware10biometrics11fingerprint4V2_136IBiometricsFingerprintClientCallbackE, .Lname_c21, \
    _ZTIN7android4hidl4base4V1_05IBaseE
SI_RTTI _ZTIN7android8hardware10biometrics11fingerprint4V2_222IBiometricsFingerprintE, .Lname_v22, \
    _ZTIN7android8hardware10biometrics11fingerprint4V2_122IBiometricsFingerprintE
SI_RTTI _ZTIN7android8hardware10biometrics11fingerprint4V2_236IBiometricsFingerprintClientCallbackE, .Lname_c22, \
    _ZTIN7android8hardware10biometrics11fingerprint4V2_136IBiometricsFingerprintClientCallbackE

/* Common HIDL RTTI omitted from the Android 16 GSI libraries. */
RTTI _ZTIN7android8hardware7details16HidlInstrumentorE, .Lname_hidl_instrumentor
VMI_RTTI _ZTIN7android8hardware11BpHwRefBaseE, .Lname_bphwrefbase, \
    _ZTIN7android7RefBaseE
VMI_RTTI _ZTIN7android8hardware7IBinderE, .Lname_ibinder, \
    _ZTIN7android7RefBaseE
SI_RTTI _ZTIN7android8hardware9BHwBinderE, .Lname_bhwbinder, \
    _ZTIN7android8hardware7IBinderE

/* BnHwBase is the HIDL wrapper over BHwBinder. */
SI_RTTI _ZTIN7android4hidl4base4V1_08BnHwBaseE, .Lname_bnbase, \
    _ZTIN7android8hardware9BHwBinderE

.section .data.rel.ro
.align 3
.global anakin_iBase_typeinfo
.type anakin_iBase_typeinfo, %object
anakin_iBase_typeinfo:
    .xword _ZTIN7android4hidl4base4V1_05IBaseE
.size anakin_iBase_typeinfo, .-anakin_iBase_typeinfo
