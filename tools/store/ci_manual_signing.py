#!/usr/bin/env python3
"""CI only: switch the Release configurations of the app and widget targets to
manual signing with the App Store profiles, so `xcodebuild archive` on a runner
that holds only the Apple Distribution certificate can sign without Xcode's
cloud signing. Never commit the result; the repo keeps automatic signing so
local device builds keep working."""
import re, sys

PBX = 'ios/Runner.xcodeproj/project.pbxproj'
PROFILES = {
    'com.matejbaco.cardjigsawworld': 'CJW AppStore cardjigsawworld',
    'com.matejbaco.cardjigsawworld.DailyWidget': 'CJW AppStore DailyWidget',
}
s = open(PBX).read()
blocks = re.split(r'(?=\n\t\t[0-9A-F]{24} /\* (?:Release|Profile) \*/ = \{)', s)
out = [blocks[0]]
patched = 0
for b in blocks[1:]:
    head, _, rest = b.partition('};')
    m = re.search(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', head)
    bid = m.group(1) if m else None
    if bid in PROFILES:
        manual = ('CODE_SIGN_STYLE = Manual;\n\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";\n'
                  '\t\t\t\t"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";\n'
                  '\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "%s";' % PROFILES[bid])
        head = re.sub(r'CODE_SIGN_STYLE = \w+;', '', head)
        head = re.sub(r'CODE_SIGN_IDENTITY[^\n]*\n', '', head)
        head = re.sub(r'PROVISIONING_PROFILE_SPECIFIER[^\n]*\n', '', head)
        head = head.replace('PRODUCT_BUNDLE_IDENTIFIER = %s;' % bid, 'PRODUCT_BUNDLE_IDENTIFIER = %s;\n\t\t\t\t%s' % (bid, manual), 1)
        patched += 1
    out.append(head + '};' + rest)
open(PBX, 'w').write(''.join(out))
print('patched', patched, 'configurations')
if patched < 2:
    sys.exit('expected at least 2 configurations (app + widget Release)')
