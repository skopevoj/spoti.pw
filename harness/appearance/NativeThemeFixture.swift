import Foundation

// A real native Swift class and an independent main store. This deliberately does not inherit
// NSObject or share storage with the ObjC mock. The production bridge resolves these exact ABI
// symbols through dlsym, so its calling convention and ownership are tested too.
public final class NativeTheme {
    public let light: Bool
    init(_ light: Bool) { self.light = light }
}
private let dark = NativeTheme(false)
private let light = NativeTheme(true)
private var main = dark

@_silgen_name("$s16EncoreFoundation0A0O10ColorThemeC0A8_CoreKitE4mainAEvgZ")
public func getMain() -> NativeTheme { main }
@_silgen_name("$s16EncoreFoundation0A0O10ColorThemeC0A8_CoreKitE4mainAEvsZ")
public func setMain(_ value: __owned NativeTheme) {
    if ProcessInfo.processInfo.environment["SG_TEST_REJECT_NATIVE_THEME"] != "1" { main = value }
}
@_silgen_name("$s16EncoreFoundation0A0O10ColorThemeC5lightAEvgZ")
public func getLight() -> NativeTheme { light }
@_silgen_name("$s16EncoreFoundation0A0O10ColorThemeC4darkAEvgZ")
public func getDark() -> NativeTheme { dark }

@_cdecl("SGTestNativeIsLight")
public func nativeIsLight() -> Bool { main.light }
@_cdecl("SGTestNativeSetDark")
public func nativeSetDark() { main = dark }
