"""Keep Android's system launch surface consistent with the app's two palettes."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'godot/android/build'
APPEARANCE_XML='''<?xml version="1.0" encoding="utf-8"?>
<resources>
  <style name="ShogiLightSplash" parent="GodotAppSplashTheme">
    <item name="windowSplashScreenBackground">#eeeae4</item>
    <item name="android:windowSplashScreenBackground">#eeeae4</item>
    <item name="postSplashScreenTheme">@style/ShogiLightMain</item>
  </style>
  <style name="ShogiDarkSplash" parent="GodotAppSplashTheme">
    <item name="windowSplashScreenBackground">#25180f</item>
    <item name="android:windowSplashScreenBackground">#25180f</item>
    <item name="postSplashScreenTheme">@style/ShogiDarkMain</item>
  </style>
  <style name="ShogiLightMain" parent="GodotAppMainTheme">
    <item name="android:windowBackground">#eeeae4</item>
    <item name="android:colorAccent">#238cd4</item>
  </style>
  <style name="ShogiDarkMain" parent="GodotAppMainTheme">
    <item name="android:windowBackground">#25180f</item>
    <item name="android:colorAccent">#2395ed</item>
  </style>
</resources>
'''


def configure_activity(text: str) -> str:
    if '// Shogi appearance' not in text:
        text=text.replace('SplashScreen splashScreen = SplashScreen.installSplashScreen(this);','''// Shogi appearance: apply the saved palette before the first activity frame.
        String mode = getSharedPreferences("shogi_appearance", MODE_PRIVATE).getString("mode", "system");
        boolean night = "dark".equals(mode) || ("system".equals(mode) &&
            (getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) != android.content.res.Configuration.UI_MODE_NIGHT_NO);
        setTheme(night ? R.style.ShogiDarkSplash : R.style.ShogiLightSplash);
        SplashScreen splashScreen = SplashScreen.installSplashScreen(this);''')
    text=text.replace('== android.content.res.Configuration.UI_MODE_NIGHT_YES', '!= android.content.res.Configuration.UI_MODE_NIGHT_NO')
    text=text.replace('getString("mode", "system")', 'getString("mode", "dark")')
    # AndroidX implements this condition with an OnPreDrawListener that returns
    # false. Waiting for a rendered board here can prevent the SurfaceView from
    # ever drawing the frame that would release it. Use automatic splash removal.
    # Migrate both the pristine template and already-generated 0.6.0/0.6.1 builds.
    text=re.sub(
        r'\n[ \t]*Godot godot = getGodot\(\);\s*'
        r'if \(godot != null && godot\.getDisableGodotSplash\(\)\) \{\s*'
        r'splashScreen\.setKeepOnScreenCondition\(\(\) -> '
        r'(?:godot\.getRunStatus\(\) != Godot\.RunStatus\.STARTED|'
        r'!org\.shogistudio\.platform\.ShogiPlatform\.isBoardFrameReady\(\))\);\s*\}',
        '', text)
    text=text.replace('SplashScreen splashScreen = SplashScreen.installSplashScreen(this);',
                      'SplashScreen.installSplashScreen(this);')
    if ('setKeepOnScreenCondition' in text or 'isBoardFrameReady' in text
            or '// Shogi appearance' not in text
            or text.count('SplashScreen.installSplashScreen(this);') != 1):
        raise ValueError('Unrecognized Android launch template; refusing to export a potentially blocked startup')
    return text


def main() -> None:
    activity=BUILD/'src/main/java/com/godot/game/GodotApp.java'
    text=configure_activity(activity.read_text(encoding='utf-8'))
    (BUILD/'res/values/shogi_appearance.xml').write_text(APPEARANCE_XML,encoding='utf-8')
    activity.write_text(text,encoding='utf-8')
    print('Android launch palettes configured; first draw is not blocked by a splash condition')


if __name__ == '__main__':
    main()
