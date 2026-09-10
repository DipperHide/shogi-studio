"""Regression checks for fresh and previously generated Android launch templates.

These check build-time migration, not a physical device's rendering or drivers.
"""
import json
from pathlib import Path
import unittest
from zipfile import ZipFile

from configure_android_appearance import configure_activity


class AndroidStartupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        toolchain = json.loads((Path.home() / 'Development/toolchain.json').read_text('utf-8-sig'))
        template = (Path(toolchain['godot']).parent / 'editor_data/export_templates'
                    / (toolchain['godotVersion'] + '.stable') / 'android_source.zip')
        with ZipFile(template) as archive:
            cls.original = archive.read('src/main/java/com/godot/game/GodotApp.java').decode('utf-8')

    def assert_unblocked(self, activity):
        self.assertNotIn('setKeepOnScreenCondition', activity)
        self.assertNotIn('isBoardFrameReady', activity)
        self.assertNotIn('org.shogistudio.platform', activity)
        self.assertEqual(activity.count('SplashScreen.installSplashScreen(this);'), 1)
        self.assertLess(activity.index('setTheme(night ?'), activity.index('SplashScreen.installSplashScreen'))
        self.assertLess(activity.index('SplashScreen.installSplashScreen'), activity.index('super.onCreate(savedInstanceState)'))
        # Window lifecycle callbacks must survive removal of the startup gate.
        self.assertIn('godot.enableImmersiveMode', activity)
        self.assertIn('super.onGodotMainLoopStarted();', activity)
        self.assertIn('super.onResume();', activity)

    def test_pristine_godot_template(self):
        self.assert_unblocked(configure_activity(self.original))

    def test_previous_board_frame_wait_is_removed(self):
        old = self.original.replace('() -> godot.getRunStatus() != Godot.RunStatus.STARTED',
                                    '() -> !org.shogistudio.platform.ShogiPlatform.isBoardFrameReady()')
        self.assertIn('isBoardFrameReady', old)
        self.assert_unblocked(configure_activity(old))

    def test_repeated_builds_preserve_the_same_activity(self):
        fixed = configure_activity(self.original)
        self.assertEqual(configure_activity(fixed), fixed)

    def test_unknown_drawing_gate_fails_the_build(self):
        changed = self.original.replace('godot.getRunStatus() != Godot.RunStatus.STARTED', 'true')
        with self.assertRaises(ValueError):
            configure_activity(changed)

    def test_unknown_installation_template_fails_the_build(self):
        with self.assertRaises(ValueError):
            configure_activity('public class GodotApp {}')


if __name__ == '__main__':
    unittest.main(verbosity=2)
